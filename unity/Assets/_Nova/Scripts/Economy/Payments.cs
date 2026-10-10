using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;

namespace NovaMobile.Economy
{
    /// <summary>
    /// Flutterwave payment module — buys NOVA Points with REAL money.
    /// Ported from Godot scripts/payments.gd.
    ///
    /// Interface: Payments.Purchase(packId) starts checkout; C# events
    /// Completed(packId, np, txRef) / Failed(packId, reason) deliver results.
    ///
    /// MODES:
    ///  - "test": fully simulated checkout. NO real money moves, NO network
    ///    calls (zero UnityWebRequests are created in this mode). Default.
    ///  - "live": real Flutterwave checkout. The game NEVER holds the secret
    ///    key (it would ship inside the APK). The game POSTs to the NOVA
    ///    payments backend (server/nova_payments_server.py, holds FLW_SECRET_KEY
    ///    as an env var) for a hosted checkout link, opens it in the OS
    ///    browser, then polls the backend until it confirms payment before
    ///    crediting NP.
    ///
    /// Config: Application.persistentDataPath/flutterwave_config.json:
    ///   {"mode": "live", "backend_url": "https://your-host:8777"}
    /// Live mode is refused without a real https:// backend URL (accident guard).
    ///
    /// KEYS ARE NEVER HARDCODED. No secret key is stored in the game, ever.
    /// In test mode the file may say {"mode": "test"} or not exist at all.
    /// </summary>
    public class Payments : MonoBehaviour
    {
        public const string TestMode = "test";
        public const string LiveMode = "live";

        private const string ConfigFileName = "flutterwave_config.json";
        private const string PlaceholderHostMarker = "your-host";
        private const int MaxVerifyAttempts = 40;   // ~10 minutes of polling
        private const float VerifyInterval = 15f;

        [Serializable]
        private class PaymentsConfig
        {
            public string mode = "test";
            public string backend_url = "";
            public string note = "";
        }

        [Serializable]
        private class CreateLinkResponse
        {
            public string link = "";
            public string tx_ref = "";
            public string error = "";
        }

        [Serializable]
        private class VerifyResponse
        {
            public bool paid;
            public string tx_ref = "";
            public string status = "";
        }

        public event Action<string, int, string> Completed;   // packId, np, txRef
        public event Action<string, string> Failed;           // packId, reason

        public enum SimulatedResult { Success, Fail, Cancel }

        private string _mode = TestMode;
        private string _backendUrl = "";
        private SimulatedResult _simulatedResult = SimulatedResult.Success;
        private string _pendingPack = "";
        private string _pendingTxRef = "";
        private bool _purchaseInFlight;

        public string Mode
        {
            get { return _mode; }
        }

        public bool IsTestMode
        {
            get { return _mode == TestMode; }
        }

        private void Awake()
        {
            LoadConfig();
        }

        private void LoadConfig()
        {
            _mode = TestMode;
            _backendUrl = "";
            string path = Path.Combine(Application.persistentDataPath, ConfigFileName);
            if (!File.Exists(path)) return;
            try
            {
                var cfg = JsonUtility.FromJson<PaymentsConfig>(File.ReadAllText(path));
                if (cfg == null) return;
                if (cfg.mode == LiveMode)
                {
                    string backend = (cfg.backend_url ?? "").Trim();
                    // Accident guard: refuse live without a real https backend URL.
                    if (backend.Length > 0
                        && backend.StartsWith("https://")
                        && backend.IndexOf(PlaceholderHostMarker, StringComparison.Ordinal) < 0)
                    {
                        _mode = LiveMode;
                        _backendUrl = backend.TrimEnd('/');
                    }
                }
            }
            catch (Exception e)
            {
                Debug.LogWarning("[Payments] bad config, staying in test mode: " + e.Message);
            }
        }

        /// <summary>Writes the documented config template (test mode default).</summary>
        public static void WriteConfigTemplate()
        {
            var cfg = new PaymentsConfig
            {
                mode = TestMode,
                backend_url = "https://your-host:8777",
                note = "Live mode needs the NOVA payments backend (server/nova_payments_server.py) "
                     + "hosted with FLW_SECRET_KEY set. The game never stores the secret key.",
            };
            File.WriteAllText(
                Path.Combine(Application.persistentDataPath, ConfigFileName),
                JsonUtility.ToJson(cfg, true));
        }

        /// <summary>Test hook: force the next simulated checkout outcome.</summary>
        public void SetSimulatedResult(SimulatedResult r) { _simulatedResult = r; }

        /// <summary>Start buying an NP pack. Unknown pack ids fail immediately.</summary>
        public void Purchase(string packId)
        {
            NpPack pack = StoreData.NpPackById(packId);
            if (pack.Id == null)
            {
                if (Failed != null) Failed(packId, "unknown pack");
                return;
            }
            if (_purchaseInFlight)
            {
                if (Failed != null) Failed(packId, "another purchase is in progress");
                return;
            }
            _purchaseInFlight = true;
            _pendingPack = packId;
            if (_mode == TestMode)
                StartCoroutine(SimulateCheckout(pack));
            else
                StartCoroutine(LiveCheckout(pack));
        }

        // ------------------------------------------------- TEST checkout ---
        // Zero network, zero money, deterministic outcomes.

        private IEnumerator SimulateCheckout(NpPack pack)
        {
            yield return new WaitForSeconds(0.6f);
            _purchaseInFlight = false;
            string txRef = "TEST-" + pack.Id + "-" + DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            switch (_simulatedResult)
            {
                case SimulatedResult.Success:
                    VerifyAndCredit(pack.Id, txRef, true);
                    break;
                case SimulatedResult.Cancel:
                    if (Failed != null) Failed(pack.Id, "user cancelled");
                    break;
                default:
                    if (Failed != null) Failed(pack.Id, "payment declined (test)");
                    break;
            }
        }

        // ------------------------------------------------- LIVE checkout ---
        // Backend creates the Flutterwave hosted link; the OS browser opens
        // it; we poll the backend until it confirms payment. The secret key
        // lives only on the backend server, never in the game.

        private IEnumerator LiveCheckout(NpPack pack)
        {
            if (_backendUrl == "")
            {
                _purchaseInFlight = false;
                if (Failed != null) Failed(pack.Id, "live backend not configured");
                yield break;
            }

            string url = _backendUrl + "/create-link";
            string body = JsonUtility.ToJson(new CreateLinkRequest
            {
                pack_id = pack.Id,
                currency = "NGN",
                redirect_url = "https://example.com/nova-purchase-done",
                email = "",
            });
            string link = "";
            using (UnityWebRequest req = new UnityWebRequest(url, UnityWebRequest.kHttpVerbPOST))
            {
                byte[] bytes = System.Text.Encoding.UTF8.GetBytes(body);
                req.uploadHandler = new UploadHandlerRaw(bytes);
                req.downloadHandler = new DownloadHandlerBuffer();
                req.SetRequestHeader("Content-Type", "application/json");
                yield return req.SendWebRequest();
                _purchaseInFlight = false;
                if (req.result != UnityWebRequest.Result.Success)
                {
                    if (Failed != null) Failed(pack.Id, "could not reach payment backend");
                    yield break;
                }
                var parsed = JsonUtility.FromJson<CreateLinkResponse>(req.downloadHandler.text);
                if (parsed == null || string.IsNullOrEmpty(parsed.link))
                {
                    string err = (parsed != null && parsed.error != "") ? parsed.error : "payment link failed";
                    if (Failed != null) Failed(pack.Id, err);
                    yield break;
                }
                _pendingTxRef = parsed.tx_ref;
                link = parsed.link;
            }

            // Open the hosted Flutterwave checkout in the OS browser.
            Application.OpenURL(link);

            // Poll for confirmation (player pays in the browser).
            yield return StartCoroutine(PollVerify(0));
        }

        [Serializable]
        private class CreateLinkRequest
        {
            public string pack_id = "";
            public string currency = "NGN";
            public string redirect_url = "";
            public string email = "";
        }

        private IEnumerator PollVerify(int attempt)
        {
            if (attempt >= MaxVerifyAttempts)
            {
                if (Failed != null) Failed(_pendingPack, "payment not confirmed in time");
                yield break;
            }
            string url = _backendUrl + "/verify?tx_ref=" + UnityWebRequest.EscapeURL(_pendingTxRef);
            using (UnityWebRequest req = UnityWebRequest.Get(url))
            {
                yield return req.SendWebRequest();
                if (req.result == UnityWebRequest.Result.Success)
                {
                    var parsed = JsonUtility.FromJson<VerifyResponse>(req.downloadHandler.text);
                    if (parsed != null && parsed.paid)
                    {
                        VerifyAndCredit(_pendingPack, _pendingTxRef, true);
                        yield break;
                    }
                }
                else
                {
                    Debug.LogWarning("[Payments] verify poll failed, retrying: " + req.error);
                }
            }
            yield return new WaitForSeconds(VerifyInterval);
            yield return StartCoroutine(PollVerify(attempt + 1));
        }

        private void VerifyAndCredit(string packId, string txRef, bool verified)
        {
            if (!verified)
            {
                if (Failed != null) Failed(packId, "verification failed");
                return;
            }
            NpPack pack = StoreData.NpPackById(packId);
            if (pack.Id == null)
            {
                if (Failed != null) Failed(packId, "unknown pack");
                return;
            }
            // CREDIT ONLY AFTER VERIFICATION. Ledger detail records the mode
            // so test grants are always auditable.
            NpWallet.Add(pack.Np, "np pack:" + packId + " tx:" + txRef + " mode:" + _mode);
            if (Completed != null) Completed(packId, pack.Np, txRef);
        }
    }
}
