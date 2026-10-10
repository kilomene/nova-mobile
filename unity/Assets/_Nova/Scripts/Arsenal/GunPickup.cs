using System;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// Contract the player character implements so pickups can hand over guns.
    /// Implemented by the Player system.
    /// </summary>
    public interface IGunCarrier
    {
        bool IsAlive { get; }
        /// <summary>Give the carrier a gun. Returns the replaced gun id, or "" if none.</summary>
        string GiveGun(string gunId, int tier);
        bool AttachToCurrent(string attachId);
        void SetSkinFor(string slot, int skinIdx);
    }

    /// <summary>
    /// World pickup for guns (and attachment loot), ported from gun_pickup.gd.
    /// Tier tints the glow ring; legendary+ rolls a mythic skin via the Mythics hook.
    /// On touch: gives the gun to the carrier; the carrier's old gun swaps into this
    /// pickup (so nothing is ever lost). Spins + bobs; pingable.
    /// </summary>
    [RequireComponent(typeof(SphereCollider))]
    public class GunPickup : MonoBehaviour
    {
        public string gunId = "m5";
        public int tier;
        public string attachId = ""; // if set, this pickup is an attachment, not a gun

        public Action<string> OnPickedUp;                    // announcement text
        public Action<string, int, Vector3> OnPing;          // displayName, tier, position

        /// <summary>Hook for the Mythics system: apply skin index to a world model.</summary>
        public static Action<GameObject, string, int> ApplySkinHook;
        /// <summary>Hook for the Mythics system: display name of a rolled skin.</summary>
        public static Func<string, int, string> SkinDisplayNameHook;

        private static readonly Color[] TierGlow = new Color[]
        {
            new Color(0.75f, 0.75f, 0.75f), new Color(0.75f, 0.75f, 0.75f),
            new Color(0.25f, 0.90f, 0.45f), new Color(0.35f, 0.60f, 1.00f),
            new Color(0.70f, 0.35f, 1.00f), new Color(1.00f, 0.60f, 0.15f),
        };

        private static readonly string[] TierNames = new string[]
            { "COMMON", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY" };

        private Transform _modelHolder;
        private Transform _beam;
        private Material _ringMat;
        private float _t;
        private bool _taken;
        private bool _pinged;
        private int _skinIdx;
        private System.Random _rng = new System.Random();

        public static GunPickup Make(string gid, int t)
        {
            var go = new GameObject("GunPickup_" + gid);
            var gp = go.AddComponent<GunPickup>();
            gp.gunId = gid;
            gp.tier = t;
            return gp;
        }

        public static GunPickup MakeAttachment(string aid)
        {
            var go = new GameObject("AttachPickup_" + aid);
            var gp = go.AddComponent<GunPickup>();
            gp.attachId = aid;
            gp.tier = 2;
            return gp;
        }

        private void Awake()
        {
            var col = GetComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 0.9f;

            _modelHolder = new GameObject("ModelHolder").transform;
            _modelHolder.SetParent(transform, false);

            var ringGo = new GameObject("Ring");
            ringGo.transform.SetParent(transform, false);
            var mf = ringGo.AddComponent<MeshFilter>();
            mf.mesh = BuildTorus(0.46f, 0.04f, 24, 10);
            var mr = ringGo.AddComponent<MeshRenderer>();
            var rm = new Material(Shader.Find("Standard"));
            rm.color = Color.black;
            rm.EnableKeyword("_EMISSION");
            mr.material = rm;
            _ringMat = rm; // tinted in Start, after Make() assigns tier
        }

        private void Start()
        {
            if (_ringMat != null)
                _ringMat.SetColor("_EmissionColor", TierGlow[Mathf.Clamp(tier, 0, 5)]);
            Rebuild();
            if (tier >= 4)
            {
                var beamGo = new GameObject("Beam");
                beamGo.transform.SetParent(transform, false);
                var mf = beamGo.AddComponent<MeshFilter>();
                mf.mesh = MeshBuilder.Combine(new System.Collections.Generic.List<MeshBuilder.Part>
                {
                    MeshBuilder.Cylinder(0.35f, 3f, 12, Matrix4x4.identity)
                });
                var mr = beamGo.AddComponent<MeshRenderer>();
                var bm = new Material(Shader.Find("Standard"));
                bm.SetFloat("_Mode", 3f);
                bm.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                bm.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                bm.SetInt("_ZWrite", 0);
                bm.DisableKeyword("_ALPHATEST_ON");
                bm.EnableKeyword("_ALPHABLEND_ON");
                bm.renderQueue = 3000;
                Color glow = TierGlow[Mathf.Clamp(tier, 0, 5)];
                glow.a = 0.35f;
                bm.color = glow;
                mr.material = bm;
                beamGo.transform.localPosition = new Vector3(0f, 1.5f, 0f);
                _beam = beamGo.transform;
            }
        }

        private static Mesh BuildTorus(float ringR, float tubeR, int ringSegs, int tubeSegs)
        {
            var verts = new System.Collections.Generic.List<Vector3>();
            var normals = new System.Collections.Generic.List<Vector3>();
            var uvs = new System.Collections.Generic.List<Vector2>();
            var tris = new System.Collections.Generic.List<int>();
            for (int i = 0; i <= ringSegs; i++)
            {
                float u = (float)i / ringSegs * Mathf.PI * 2f;
                Vector3 center = new Vector3(Mathf.Cos(u) * ringR, 0f, Mathf.Sin(u) * ringR);
                for (int j = 0; j <= tubeSegs; j++)
                {
                    float v = (float)j / tubeSegs * Mathf.PI * 2f;
                    Vector3 n = new Vector3(Mathf.Cos(u) * Mathf.Cos(v), Mathf.Sin(v), Mathf.Sin(u) * Mathf.Cos(v));
                    verts.Add(center + n * tubeR);
                    normals.Add(n);
                    uvs.Add(new Vector2((float)i / ringSegs, (float)j / tubeSegs));
                }
            }
            for (int i = 0; i < ringSegs; i++)
                for (int j = 0; j < tubeSegs; j++)
                {
                    int a = i * (tubeSegs + 1) + j;
                    int b = a + tubeSegs + 1;
                    tris.Add(a); tris.Add(b); tris.Add(a + 1);
                    tris.Add(a + 1); tris.Add(b); tris.Add(b + 1);
                }
            var mesh = new Mesh();
            mesh.SetVertices(verts);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private void Rebuild()
        {
            foreach (Transform child in _modelHolder)
                Destroy(child.gameObject);
            var labelGo = new GameObject("Label");
            labelGo.transform.SetParent(_modelHolder, false);
            labelGo.transform.localPosition = new Vector3(0f, 0.95f, 0f);
            var label = labelGo.AddComponent<TextMesh>();
            label.anchor = TextAnchor.MiddleCenter;
            label.alignment = TextAlignment.Center;
            label.characterSize = 0.06f;
            label.fontSize = 48;
            label.color = Color.white;

            if (attachId != "")
            {
                AttachmentMod a;
                string aname = AttachmentData.TryGet(attachId, out a) ? a.Name : attachId;
                label.text = aname.ToUpper();
                var boxGo = new GameObject("AttachBox");
                boxGo.transform.SetParent(_modelHolder, false);
                boxGo.transform.localPosition = new Vector3(0f, 0.45f, 0f);
                var mf = boxGo.AddComponent<MeshFilter>();
                mf.mesh = MeshBuilder.Combine(new System.Collections.Generic.List<MeshBuilder.Part>
                {
                    MeshBuilder.Box(new Vector3(0.16f, 0.10f, 0.16f), Matrix4x4.identity)
                });
                var mr = boxGo.AddComponent<MeshRenderer>();
                mr.material = GunFactory.EmissiveMat(new Color(0.3f, 0.7f, 1f));
            }
            else
            {
                GunSpec g = GunData.Get(gunId);
                string lbl = GunData.FullName(g) + "\n" + TierNames[Mathf.Clamp(tier, 0, 5)];
                lbl += "\n" + GunData.StkLabel(g);
                _skinIdx = 0;
                if (tier >= 4)
                {
                    _skinIdx = 1 + _rng.Next(3); // 3 mythic skins per gun
                    if (SkinDisplayNameHook != null)
                    {
                        string skn = SkinDisplayNameHook(gunId, _skinIdx);
                        if (!string.IsNullOrEmpty(skn)) lbl = skn + "\n" + lbl;
                    }
                }
                label.text = lbl.ToUpper();
                GameObject wm = GunFactory.BuildWorldModel(g);
                if (ApplySkinHook != null) ApplySkinHook(wm, gunId, _skinIdx);
                wm.transform.SetParent(_modelHolder, false);
                wm.transform.localPosition = new Vector3(0f, 0.45f, 0f);
            }
        }

        private void Update()
        {
            if (_taken) return;
            _t += Time.deltaTime;
            _modelHolder.rotation *= Quaternion.Euler(0f, 1.2f * Time.deltaTime * Mathf.Rad2Deg, 0f);
            Vector3 p = _modelHolder.position;
            p.y = 0.1f + Mathf.Sin(_t * 2f) * 0.06f;
            _modelHolder.position = p;
            if (_beam != null)
                _beam.rotation *= Quaternion.Euler(0f, 0.7f * Time.deltaTime * Mathf.Rad2Deg, 0f);
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_taken) return;
            var carrier = other.GetComponentInParent<IGunCarrier>();
            if (carrier == null || !carrier.IsAlive) return;
            TakeBy(carrier);
        }

        /// <summary>
        /// Give this pickup to a carrier. Called by the trigger and by the Loot
        /// NEARBY panel's tap-to-pickup. Same swap logic as the touch path.
        /// </summary>
        public void TakeBy(IGunCarrier carrier)
        {
            if (_taken) return;
            if (carrier == null || !carrier.IsAlive) return;
            if (attachId != "")
            {
                if (carrier.AttachToCurrent(attachId))
                {
                    _taken = true;
                    AttachmentMod a;
                    string aname = AttachmentData.TryGet(attachId, out a) ? a.Name : attachId;
                    string msg = "Attached " + aname;
                    if (OnPickedUp != null) OnPickedUp(msg);
                    if (OnAnyPickedUp != null) OnAnyPickedUp(msg, tier);
                    Destroy(gameObject);
                }
                return;
            }
            string oldId = carrier.GiveGun(gunId, tier);
            string label = "Picked up " + GunData.FullName(GunData.Get(gunId));
            if (OnPickedUp != null) OnPickedUp(label);
            if (OnAnyPickedUp != null) OnAnyPickedUp(label, tier);
            if (_skinIdx > 0)
                carrier.SetSkinFor(GunData.SlotOf(GunData.Get(gunId).Class), _skinIdx);
            if (oldId == "")
            {
                _taken = true;
                Destroy(gameObject);
            }
            else
            {
                // Swap: the dropped gun takes this pickup's place.
                gunId = oldId;
                tier = 0;
                _skinIdx = 0;
                Rebuild();
            }
        }

        /// <summary>
        /// Global pickup feed (message, 0-5 gun tier): the Loot UI's pickup cards
        /// subscribe here. Instance-level OnPickedUp is untouched.
        /// </summary>
        public static System.Action<string, int> OnAnyPickedUp;

        public string DisplayName()
        {
            return GunData.FullName(GunData.Get(gunId));
        }

        /// <summary>Called by the match when the player pings this pickup.</summary>
        public void Ping()
        {
            if (_taken || _pinged) return;
            _pinged = true;
            if (OnPing != null) OnPing(DisplayName(), tier, transform.position);
        }
    }
}
