using UnityEngine;
using UnityEngine.UI;

namespace NovaMobile.Match
{
    /// <summary>
    /// Victory / defeat screen (visual bible §11): "BATTLE ROYALE — NOVA WORLD"
    /// header, placement "#1/100" top-left, player stat card with KILLS /
    /// DAMAGE / TIME, dimmed battlefield backdrop, RETURN TO LOBBY button.
    /// (Squad member cards render when the Squads system supplies rosters;
    /// until then the player's own card is shown.)
    /// </summary>
    public class VictoryDefeat : MonoBehaviour
    {
        private static GameObject _root;

        public static void Show(bool victory, int placement, int kills, float damage, float timeAlive)
        {
            Hide();
            var canvas = UiKit.OverlayCanvas("VictoryDefeat", 50);
            _root = canvas;

            // Dimmed backdrop (the battlefield stays visible behind).
            var dim = UiKit.Panel(canvas.transform, new Color(0f, 0f, 0f, 0.62f));
            UiKit.Place(dim.GetComponent<RectTransform>(), 0f, 0f, 1f, 1f);

            var header = UiKit.Label(canvas.transform, "BATTLE ROYALE — NOVA WORLD", 40,
                new Color(1f, 0.85f, 0.3f), TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(header.GetComponent<RectTransform>(), 0f, 0.80f, 1f, 0.92f);

            // Placement top-left.
            var place = UiKit.Label(canvas.transform,
                victory ? "#1/100" : "#" + placement + "/100", 72,
                victory ? new Color(1f, 0.85f, 0.25f) : new Color(1f, 0.35f, 0.3f),
                TextAnchor.MiddleLeft, FontStyle.Bold);
            UiKit.Place(place.GetComponent<RectTransform>(), 0.06f, 0.62f, 0.40f, 0.78f);

            var verdict = UiKit.Label(canvas.transform,
                victory ? "WINNER WINNER!" : "DEFEAT", 54,
                victory ? new Color(1f, 0.85f, 0.25f) : new Color(1f, 0.4f, 0.35f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(verdict.GetComponent<RectTransform>(), 0f, 0.60f, 1f, 0.72f);

            // Player stat card.
            var card = UiKit.Panel(canvas.transform, new Color(0.08f, 0.10f, 0.14f, 0.92f));
            UiKit.Place(card.GetComponent<RectTransform>(), 0.30f, 0.30f, 0.70f, 0.58f);
            var name = UiKit.Label(card.transform, "YOU", 34, Color.white,
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(name.GetComponent<RectTransform>(), 0f, 0.66f, 1f, 0.95f);
            var stats = UiKit.Label(card.transform,
                "KILLS  " + kills + "\nDAMAGE  " + Mathf.RoundToInt(damage) +
                "\nSURVIVED  " + FormatTime(timeAlive),
                30, new Color(0.9f, 0.92f, 0.96f));
            UiKit.Place(stats.GetComponent<RectTransform>(), 0f, 0.05f, 1f, 0.64f);

            var again = UiKit.Button(canvas.transform, "RETURN TO LOBBY",
                () => MatchManager.Instance.ToLobby(),
                new Color(1f, 0.72f, 0.12f, 1f), 36);
            UiKit.Place(again.GetComponent<RectTransform>(), 0.38f, 0.12f, 0.62f, 0.24f);
            var at = again.GetComponentInChildren<Text>();
            if (at != null) at.color = Color.black;
        }

        public static void Hide()
        {
            if (_root != null) { Object.Destroy(_root); _root = null; }
        }

        private static string FormatTime(float s)
        {
            int m = Mathf.FloorToInt(s / 60f);
            int sec = Mathf.FloorToInt(s % 60f);
            return m + ":" + sec.ToString("00");
        }
    }
}
