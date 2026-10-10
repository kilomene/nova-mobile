using UnityEngine;

namespace NovaMobile.Match
{
    /// <summary>
    /// Supply-drop crate: falls from the sky with a small canopy, lands with a
    /// dust burst, then sits as a lootable crate (the Loot system owns opening
    /// it — the crate registers itself on the minimap while falling/landed).
    /// Ported from main.gd _update_airdrops / _burst_airdrop_loot (visual part).
    /// </summary>
    public class AirdropCrate : MonoBehaviour
    {
        private const float FallSpeed = 14f;
        private float _groundY;
        private bool _landed;
        private GameObject _canopy;

        public static AirdropCrate Spawn(Vector3 atSky)
        {
            var go = new GameObject("AirdropCrate");
            var c = go.AddComponent<AirdropCrate>();
            c.Build(atSky);
            return c;
        }

        private void Build(Vector3 atSky)
        {
            transform.position = atSky;
            // Crate body.
            var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
            body.transform.SetParent(transform, false);
            body.transform.localScale = new Vector3(1.6f, 1.2f, 1.6f);
            var bmat = new Material(Shader.Find("Unlit/Color"));
            bmat.color = new Color(0.55f, 0.42f, 0.2f, 1f);
            body.GetComponent<Renderer>().material = bmat;
            Destroy(body.GetComponent<Collider>());
            // Glow stripe (top-tier loot telegraph).
            var stripe = GameObject.CreatePrimitive(PrimitiveType.Cube);
            stripe.transform.SetParent(transform, false);
            stripe.transform.localPosition = new Vector3(0f, 0.62f, 0f);
            stripe.transform.localScale = new Vector3(1.62f, 0.12f, 1.62f);
            var smat = new Material(Shader.Find("Unlit/Color"));
            smat.color = new Color(1f, 0.55f, 0.1f, 1f);
            stripe.GetComponent<Renderer>().material = smat;
            Destroy(stripe.GetComponent<Collider>());
            // Small canopy.
            _canopy = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            _canopy.transform.SetParent(transform, false);
            _canopy.transform.localPosition = new Vector3(0f, 5f, 0f);
            _canopy.transform.localScale = new Vector3(4.5f, 1.4f, 4.5f);
            var cmat = new Material(Shader.Find("Unlit/Color"));
            cmat.color = new Color(1f, 0.55f, 0.1f, 1f);
            _canopy.GetComponent<Renderer>().material = cmat;
            Destroy(_canopy.GetComponent<Collider>());

            RaycastHit hit;
            _groundY = Physics.Raycast(new Vector3(atSky.x, 400f, atSky.z), Vector3.down, out hit, 600f)
                ? hit.point.y : 0f;
            MatchMarkers.AddAirdrop(new Vector3(atSky.x, _groundY, atSky.z));
        }

        private void Update()
        {
            if (_landed) return;
            Vector3 p = transform.position;
            p.y -= FallSpeed * Time.deltaTime;
            if (p.y <= _groundY + 0.6f)
            {
                p.y = _groundY + 0.6f;
                _landed = true;
                if (_canopy != null) Destroy(_canopy);
                ExplosionFx.DustBurst(p); // landing dust
            }
            transform.position = p;
        }
    }
}
