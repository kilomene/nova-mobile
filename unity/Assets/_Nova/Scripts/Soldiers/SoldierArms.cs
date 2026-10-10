using UnityEngine;
using NovaMobile.Arsenal;

namespace NovaMobile.Soldiers
{
    /// <summary>Grip pose set for the first-person arms viewmodel.</summary>
    public enum WeaponGrip
    {
        Rifle = 0,
        Pistol = 1,
        Launcher = 2,
        Melee = 3,
    }

    /// <summary>
    /// First-person arms viewmodel parented to the camera: procedural forearms
    /// with sleeves + gloves, grip poses per weapon class. Used during ADS /
    /// first-person moments (the game is third-person otherwise). No per-frame
    /// allocations: precreated unit-box limb meshes are re-posed via transform
    /// only. All positions authored from the Godot spec, mirrored to Unity's
    /// camera space (+Z forward).
    /// </summary>
    public class SoldierArms : MonoBehaviour
    {
        // Hand targets per grip, camera-local: [R hand, L hand].
        private static readonly Vector3[,] GripPose = {
            { new Vector3(0.30f, -0.30f, 0.52f), new Vector3(0.14f, -0.33f, 0.74f) }, // rifle
            { new Vector3(0.28f, -0.30f, 0.50f), new Vector3(0.34f, -0.62f, 0.18f) }, // pistol
            { new Vector3(0.32f, -0.16f, 0.42f), new Vector3(0.10f, -0.20f, 0.60f) }, // launcher
            { new Vector3(0.30f, -0.32f, 0.55f), new Vector3(0.33f, -0.60f, 0.20f) }, // melee
        };
        private static readonly Vector3[,] GripAds = {
            { new Vector3(0.015f, -0.238f, 0.44f), new Vector3(-0.01f, -0.27f, 0.62f) }, // rifle
            { new Vector3(0.0f, -0.245f, 0.44f), new Vector3(0.02f, -0.30f, 0.42f) },    // pistol
            { new Vector3(0.05f, -0.16f, 0.42f), new Vector3(0.0f, -0.20f, 0.60f) },      // launcher
            { new Vector3(0.30f, -0.32f, 0.55f), new Vector3(0.33f, -0.60f, 0.20f) },     // melee
        };

        private static Mesh _unitCube;
        private static Mesh _gloveBox;
        private static Mesh _nadeMesh;

        private WeaponGrip _grip = WeaponGrip.Rifle;
        private float _adsT, _adsTarget;
        private float _sprintT, _sprintTarget;
        private Vector3 _kick;
        private float _kickRot;
        private float _reloadPh = -1f; // -1 idle, else 0..1
        private float _throwPh = -1f;  // -1 idle, else 0..1 (left-hand throw)
        private float _bobT, _bobAmp;
        private bool _visibleHands = true;

        private readonly Transform[] _limbs = new Transform[4]; // R upper, R fore, L upper, L fore
        private readonly Transform[] _gloves = new Transform[2];
        private Transform _nade;

        private Material _sleeveMat;
        private Material _gloveMat;

        /// <summary>Factory: builds arms already parented to the camera.</summary>
        public static SoldierArms Build(Camera cam)
        {
            var go = new GameObject("SoldierArms");
            var arms = go.AddComponent<SoldierArms>();
            arms.BuildParts();
            arms.AttachTo(cam);
            return arms;
        }

        public void AttachTo(Camera cam)
        {
            if (cam == null) return;
            transform.SetParent(cam.transform, false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
        }

        public void BuildParts()
        {
            if (_unitCube == null) _unitCube = SoldierMeshes.Box(Vector3.one);
            if (_gloveBox == null) _gloveBox = SoldierMeshes.Box(new Vector3(0.075f, 0.10f, 0.09f));
            if (_nadeMesh == null) _nadeMesh = SoldierMeshes.Sphere(0.035f);

            _sleeveMat = new Material(Shader.Find("Standard"));
            _sleeveMat.color = new Color(0.26f, 0.28f, 0.18f);
            _sleeveMat.SetFloat("_Glossiness", 0.08f);
            _gloveMat = new Material(Shader.Find("Standard"));
            _gloveMat.color = new Color(0.12f, 0.11f, 0.09f);
            _gloveMat.SetFloat("_Glossiness", 0.3f);

            for (int i = 0; i < 4; i++)
                _limbs[i] = MakePart("Limb" + i, _unitCube, _sleeveMat);
            for (int i = 0; i < 2; i++)
                _gloves[i] = MakePart("Glove" + i, _gloveBox, _gloveMat);

            var nadeMat = new Material(Shader.Find("Standard"));
            nadeMat.color = new Color(0.2f, 0.28f, 0.16f);
            nadeMat.SetFloat("_Glossiness", 0.4f);
            nadeMat.SetFloat("_Metallic", 0.3f);
            _nade = MakePart("Grenade", _nadeMesh, nadeMat);
            _nade.gameObject.SetActive(false);
        }

        private Transform MakePart(string name, Mesh mesh, Material mat)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var mf = go.AddComponent<MeshFilter>();
            mf.sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;
            return go.transform;
        }

        public void SetGrip(WeaponGrip g) { _grip = g; }
        public WeaponGrip Grip() { return _grip; }

        public string GripName() { return _grip.ToString().ToLowerInvariant(); }

        /// <summary>Map an Arsenal gun class to the matching grip pose.</summary>
        public void SetGripForGunClass(GunClass gc)
        {
            switch (gc)
            {
                case GunClass.Pistol: _grip = WeaponGrip.Pistol; break;
                case GunClass.Launcher: _grip = WeaponGrip.Launcher; break;
                case GunClass.Melee: _grip = WeaponGrip.Melee; break;
                default: _grip = WeaponGrip.Rifle; break; // AR/SMG/LMG/Sniper/Marksman/Shotgun
            }
        }

        public void SetAds(bool b) { _adsTarget = b ? 1f : 0f; }
        public void SetSprint(bool b) { _sprintTarget = b ? 1f : 0f; }

        public void AddKick(float v)
        {
            _kick += new Vector3(0f, v * 0.35f, -v); // back toward the camera (-Z)
            _kickRot += v * 1.4f;
        }

        public void SetReloadPhase(float ph) { _reloadPh = ph; }

        public void SetThrowPhase(float ph)
        {
            _throwPh = ph;
            if (_nade != null) _nade.gameObject.SetActive(ph >= 0f && ph < 0.55f);
        }

        public void SetBob(float t, float amp) { _bobT = t; _bobAmp = amp; }

        public void SetHandsVisible(bool b)
        {
            _visibleHands = b;
            gameObject.SetActive(b);
        }

        /// <summary>Tint the sleeves (e.g. to match the operator's uniform).</summary>
        public void SetSleeveTint(Color c)
        {
            if (_sleeveMat != null) _sleeveMat.color = c;
        }

        private void PoseLimb(Transform limb, Vector3 a, Vector3 b, float r)
        {
            // a/b are camera-local (arms root sits at the camera origin), so all
            // posing is in local space; world-space sets would detach from the camera.
            Vector3 d = b - a;
            float len = d.magnitude;
            if (len < 0.001f || !_visibleHands)
            {
                limb.gameObject.SetActive(false);
                return;
            }
            limb.gameObject.SetActive(true);
            limb.localPosition = (a + b) * 0.5f;
            Vector3 fwd = d / len;
            Vector3 up = Vector3.up;
            if (Mathf.Abs(Vector3.Dot(fwd, up)) > 0.95f) up = Vector3.right;
            limb.localRotation = Quaternion.LookRotation(fwd, up);
            limb.localScale = new Vector3(r * 2f, r * 2f, len);
        }

        private void LateUpdate()
        {
            if (_limbs[0] == null) return;
            _adsT = Mathf.MoveTowards(_adsT, _adsTarget, Time.deltaTime * 7f);
            _sprintT = Mathf.MoveTowards(_sprintT, _sprintTarget, Time.deltaTime * 6f);
            _kick = Vector3.MoveTowards(_kick, Vector3.zero, Time.deltaTime * 1.6f);
            _kickRot = Mathf.MoveTowards(_kickRot, 0f, Time.deltaTime * 9f);

            int g = (int)_grip;
            Vector3 rh = Vector3.Lerp(GripPose[g, 0], GripAds[g, 0], _adsT);
            Vector3 lh = Vector3.Lerp(GripPose[g, 1], GripAds[g, 1], _adsT);
            // Sprint: weapon lowered, right hand drops, left hand pumps at side.
            Vector3 rhSprint = new Vector3(0.34f, -0.52f, 0.35f);
            Vector3 lhSprint = new Vector3(0.30f, -0.48f, 0.30f)
                + new Vector3(0f, 0.10f * Mathf.Sin(_bobT * 6f), 0f);
            rh = Vector3.Lerp(rh, rhSprint, _sprintT);
            lh = Vector3.Lerp(lh, lhSprint, _sprintT);
            // Walk bob.
            Vector3 bob = new Vector3(
                Mathf.Sin(_bobT * 2f) * 0.006f, Mathf.Cos(_bobT * 4f) * 0.008f, 0f) * _bobAmp;
            rh += bob;
            lh += bob;
            // Per-shot kick.
            rh += _kick;
            lh += _kick * 0.7f;
            // Reload: left hand dips to the mag well.
            if (_reloadPh >= 0f)
            {
                float dip = Mathf.Sin(_reloadPh * Mathf.PI);
                lh = Vector3.Lerp(lh, new Vector3(0.20f, -0.42f, 0.45f), dip * 0.8f);
            }
            // Grenade throw: left hand leaves the gun, overhand arc.
            if (_throwPh >= 0f)
            {
                float ph = _throwPh;
                Vector3 windup = new Vector3(0.05f, 0.05f, 0.35f);
                Vector3 release = new Vector3(0.10f, -0.10f, 0.75f);
                if (ph < 0.35f) lh = Vector3.Lerp(lh, windup, ph / 0.35f);
                else if (ph < 0.55f) lh = Vector3.Lerp(windup, release, (ph - 0.35f) / 0.20f);
                else lh = Vector3.Lerp(release, GripPose[g, 1], (ph - 0.55f) / 0.45f);
            }
            // Elbows: out, down, back from the hands.
            Vector3 re = rh + new Vector3(0.16f, -0.26f, -0.16f);
            Vector3 le = lh + new Vector3(-0.16f, -0.26f, -0.16f);
            Vector3 ra = rh + new Vector3(0.10f, -0.62f, -0.30f);
            Vector3 la = lh + new Vector3(-0.10f, -0.62f, -0.30f);
            PoseLimb(_limbs[0], ra, re, 0.055f);
            PoseLimb(_limbs[1], re, rh, 0.048f);
            PoseLimb(_limbs[2], la, le, 0.055f);
            PoseLimb(_limbs[3], le, lh, 0.048f);
            _gloves[0].localPosition = rh + new Vector3(0f, -0.02f, 0.03f);
            _gloves[1].localPosition = lh + new Vector3(0f, -0.02f, 0.03f);
            // Godot authored these rotations in radians; convert to degrees.
            _gloves[0].localRotation = Quaternion.Euler(
                _kickRot * 0.4f * Mathf.Rad2Deg, 0f, -0.15f * Mathf.Rad2Deg);
            _gloves[1].localRotation = Quaternion.Euler(
                _kickRot * 0.3f * Mathf.Rad2Deg, 0f, 0.15f * Mathf.Rad2Deg);
            if (_nade.gameObject.activeSelf)
                _nade.localPosition = lh + new Vector3(0f, 0.03f, 0.02f);
        }
    }
}
