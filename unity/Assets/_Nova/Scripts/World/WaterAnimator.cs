using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>
    /// Scrolls the shared water material's texture offset (scrolling material offset
    /// for the ProcTexture.Water() noise). Allocation-free; one instance drives all
    /// water in the world. Added by WorldBuilder.
    /// </summary>
    public class WaterAnimator : MonoBehaviour
    {
        public Material WaterMaterial;
        public Vector2 ScrollSpeed = new Vector2(0.025f, 0.016f);

        private Vector2 _offset;

        private void Update()
        {
            if (WaterMaterial == null) return;
            _offset += ScrollSpeed * Time.deltaTime;
            _offset.x -= Mathf.Floor(_offset.x);
            _offset.y -= Mathf.Floor(_offset.y);
            WaterMaterial.mainTextureOffset = _offset;
        }
    }
}
