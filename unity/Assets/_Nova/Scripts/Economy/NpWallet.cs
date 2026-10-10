using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace NovaMobile.Economy
{
    /// <summary>
    /// NOVA Points wallet: persisted NP balance, mythic skin ownership, and a
    /// full transaction ledger (every earn/spend carries a receipt entry).
    /// Ported from Godot scripts/store_wallet.gd.
    ///
    /// Contract (CONVENTIONS.md — implemented EXACTLY):
    ///   Balance (int get), Spend(amount, reason) bool, Add(amount, reason) void,
    ///   OwnsSkin(skinId) bool, UnlockSkin(skinId) void.
    ///
    /// skinId format is the GunsmithUI contract: "<gun_id>_skin_<idx>"
    /// (e.g. "kv47_skin_1"). The empty skinId (standard unskinned look) is
    /// always owned. Spend is atomic: insufficient funds => no debit, no log.
    /// Persistence: JSON at Application.persistentDataPath/nova_wallet.json
    /// (per conventions — never PlayerPrefs). Ledger keeps the newest 200.
    /// </summary>
    public static class NpWallet
    {
        private const string FileName = "nova_wallet.json";
        private const int Version = 1;
        private const int LedgerCap = 200;

        private static int _np;
        private static readonly HashSet<string> _ownedSkins = new HashSet<string>();
        private static readonly HashSet<string> _ownedFlair = new HashSet<string>();
        private static readonly HashSet<string> _ownedBundles = new HashSet<string>();
        private static readonly Dictionary<string, DrawState> _draws = new Dictionary<string, DrawState>();
        private static readonly List<LedgerEntry> _ledger = new List<LedgerEntry>();
        private static bool _loaded;

        // ------------------------------------------------------------- types

        [Serializable]
        private class WalletSave
        {
            public int version;
            public int np;
            public List<string> ownedSkins = new List<string>();
            public List<string> ownedFlair = new List<string>();
            public List<string> ownedBundles = new List<string>();
            public List<DrawEntry> draws = new List<DrawEntry>();
            public List<LedgerEntry> ledger = new List<LedgerEntry>();
        }

        [Serializable]
        private class DrawEntry
        {
            public string id = "";
            public int spins;
            public List<int> won = new List<int>();
        }

        [Serializable]
        private class LedgerEntry
        {
            public long t;
            public string kind = "";
            public int npDelta;
            public int balance;
            public string detail = "";
        }

        public struct DrawState
        {
            public int Spins;
            public List<int> Won;   // item indices already claimed (pool removal)
        }

        public struct Receipt
        {
            public long UnixTime;
            public string Kind;
            public int NpDelta;
            public int Balance;
            public string Detail;
        }

        // -------------------------------------------------------------- load

        private static string SavePath()
        {
            return Path.Combine(Application.persistentDataPath, FileName);
        }

        private static void EnsureLoaded()
        {
            if (_loaded) return;
            _loaded = true;
            string path = SavePath();
            if (!File.Exists(path)) return;
            try
            {
                string json = File.ReadAllText(path);
                var save = JsonUtility.FromJson<WalletSave>(json);
                if (save == null || save.version != Version) return; // old schema: start fresh
                _np = Mathf.Max(0, save.np);
                if (save.ownedSkins != null)
                    foreach (var k in save.ownedSkins) _ownedSkins.Add(k ?? "");
                if (save.ownedFlair != null)
                    foreach (var k in save.ownedFlair) _ownedFlair.Add(k ?? "");
                if (save.ownedBundles != null)
                    foreach (var k in save.ownedBundles) _ownedBundles.Add(k ?? "");
                if (save.draws != null)
                    foreach (var d in save.draws)
                        _draws[d.id] = new DrawState { Spins = d.spins, Won = new List<int>(d.won ?? new List<int>()) };
                if (save.ledger != null)
                    foreach (var e in save.ledger) _ledger.Add(e);
            }
            catch (Exception e)
            {
                Debug.LogWarning("[NpWallet] corrupt save, starting fresh: " + e.Message);
            }
        }

        private static void Save()
        {
            try
            {
                var save = new WalletSave
                {
                    version = Version,
                    np = _np,
                    ownedSkins = new List<string>(_ownedSkins),
                    ownedFlair = new List<string>(_ownedFlair),
                    ownedBundles = new List<string>(_ownedBundles),
                };
                foreach (var kv in _draws)
                    save.draws.Add(new DrawEntry { id = kv.Key, spins = kv.Value.Spins, won = new List<int>(kv.Value.Won) });
                int start = Mathf.Max(0, _ledger.Count - LedgerCap);
                for (int i = start; i < _ledger.Count; i++) save.ledger.Add(_ledger[i]);
                File.WriteAllText(SavePath(), JsonUtility.ToJson(save, true));
            }
            catch (Exception e)
            {
                Debug.LogWarning("[NpWallet] save failed: " + e.Message);
            }
        }

        private static void Log(string kind, int npDelta, string detail)
        {
            _ledger.Add(new LedgerEntry
            {
                t = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                kind = kind,
                npDelta = npDelta,
                balance = _np,
                detail = detail,
            });
            Save();
        }

        /// <summary>Test hook: wipe in-memory + disk state.</summary>
        internal static void ResetForTests()
        {
            _np = 0;
            _ownedSkins.Clear();
            _ownedFlair.Clear();
            _ownedBundles.Clear();
            _draws.Clear();
            _ledger.Clear();
            _loaded = true;
            try { if (File.Exists(SavePath())) File.Delete(SavePath()); } catch { }
        }

        // ------------------------------------------------------------ contract

        /// <summary>Canonical skin id: "<gun_id>_skin_<idx>". Matches GunsmithUI.</summary>
        public static string SkinId(string gunId, int skinIdx)
        {
            return gunId + "_skin_" + skinIdx;
        }

        public static int Balance
        {
            get { EnsureLoaded(); return _np; }
        }

        /// <summary>Grant NP (purchase, promo, compensation). Ignores non-positive amounts.</summary>
        public static void Add(int amount, string reason)
        {
            EnsureLoaded();
            if (amount <= 0) return;
            _np += amount;
            Log("earn", amount, reason);
        }

        /// <summary>
        /// Spend NP atomically. Returns true on success; false when funds are
        /// insufficient (no partial spend, no negative balances).
        /// </summary>
        public static bool Spend(int amount, string reason)
        {
            EnsureLoaded();
            if (amount <= 0) return true;
            if (_np < amount) return false;
            _np -= amount;
            Log("spend", -amount, reason);
            return _np >= 0;
        }

        /// <summary>Skin ownership. Empty skinId = standard look = always owned.</summary>
        public static bool OwnsSkin(string skinId)
        {
            EnsureLoaded();
            if (string.IsNullOrEmpty(skinId)) return true;
            return _ownedSkins.Contains(skinId);
        }

        public static void UnlockSkin(string skinId)
        {
            EnsureLoaded();
            if (string.IsNullOrEmpty(skinId) || _ownedSkins.Contains(skinId)) return;
            _ownedSkins.Add(skinId);
            Log("skin", 0, "unlock | " + skinId);
        }

        // ------------------------------------------------- purchases & grants

        /// <summary>Buy a mythic skin directly (950 NP). False = already owned or broke.</summary>
        public static bool BuySkin(string gunId, int skinIdx)
        {
            EnsureLoaded();
            string key = SkinId(gunId, skinIdx);
            if (OwnsSkin(key)) return false;
            if (!Spend(StoreData.MythicPrice, "skin:" + key)) return false;
            UnlockSkin(key);
            Log("skin", 0, "store purchase | " + key);
            return true;
        }

        public static bool OwnsBundle(string bundleId)
        {
            EnsureLoaded();
            return _ownedBundles.Contains(bundleId);
        }

        /// <summary>Buy a bundle (skin + cards + frame). False = already owned or broke.</summary>
        public static bool BuyBundle(string bundleId)
        {
            EnsureLoaded();
            BundleDef b = StoreData.BundleById(bundleId);
            if (b.Id == null || OwnsBundle(bundleId)) return false;
            if (!Spend(b.Price, "bundle:" + bundleId)) return false;
            _ownedBundles.Add(bundleId);
            UnlockSkin(SkinId(b.Gun, b.SkinIdx));
            GrantFlair(b.Name + " Operator Card");
            GrantFlair(b.Name + " Calling Card");
            GrantFlair(b.Name + " Avatar Frame");
            Log("bundle", 0, "store purchase | " + bundleId);
            return true;
        }

        public static bool OwnsFlair(string label)
        {
            EnsureLoaded();
            return _ownedFlair.Contains(label);
        }

        public static void GrantFlair(string label)
        {
            EnsureLoaded();
            if (string.IsNullOrEmpty(label) || _ownedFlair.Contains(label)) return;
            _ownedFlair.Add(label);
            Log("flair", 0, "grant | " + label);
        }

        // ------------------------------------------------------------ ledger

        public static Receipt[] GetLedger()
        {
            EnsureLoaded();
            Receipt[] outp = new Receipt[_ledger.Count];
            for (int i = 0; i < _ledger.Count; i++)
            {
                LedgerEntry e = _ledger[i];
                outp[i] = new Receipt
                {
                    UnixTime = e.t, Kind = e.kind, NpDelta = e.npDelta,
                    Balance = e.balance, Detail = e.detail,
                };
            }
            return outp;
        }

        // -------------------------------------------------------- draw state

        /// <summary>Persisted per-draw progress: spins used + won item indices.</summary>
        public static DrawState GetDrawState(string drawId)
        {
            EnsureLoaded();
            DrawState st;
            if (!_draws.TryGetValue(drawId, out st))
            {
                st = new DrawState { Spins = 0, Won = new List<int>() };
                _draws[drawId] = st;
            }
            return st;
        }

        public static void RecordDrawWin(string drawId, int wonIdx)
        {
            EnsureLoaded();
            DrawState st = GetDrawState(drawId);
            st.Spins++;
            st.Won.Add(wonIdx);
            _draws[drawId] = st;
            Save();
        }
    }
}
