using UnityEngine;

namespace NovaMobile.Squads
{
    /// <summary>
    /// Fallen teammate's dog tag, ported from dog_tag.gd. Walk over it to
    /// carry it, then REDEPLOY the teammate at any buy station (CODM-style,
    /// $2000 via SquadManager.TryRedeployTag).
    /// </summary>
    [RequireComponent(typeof(SphereCollider))]
    public class DogTag : MonoBehaviour
    {
        public string TagName = "ALLY";
        public SquadManager Squadman;

        private float _t;
        private GameObject _mesh;

        public static DogTag Make(string callsign, SquadManager squadman, Vector3 at)
        {
            var go = new GameObject("DogTag_" + callsign);
            var tag = go.AddComponent<DogTag>();
            tag.TagName = callsign;
            tag.Squadman = squadman;
            var col = go.GetComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 1.6f;
            // Kinematic rigidbody: guarantees trigger events against the
            // player's CharacterController on every platform.
            var rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = false;
            go.transform.position = at + Vector3.up * 0.4f;

            // Gold tag mesh (cheap box + emissive material, shared).
            tag._mesh = new GameObject("TagMesh");
            tag._mesh.transform.SetParent(go.transform, false);
            var mf = tag._mesh.AddComponent<MeshFilter>();
            mf.sharedMesh = TagMesh();
            var mr = tag._mesh.AddComponent<MeshRenderer>();
            mr.sharedMaterial = TagMaterial();
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;

            // Callsign label.
            var label = new GameObject("TagLabel");
            label.transform.SetParent(go.transform, false);
            label.transform.localPosition = new Vector3(0f, 0.9f, 0f);
            var tm = label.AddComponent<TextMesh>();
            tm.text = "◈ " + callsign;
            tm.fontSize = 48;
            tm.characterSize = 0.012f;
            tm.anchor = TextAnchor.MiddleCenter;
            tm.color = new Color(1f, 0.85f, 0.35f);
            var lmr = label.GetComponent<MeshRenderer>();
            lmr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            return tag;
        }

        private static Mesh _tagMesh;
        private static Mesh TagMesh()
        {
            if (_tagMesh == null)
            {
                _tagMesh = new Mesh();
                float x = 0.14f, y = 0.01f, z = 0.22f;
                _tagMesh.vertices = new[] {
                    new Vector3(-x,-y,-z), new Vector3(x,-y,-z),
                    new Vector3(x,-y,z), new Vector3(-x,-y,z),
                    new Vector3(-x,y,-z), new Vector3(x,y,-z),
                    new Vector3(x,y,z), new Vector3(-x,y,z) };
                _tagMesh.triangles = new[] {
                    0,2,1, 0,3,2, 4,5,6, 4,6,7,
                    0,1,5, 0,5,4, 2,3,7, 2,7,6,
                    0,4,7, 0,7,3, 1,2,6, 1,6,5 };
                _tagMesh.RecalculateNormals();
                _tagMesh.RecalculateBounds();
            }
            return _tagMesh;
        }

        private static Material _tagMat;
        private static Material TagMaterial()
        {
            if (_tagMat == null)
            {
                _tagMat = new Material(Shader.Find("Standard"));
                _tagMat.color = new Color(1f, 0.8f, 0.25f);
                _tagMat.SetFloat("_Metallic", 0.9f);
                _tagMat.SetFloat("_Glossiness", 0.75f);
                _tagMat.SetColor("_EmissionColor", new Color(1f, 0.75f, 0.2f) * 0.7f);
                _tagMat.EnableKeyword("_EMISSION");
            }
            return _tagMat;
        }

        private void Update()
        {
            _t += Time.deltaTime;
            if (_mesh != null)
            {
                _mesh.transform.localPosition = new Vector3(0f, 0.35f + Mathf.Sin(_t * 2.4f) * 0.12f, 0f);
                _mesh.transform.localRotation = Quaternion.Euler(0f, _t * 103f, 0f);
            }
        }

        private void OnTriggerEnter(Collider other)
        {
            if (Squadman == null || Squadman.Player == null) return;
            if (other.gameObject != Squadman.Player) return;
            if (!Squadman.IsPlayerAlive()) return;
            Squadman.CollectTag(TagName);
            Destroy(gameObject);
        }
    }
}
