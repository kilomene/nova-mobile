using UnityEngine;
using NovaMobile.Arsenal;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Attached to a gun root when a mythic skin is applied (see SkinApplier).
    /// Wires GunBehaviour's reload events to the theme flourish and exposes
    /// PlayDraw() for the owning character controller to call when the gun is
    /// drawn/equipped. Also drives the reload/draw scale pulse (no allocations).
    /// </summary>
    public class MythicGunRig : MonoBehaviour
    {
        public string GunId { get; private set; }
        public string ThemeId { get; private set; }

        private GunBehaviour _gun;
        private float _pulseT; // >0 while a scale pulse is running
        private const float PulseDur = 0.28f;

        public void Setup(string gunId, string themeId)
        {
            GunId = gunId;
            ThemeId = themeId;
            _gun = GetComponent<GunBehaviour>();
        }

        private void OnEnable()
        {
            if (_gun == null) _gun = GetComponent<GunBehaviour>();
            if (_gun != null) _gun.OnReloadFinished += HandleReloadFinished;
        }

        private void OnDisable()
        {
            if (_gun != null) _gun.OnReloadFinished -= HandleReloadFinished;
        }

        private void HandleReloadFinished()
        {
            if (string.IsNullOrEmpty(ThemeId)) return;
            MythicFx.PlayReloadFlourish(gameObject, ThemeId);
            _pulseT = PulseDur;
        }

        /// <summary>Called by the owning character when this gun is drawn/equipped.</summary>
        public void PlayDraw()
        {
            if (string.IsNullOrEmpty(ThemeId)) return;
            MythicFx.PlayDrawFlourish(gameObject, ThemeId);
            _pulseT = PulseDur;
        }

        private void Update()
        {
            if (_pulseT <= 0f) return;
            _pulseT -= Time.deltaTime;
            float k = Mathf.Clamp01(1f - _pulseT / PulseDur);
            float s = 1f + 0.12f * Mathf.Sin(k * Mathf.PI);
            transform.localScale = new Vector3(s, s, s);
            if (_pulseT <= 0f) transform.localScale = Vector3.one;
        }
    }
}
