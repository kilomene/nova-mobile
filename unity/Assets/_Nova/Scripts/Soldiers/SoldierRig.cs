using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Soldiers
{
    /// <summary>Selectable operator appearance. Sentinel and Breacher are the two
    /// NOVA default characters (CODM Special-Ops visual language).</summary>
    public enum SoldierVariant
    {
        Sentinel = 0,   // full helmet + white balaclava + red-lens goggles + NVG + boom mic
        Breacher = 1,   // tan cap, visible face, red shotgun-shell chest rig
    }

    /// <summary>
    /// Procedural 1.82m soldier: 28 named bone Transforms with rigid body/gear
    /// meshes parented to bones (mobile-appropriate, NOT skinned). The character
    /// faces +Z (Unity convention); the Godot spec faces -Z, so all authored
    /// front/back (Z) positions and pitch (X) rotations are mirrored on input.
    /// Gear visibility groups switch per variant; Sentinel vs Breacher are
    /// readable at 5m (helmet+NVG+white balaclava vs cap+bare face+red shells).
    /// Death = animated fall clip + settle tween, then a 25s corpse window
    /// before CorpseExpired fires (hook for Match/Squads recycling).
    /// </summary>
    public class SoldierRig : MonoBehaviour
    {
        // ------------------------------------------------------------------ bones
        // name, parent, local pos (Godot spec values, Z mirrored at build),
        // rest euler radians (Godot spec values, X mirrored at build).
        private struct BoneDef
        {
            public string name, parent;
            public Vector3 pos, eul;
            public BoneDef(string n, string p, Vector3 pos, Vector3 eul)
            { name = n; parent = p; this.pos = pos; this.eul = eul; }
        }

        private static readonly BoneDef[] BoneDefs = {
            new BoneDef("Hips",       "",          new Vector3(0, 0.98f, 0),      Vector3.zero),
            new BoneDef("Spine",      "Hips",      new Vector3(0, 0.12f, 0),      Vector3.zero),
            new BoneDef("Chest",      "Spine",     new Vector3(0, 0.14f, 0),      Vector3.zero),
            new BoneDef("Neck",       "Chest",     new Vector3(0, 0.20f, 0),      Vector3.zero),
            new BoneDef("Head",       "Neck",      new Vector3(0, 0.08f, 0),      Vector3.zero),
            new BoneDef("ClavicleL",  "Chest",     new Vector3(-0.10f, 0.16f, 0), Vector3.zero),
            new BoneDef("ClavicleR",  "Chest",     new Vector3(0.10f, 0.16f, 0),  Vector3.zero),
            new BoneDef("ShoulderL",  "ClavicleL", new Vector3(-0.11f, 0.02f, 0),Vector3.zero),
            new BoneDef("ShoulderR",  "ClavicleR", new Vector3(0.11f, 0.02f, 0), Vector3.zero),
            new BoneDef("UpperArmL",  "ShoulderL", new Vector3(-0.03f, -0.02f, 0), new Vector3(0, 0, -0.10f)),
            new BoneDef("UpperArmR",  "ShoulderR", new Vector3(0.03f, -0.02f, 0),  new Vector3(0, 0, 0.10f)),
            new BoneDef("LowerArmL",  "UpperArmL", new Vector3(0, -0.28f, 0),    new Vector3(0.12f, 0, 0)),
            new BoneDef("LowerArmR",  "UpperArmR", new Vector3(0, -0.28f, 0),    new Vector3(0.12f, 0, 0)),
            new BoneDef("HandL",      "LowerArmL", new Vector3(0, -0.26f, 0),    Vector3.zero),
            new BoneDef("HandR",      "LowerArmR", new Vector3(0, -0.26f, 0),    Vector3.zero),
            new BoneDef("FingerL",    "HandL",     new Vector3(0, -0.09f, -0.01f),Vector3.zero),
            new BoneDef("FingerR",    "HandR",     new Vector3(0, -0.09f, -0.01f),Vector3.zero),
            new BoneDef("UpperLegL",  "Hips",      new Vector3(-0.11f, -0.04f, 0),Vector3.zero),
            new BoneDef("UpperLegR",  "Hips",      new Vector3(0.11f, -0.04f, 0), Vector3.zero),
            new BoneDef("LowerLegL",  "UpperLegL", new Vector3(0, -0.44f, 0),    Vector3.zero),
            new BoneDef("LowerLegR",  "UpperLegR", new Vector3(0, -0.44f, 0),    Vector3.zero),
            new BoneDef("FootL",      "LowerLegL", new Vector3(0, -0.42f, 0),    Vector3.zero),
            new BoneDef("FootR",      "LowerLegR", new Vector3(0, -0.42f, 0),    Vector3.zero),
            new BoneDef("ToesL",      "FootL",     new Vector3(0, -0.03f, -0.12f),Vector3.zero),
            new BoneDef("ToesR",      "FootR",     new Vector3(0, -0.03f, -0.12f),Vector3.zero),
            new BoneDef("VestPlate",  "Spine",     new Vector3(0, 0.06f, 0),     Vector3.zero),
            new BoneDef("Backpack",   "Chest",     new Vector3(0, 0.06f, 0.17f), Vector3.zero),
            new BoneDef("WeaponMount","HandR",     new Vector3(0, -0.02f, -0.06f),Vector3.zero),
        };

        public static readonly string[] BoneNames = {
            "Hips","Spine","Chest","Neck","Head",
            "ClavicleL","ClavicleR","ShoulderL","ShoulderR",
            "UpperArmL","UpperArmR","LowerArmL","LowerArmR",
            "HandL","HandR","FingerL","FingerR",
            "UpperLegL","UpperLegR","LowerLegL","LowerLegR",
            "FootL","FootR","ToesL","ToesR",
            "VestPlate","Backpack","WeaponMount",
        };

        /// <summary>Godot clip-authoring bone names -> Unity rig bone names.</summary>
        public static string RemapBoneName(string godot)
        {
            switch (godot)
            {
                case "Spine1": return "Chest";
                case "ForearmL": return "LowerArmL";
                case "ForearmR": return "LowerArmR";
                case "ThighL": return "UpperLegL";
                case "ThighR": return "UpperLegR";
                case "ShinL": return "LowerLegL";
                case "ShinR": return "LowerLegR";
                case "ToeL": return "ToesL";
                case "ToeR": return "ToesR";
                case "Weapon": return "WeaponMount";
                default: return godot;
            }
        }

        // ------------------------------------------------------------------ state
        public Transform[] Bones = new Transform[28];
        public Vector3[] RestPos = new Vector3[28];
        public Quaternion[] RestRot = new Quaternion[28];

        public Transform WeaponMount { get; private set; }
        /// <summary>Anchor on the upper back where Arsenal's third-person gun
        /// sits while stowed (not in hands).</summary>
        public Transform BackSling { get; private set; }
        public GameObject CurrentWeapon { get; private set; }

        public SoldierAnim Anim { get; private set; }
        public SoldierVariant Variant { get; private set; }

        /// <summary>Fired 25s (CorpseLifetime) after death settles; Match/Squads
        /// use it to recycle or fade the corpse.</summary>
        public event Action<SoldierRig> CorpseExpired;
        public float CorpseLifetime = 25f;
        public bool IsDead { get { return _dead; } }

        /// <summary>Distance LOD: beyond this, animation sampling pauses.</summary>
        public float LodAnimDistance = 45f;

        private readonly Dictionary<string, int> _boneIndex = new Dictionary<string, int>();
        private readonly Dictionary<string, List<MeshRenderer>> _groups = new Dictionary<string, List<MeshRenderer>>();
        private readonly List<MeshRenderer> _headMeshes = new List<MeshRenderer>();
        private readonly List<MeshRenderer> _allRenderers = new List<MeshRenderer>();
        private readonly List<MeshFilter> _variantMats = new List<MeshFilter>();
        private readonly Dictionary<MeshFilter, string> _matKey = new Dictionary<MeshFilter, string>();
        private Material _accentMat;
        private MeshRenderer _accentRenderer;

        private bool _built;
        private bool _dead;
        private int _deathPhase; // 0 = clip playing, 1 = settle tween, 2 = corpse
        private float _deathT;
        private float _corpseT;
        private float _lodT;
        private bool _lodFar;
        private bool _shadowsOn = true;
        private Transform _cam;
        private float _settleDrop;

        // ------------------------------------------------------------------ build
        /// <summary>Factory: creates a fully built soldier GameObject.</summary>
        public static SoldierRig Build(SoldierVariant variant, string name = "Soldier")
        {
            var go = new GameObject(name);
            var rig = go.AddComponent<SoldierRig>();
            rig.BuildRig(variant);
            return rig;
        }

        public void BuildRig(SoldierVariant variant)
        {
            if (_built) return;
            _built = true;
            BuildBones();
            BuildMeshes();
            BackSling = new GameObject("BackSling").transform;
            BackSling.SetParent(GetBone("Chest"), false);
            // Diagonal across the upper back: muzzle up over the right shoulder.
            BackSling.localPosition = new Vector3(0.10f, 0.12f, -0.24f);
            BackSling.localRotation = Quaternion.Euler(-38f, 12f, 24f);
            Anim = gameObject.AddComponent<SoldierAnim>();
            Anim.Setup(this);
            SetVariant(variant);
        }

        private void BuildBones()
        {
            var map = new Dictionary<string, Transform>();
            for (int i = 0; i < BoneDefs.Length; i++)
            {
                var d = BoneDefs[i];
                var t = new GameObject(d.name).transform;
                t.SetParent(string.IsNullOrEmpty(d.parent) ? transform : map[d.parent], false);
                // Godot spec faces -Z; Unity faces +Z: mirror Z pos, negate X euler.
                t.localPosition = new Vector3(d.pos.x, d.pos.y, -d.pos.z);
                t.localRotation = Quaternion.Euler(-d.eul.x * Mathf.Rad2Deg, d.eul.y * Mathf.Rad2Deg, d.eul.z * Mathf.Rad2Deg);
                map[d.name] = t;
                Bones[i] = t;
                RestPos[i] = t.localPosition;
                RestRot[i] = t.localRotation;
                _boneIndex[d.name] = i;
            }
            WeaponMount = map["WeaponMount"];
        }

        public int BoneIndex(string name)
        {
            int i;
            return _boneIndex.TryGetValue(name, out i) ? i : -1;
        }

        /// <summary>Static bone index (identical for every rig).</summary>
        public static int BoneIndexOf(string name)
        {
            for (int i = 0; i < BoneNames.Length; i++)
                if (BoneNames[i] == name) return i;
            return -1;
        }

        /// <summary>Static rest local position (Unity space, Z mirrored).</summary>
        public static Vector3 RestLocalPos(string name)
        {
            for (int i = 0; i < BoneDefs.Length; i++)
                if (BoneDefs[i].name == name)
                {
                    Vector3 p = BoneDefs[i].pos;
                    return new Vector3(p.x, p.y, -p.z);
                }
            return Vector3.zero;
        }

        public Transform GetBone(string name)
        {
            int i = BoneIndex(name);
            return i >= 0 ? Bones[i] : null;
        }

        // ------------------------------------------------------------------ materials
        private class VariantMats
        {
            public Material uniform, vest, helmet, pack, pants, balaclava, cap;
        }

        private static readonly Dictionary<SoldierVariant, VariantMats> _variantMats =
            new Dictionary<SoldierVariant, VariantMats>();
        private static readonly Dictionary<string, Material> _sharedMats =
            new Dictionary<string, Material>();

        private static Material MakeMat(Color c, float rough, float metal)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.SetFloat("_Glossiness", 1f - rough);
            m.SetFloat("_Metallic", metal);
            return m;
        }

        private static Material MakeEmissive(Color c, Color emission, float energy)
        {
            var m = MakeMat(c, 0.4f, 0f);
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", emission * energy);
            return m;
        }

        private static Material Shared(string key, Func<Material> build)
        {
            Material m;
            if (!_sharedMats.TryGetValue(key, out m)) { m = build(); _sharedMats[key] = m; }
            return m;
        }

        private static readonly Color[] SentinelCamo = {
            new Color(0.45f, 0.49f, 0.55f), new Color(0.30f, 0.33f, 0.40f),
            new Color(0.22f, 0.24f, 0.30f), new Color(0.62f, 0.65f, 0.70f),
        };
        private static readonly Color[] BreacherCamo = {
            new Color(0.66f, 0.58f, 0.42f), new Color(0.50f, 0.43f, 0.30f),
            new Color(0.38f, 0.32f, 0.22f), new Color(0.75f, 0.68f, 0.52f),
        };

        private static VariantMats GetVariantMats(SoldierVariant v)
        {
            VariantMats vm;
            if (_variantMats.TryGetValue(v, out vm)) return vm;
            vm = new VariantMats();
            Color[] pal = v == SoldierVariant.Sentinel ? SentinelCamo : BreacherCamo;
            Texture2D camo = ProcTexture.Camo(pal, 128, v == SoldierVariant.Sentinel ? 4242 : 917);
            vm.uniform = MakeMat(Color.white, 0.92f, 0f);
            vm.uniform.mainTexture = camo;
            vm.helmet = MakeMat(Color.white, 0.55f, 0f);
            vm.helmet.mainTexture = camo;
            if (v == SoldierVariant.Sentinel)
            {
                vm.vest = MakeMat(new Color(0.16f, 0.16f, 0.18f), 0.88f, 0f);
                vm.pack = MakeMat(new Color(0.30f, 0.30f, 0.33f), 0.9f, 0f);
                vm.pants = MakeMat(new Color(0.40f, 0.44f, 0.50f), 0.92f, 0f);
                vm.balaclava = MakeMat(new Color(0.88f, 0.88f, 0.86f), 0.95f, 0f);
                vm.cap = MakeMat(new Color(0.58f, 0.50f, 0.34f), 0.9f, 0f);
            }
            else
            {
                vm.vest = MakeMat(new Color(0.16f, 0.16f, 0.18f), 0.88f, 0f);
                vm.pack = MakeMat(new Color(0.55f, 0.47f, 0.32f), 0.9f, 0f);
                vm.pants = MakeMat(new Color(0.40f, 0.44f, 0.50f), 0.92f, 0f);
                vm.balaclava = MakeMat(new Color(0.09f, 0.09f, 0.10f), 0.95f, 0f);
                vm.cap = MakeMat(new Color(0.58f, 0.50f, 0.34f), 0.9f, 0f);
            }
            _variantMats[v] = vm;
            return vm;
        }

        private Material MatForKey(string key, VariantMats vm)
        {
            switch (key)
            {
                case "uniform": return vm.uniform;
                case "vest": return vm.vest;
                case "helmet": return vm.helmet;
                case "pack": return vm.pack;
                case "pants": return vm.pants;
                case "balaclava": return vm.balaclava;
                case "cap": return vm.cap;
                case "glove": return Shared("glove", () => MakeMat(new Color(0.13f, 0.12f, 0.10f), 0.7f, 0f));
                case "boot": return Shared("boot", () => MakeMat(new Color(0.16f, 0.13f, 0.10f), 0.55f, 0f));
                case "pad": return Shared("pad", () => MakeMat(new Color(0.12f, 0.12f, 0.13f), 0.6f, 0f));
                case "gunmetal": return Shared("gunmetal", () => MakeMat(new Color(0.12f, 0.12f, 0.13f), 0.38f, 0.75f));
                case "metal": return Shared("metal", () => MakeMat(new Color(0.35f, 0.35f, 0.37f), 0.35f, 0.85f));
                case "glass": return Shared("glass", () => MakeEmissive(new Color(0.05f, 0.08f, 0.10f), new Color(0.1f, 0.25f, 0.35f), 0.4f));
                case "lensred": return Shared("lensred", () => MakeEmissive(new Color(0.50f, 0.10f, 0.05f), new Color(1f, 0.25f, 0.08f), 1.2f));
                case "face": return Shared("face", () => MakeMat(new Color(0.76f, 0.60f, 0.48f), 0.75f, 0f));
                case "hair": return Shared("hair", () => MakeMat(new Color(0.16f, 0.12f, 0.09f), 0.9f, 0f));
                case "shellred": return Shared("shellred", () => MakeMat(new Color(0.55f, 0.08f, 0.06f), 0.4f, 0.2f));
                default: return Shared("pad", () => MakeMat(new Color(0.12f, 0.12f, 0.13f), 0.6f, 0f));
            }
        }

        // ------------------------------------------------------------------ meshes
        // All authored in Godot spec values (faces -Z); AddMesh mirrors to Unity +Z.
        private void AddMesh(string bone, Mesh mesh, string matKey, Vector3 pos,
            Vector3 rotRad, Vector3 scale, string group, bool isHead = false)
        {
            Transform b = GetBone(bone);
            if (b == null || mesh == null) return;
            var go = new GameObject(mesh.name);
            go.transform.SetParent(b, false);
            go.transform.localPosition = new Vector3(pos.x, pos.y, -pos.z);
            go.transform.localRotation = Quaternion.Euler(
                -rotRad.x * Mathf.Rad2Deg, rotRad.y * Mathf.Rad2Deg, rotRad.z * Mathf.Rad2Deg);
            go.transform.localScale = scale;
            var mf = go.AddComponent<MeshFilter>();
            mf.sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
            mr.receiveShadow = false;
            _matKey[mf] = matKey;
            _variantMatsList.Add(mf);
            _allRenderers.Add(mr);
            if (!string.IsNullOrEmpty(group))
            {
                List<MeshRenderer> list;
                if (!_groups.TryGetValue(group, out list)) { list = new List<MeshRenderer>(); _groups[group] = list; }
                list.Add(mr);
            }
            if (isHead) _headMeshes.Add(mr);
        }

        private readonly List<MeshFilter> _variantMatsList = new List<MeshFilter>();

        private static readonly Vector3 V1 = Vector3.one;
        private static readonly float PI = Mathf.PI;

        private void BuildMeshes()
        {
            // Legs.
            for (int s = 0; s < 2; s++)
            {
                string side = s == 0 ? "L" : "R"; // L = -X per the rig convention
                AddMesh("UpperLeg" + side, SoldierMeshes.Capsule(0.088f, 0.36f), "pants", new Vector3(0, -0.20f, 0), Vector3.zero, V1, "");
                AddMesh("LowerLeg" + side, SoldierMeshes.Capsule(0.070f, 0.36f), "pants", new Vector3(0, -0.20f, 0), Vector3.zero, V1, "");
                AddMesh("LowerLeg" + side, SoldierMeshes.Box(new Vector3(0.11f, 0.10f, 0.06f)), "pad", new Vector3(0, -0.045f, -0.085f), Vector3.zero, V1, "");
                AddMesh("Foot" + side, SoldierMeshes.Box(new Vector3(0.11f, 0.10f, 0.27f)), "boot", new Vector3(0, -0.055f, -0.055f), Vector3.zero, V1, "");
                AddMesh("Toes" + side, SoldierMeshes.Box(new Vector3(0.105f, 0.075f, 0.10f)), "boot", new Vector3(0, -0.06f, -0.03f), Vector3.zero, V1, "");
                if (side == "R")
                    AddMesh("UpperLegR", SoldierMeshes.Box(new Vector3(0.08f, 0.17f, 0.07f)), "pad", new Vector3(0.105f, -0.14f, 0.03f), Vector3.zero, V1, "");
            }
            // Pelvis / torso.
            AddMesh("Hips", SoldierMeshes.Box(new Vector3(0.32f, 0.22f, 0.24f)), "pants", new Vector3(0, -0.03f, 0), Vector3.zero, V1, "");
            AddMesh("Hips", SoldierMeshes.Box(new Vector3(0.335f, 0.06f, 0.25f)), "metal", new Vector3(0, 0.075f, 0), Vector3.zero, V1, "");
            AddMesh("Spine", SoldierMeshes.Box(new Vector3(0.30f, 0.20f, 0.22f)), "uniform", new Vector3(0, 0.05f, 0), Vector3.zero, V1, "");
            AddMesh("Chest", SoldierMeshes.Box(new Vector3(0.36f, 0.26f, 0.24f)), "uniform", new Vector3(0, 0.08f, 0), Vector3.zero, V1, "");
            // Plate carrier + pouches.
            AddMesh("VestPlate", SoldierMeshes.Box(new Vector3(0.335f, 0.30f, 0.29f)), "vest", new Vector3(0, 0.07f, -0.005f), Vector3.zero, V1, "");
            AddMesh("VestPlate", SoldierMeshes.Box(new Vector3(0.24f, 0.26f, 0.045f)), "vest", new Vector3(0, 0.07f, -0.155f), Vector3.zero, V1, "");
            AddMesh("VestPlate", SoldierMeshes.Box(new Vector3(0.24f, 0.22f, 0.045f)), "vest", new Vector3(0, 0.07f, 0.15f), Vector3.zero, V1, "");
            for (int i = 0; i < 3; i++)
                AddMesh("VestPlate", SoldierMeshes.Box(new Vector3(0.075f, 0.10f, 0.055f)), "pack", new Vector3(-0.095f + 0.095f * i, -0.045f, -0.165f), Vector3.zero, V1, "");
            AddMesh("VestPlate", SoldierMeshes.Box(new Vector3(0.09f, 0.07f, 0.05f)), "pack", new Vector3(0.13f, 0.10f, -0.16f), Vector3.zero, V1, "");
            BuildBackpack();
            // Arms.
            for (int s = 0; s < 2; s++)
            {
                string side = s == 0 ? "L" : "R";
                AddMesh("UpperArm" + side, SoldierMeshes.Capsule(0.060f, 0.26f), "uniform", new Vector3(0, -0.14f, 0), Vector3.zero, V1, "");
                AddMesh("Shoulder" + side, SoldierMeshes.Box(new Vector3(0.10f, 0.09f, 0.10f)), "uniform", Vector3.zero, Vector3.zero, V1, "");
                AddMesh("LowerArm" + side, SoldierMeshes.Capsule(0.050f, 0.24f), "uniform", new Vector3(0, -0.13f, 0), Vector3.zero, V1, "");
                AddMesh("LowerArm" + side, SoldierMeshes.Box(new Vector3(0.085f, 0.075f, 0.085f)), "pad", new Vector3(0, -0.015f, 0.035f), Vector3.zero, V1, "");
                AddMesh("Hand" + side, SoldierMeshes.Box(new Vector3(0.070f, 0.115f, 0.050f)), "glove", new Vector3(0, -0.055f, 0), Vector3.zero, V1, "");
                AddMesh("Finger" + side, SoldierMeshes.Box(new Vector3(0.060f, 0.070f, 0.045f)), "glove", new Vector3(0, -0.035f, 0), Vector3.zero, V1, "");
            }
            // Neck + head options.
            AddMesh("Neck", SoldierMeshes.Capsule(0.05f, 0.10f), "balaclava", new Vector3(0, 0.02f, 0), Vector3.zero, V1, "", true);
            AddMesh("Head", SoldierMeshes.Sphere(0.105f), "balaclava", new Vector3(0, 0.10f, -0.01f), Vector3.zero, new Vector3(1f, 1.15f, 1.05f), "balaclava", true);
            // Helmet shell + rear brim.
            AddMesh("Head", SoldierMeshes.Sphere(0.135f), "helmet", new Vector3(0, 0.155f, 0.015f), Vector3.zero, new Vector3(1.02f, 0.78f, 1.08f), "helmet", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.20f, 0.035f, 0.03f)), "helmet", new Vector3(0, 0.10f, 0.10f), Vector3.zero, V1, "helmet", true);
            // Dark goggles + strap.
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.165f, 0.062f, 0.055f)), "glass", new Vector3(0, 0.115f, -0.098f), Vector3.zero, V1, "gogglesDark", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.21f, 0.03f, 0.21f)), "pad", new Vector3(0, 0.115f, 0), Vector3.zero, V1, "gogglesDark", true);
            // Red-lens goggles (Sentinel signature): dark frame + glowing lenses.
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.175f, 0.075f, 0.05f)), "pad", new Vector3(0, 0.115f, -0.096f), Vector3.zero, V1, "gogglesRed", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.150f, 0.052f, 0.022f)), "lensred", new Vector3(0, 0.115f, -0.118f), Vector3.zero, V1, "gogglesRed", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.21f, 0.03f, 0.21f)), "pad", new Vector3(0, 0.115f, 0), Vector3.zero, V1, "gogglesRed", true);
            // NVG mount (Sentinel): mount block + flip arm + binocular housing.
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.06f, 0.05f, 0.045f)), "gunmetal", new Vector3(0, 0.195f, -0.10f), Vector3.zero, V1, "nvg", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.03f, 0.035f, 0.07f)), "gunmetal", new Vector3(0, 0.175f, -0.125f), Vector3.zero, V1, "nvg", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.12f, 0.055f, 0.05f)), "gunmetal", new Vector3(0, 0.155f, -0.145f), Vector3.zero, V1, "nvg", true);
            // Boom-mic headset (Sentinel).
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.05f, 0.065f, 0.035f)), "pad", new Vector3(0.115f, 0.10f, -0.01f), Vector3.zero, V1, "boommic", true);
            AddMesh("Head", SoldierMeshes.Cylinder(0.008f, 0.008f, 0.15f), "pad", new Vector3(0.10f, 0.055f, -0.075f), new Vector3(PI * 0.5f, 0, 0), V1, "boommic", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.028f, 0.028f, 0.035f)), "gunmetal", new Vector3(0.10f, 0.055f, -0.145f), Vector3.zero, V1, "boommic", true);
            // Baseball cap (Breacher).
            AddMesh("Head", SoldierMeshes.Sphere(0.125f), "cap", new Vector3(0, 0.155f, 0.01f), Vector3.zero, new Vector3(1f, 0.62f, 1.05f), "cap", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.20f, 0.025f, 0.15f)), "cap", new Vector3(0, 0.125f, -0.155f), Vector3.zero, V1, "cap", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.06f, 0.045f, 0.012f)), "pad", new Vector3(0, 0.16f, -0.108f), Vector3.zero, V1, "cap", true);
            // Visible face (Breacher).
            AddMesh("Head", SoldierMeshes.Sphere(0.102f), "face", new Vector3(0, 0.10f, -0.012f), Vector3.zero, new Vector3(1f, 1.12f, 1.02f), "face", true);
            AddMesh("Head", SoldierMeshes.Sphere(0.108f), "hair", new Vector3(0, 0.135f, 0.028f), Vector3.zero, new Vector3(1.02f, 0.82f, 1.04f), "face", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.03f, 0.05f, 0.022f)), "face", new Vector3(-0.10f, 0.09f, 0), Vector3.zero, V1, "face", true);
            AddMesh("Head", SoldierMeshes.Box(new Vector3(0.03f, 0.05f, 0.022f)), "face", new Vector3(0.10f, 0.09f, 0), Vector3.zero, V1, "face", true);
            // Red shotgun-shell row on the chest rig (Breacher signature).
            AddMesh("VestPlate", SoldierMeshes.Box(new Vector3(0.21f, 0.022f, 0.03f)), "pad", new Vector3(0, 0.115f, -0.185f), Vector3.zero, V1, "shell");
            for (int i = 0; i < 6; i++)
                AddMesh("VestPlate", SoldierMeshes.Cylinder(0.016f, 0.016f, 0.075f), "shellred",
                    new Vector3(-0.078f + 0.031f * i, 0.115f, -0.20f), new Vector3(PI * 0.5f, 0, 0), V1, "shell");
            // Class accent patch (emissive, set via SetClassAccent).
            var acc = new GameObject("ClassAccent");
            acc.transform.SetParent(GetBone("ClavicleL"), false);
            acc.transform.localPosition = new Vector3(0.02f, 0.05f, 0.14f);
            var amf = acc.AddComponent<MeshFilter>();
            amf.sharedMesh = SoldierMeshes.Box(new Vector3(0.09f, 0.06f, 0.02f));
            _accentRenderer = acc.AddComponent<MeshRenderer>();
            _accentRenderer.enabled = false;
            _allRenderers.Add(_accentRenderer);
            ApplyMaterials();
        }

        /// <summary>
        /// Detailed rucksack on its own bone (secondary motion in the anim
        /// system). The most-visible element from behind in third person.
        /// Authored Godot-style (back = +Z), mirrored by AddMesh.
        /// </summary>
        private void BuildBackpack()
        {
            const string B = "Backpack";
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.34f, 0.42f, 0.18f)), "pack", new Vector3(0, 0.02f, 0.10f), Vector3.zero, V1, "");
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.36f, 0.10f, 0.20f)), "pack", new Vector3(0, 0.25f, 0.10f), Vector3.zero, V1, ""); // top lid
            AddMesh(B, SoldierMeshes.Cylinder(0.055f, 0.055f, 0.34f), "pack", new Vector3(0, 0.33f, 0.10f), new Vector3(0, 0, PI * 0.5f), V1, ""); // bedroll
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.025f, 0.13f, 0.215f)), "pad", new Vector3(-0.10f, 0.33f, 0.10f), Vector3.zero, V1, ""); // bedroll strap L
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.025f, 0.13f, 0.215f)), "pad", new Vector3(0.10f, 0.33f, 0.10f), Vector3.zero, V1, ""); // bedroll strap R
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.09f, 0.22f, 0.12f)), "pack", new Vector3(-0.20f, 0.0f, 0.10f), Vector3.zero, V1, ""); // side pouch L
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.09f, 0.22f, 0.12f)), "pack", new Vector3(0.20f, 0.0f, 0.10f), Vector3.zero, V1, ""); // side pouch R
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.20f, 0.16f, 0.06f)), "pack", new Vector3(0, 0.10f, 0.21f), Vector3.zero, V1, ""); // admin pouch
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.05f, 0.34f, 0.015f)), "pad", new Vector3(-0.07f, 0.02f, 0.20f), Vector3.zero, V1, ""); // MOLLE strap L
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.05f, 0.34f, 0.015f)), "pad", new Vector3(0.07f, 0.02f, 0.20f), Vector3.zero, V1, ""); // MOLLE strap R
            AddMesh(B, SoldierMeshes.Cylinder(0.05f, 0.05f, 0.30f), "pack", new Vector3(0, -0.22f, 0.10f), new Vector3(0, 0, PI * 0.5f), V1, ""); // bottom roll
            AddMesh(B, SoldierMeshes.Cylinder(0.012f, 0.012f, 0.50f), "pad", new Vector3(0.12f, 0.10f, 0.17f), new Vector3(0.12f, 0, 0), V1, ""); // hydration tube
            AddMesh(B, SoldierMeshes.Box(new Vector3(0.10f, 0.03f, 0.03f)), "pad", new Vector3(0, 0.31f, 0.10f), Vector3.zero, V1, ""); // grab handle
        }

        private void ApplyMaterials()
        {
            VariantMats vm = GetVariantMats(Variant);
            for (int i = 0; i < _variantMatsList.Count; i++)
            {
                var mf = _variantMatsList[i];
                string key;
                if (_matKey.TryGetValue(mf, out key))
                    mf.GetComponent<MeshRenderer>().sharedMaterial = MatForKey(key, vm);
            }
        }

        // ------------------------------------------------------------------ variant
        private void SetGroup(string group, bool on)
        {
            List<MeshRenderer> list;
            if (!_groups.TryGetValue(group, out list)) return;
            for (int i = 0; i < list.Count; i++) list[i].enabled = on;
        }

        private bool AnyVisible(string group)
        {
            List<MeshRenderer> list;
            if (!_groups.TryGetValue(group, out list)) return false;
            for (int i = 0; i < list.Count; i++) if (list[i].enabled) return true;
            return false;
        }

        public void SetVariant(SoldierVariant v)
        {
            Variant = v;
            bool sentinel = v == SoldierVariant.Sentinel;
            SetGroup("helmet", sentinel);
            SetGroup("gogglesDark", false);
            SetGroup("gogglesRed", sentinel);
            SetGroup("balaclava", sentinel);
            SetGroup("nvg", sentinel);
            SetGroup("boommic", sentinel);
            SetGroup("cap", !sentinel);
            SetGroup("face", !sentinel);
            SetGroup("shell", !sentinel);
            ApplyMaterials();
        }

        public string VariantName() { return Variant.ToString(); }

        /// <summary>Visibility snapshot of gear groups (tests / debugging).</summary>
        public Dictionary<string, bool> GearState()
        {
            var d = new Dictionary<string, bool>();
            foreach (var kv in _groups) d[kv.Key] = AnyVisible(kv.Key);
            return d;
        }

        /// <summary>Class identity accent: small emissive shoulder patch.</summary>
        public void SetClassAccent(Color c)
        {
            if (_accentMat == null)
            {
                _accentMat = MakeEmissive(Color.black, c, 1.5f);
            }
            else
            {
                _accentMat.SetColor("_EmissionColor", c * 1.5f);
            }
            _accentRenderer.sharedMaterial = _accentMat;
            _accentRenderer.enabled = true;
        }

        /// <summary>Hide head + headgear from the player's own camera
        /// (first-person body) while keeping the rest of the body visible.</summary>
        public void SetHeadVisible(bool visible)
        {
            for (int i = 0; i < _headMeshes.Count; i++) _headMeshes[i].enabled = visible;
        }

        // ------------------------------------------------------------------ weapons
        /// <summary>Parent an Arsenal-built gun to the right hand.</summary>
        public void AttachWeapon(GameObject gun)
        {
            if (gun == null) return;
            CurrentWeapon = gun;
            DrawWeapon();
        }

        /// <summary>Move the current weapon to the back sling.</summary>
        public void StowWeapon()
        {
            if (CurrentWeapon == null) return;
            CurrentWeapon.transform.SetParent(BackSling, false);
            CurrentWeapon.transform.localPosition = Vector3.zero;
            CurrentWeapon.transform.localRotation = Quaternion.identity;
        }

        /// <summary>Move the current weapon back to the hands.</summary>
        public void DrawWeapon()
        {
            if (CurrentWeapon == null) return;
            CurrentWeapon.transform.SetParent(WeaponMount, false);
            // Carry pose: receiver in palm, muzzle forward (+Z).
            CurrentWeapon.transform.localPosition = new Vector3(0, 0.01f, 0.22f);
            CurrentWeapon.transform.localRotation = Quaternion.identity;
        }

        public void DetachWeapon()
        {
            CurrentWeapon = null;
        }

        // ------------------------------------------------------------------ queries
        public float RigHeight()
        {
            return GetBone("Head").position.y - transform.position.y + 0.30f;
        }

        /// <summary>Chest height — where shooters aim.</summary>
        public Vector3 AimPoint()
        {
            return GetBone("Chest").position + Vector3.up * 0.06f;
        }

        /// <summary>Estimated muzzle point ahead of the weapon mount.</summary>
        public Vector3 MuzzlePoint()
        {
            Transform w = WeaponMount;
            return w.position + w.forward * 0.55f;
        }

        // ------------------------------------------------------------------ hits/death
        /// <summary>
        /// Directional flinch (action overlay, full body).
        /// hitDirection convention: world-space direction FROM the victim TOWARD
        /// the source of the hit (so a shot from the front gives +Z local).
        /// </summary>
        public void PlayHit(Vector3 worldHitDir)
        {
            if (_dead || Anim == null) return;
            Vector3 local = transform.InverseTransformDirection(worldHitDir);
            SoldierClip clip = SoldierClip.HitFront;
            if (local.z < -0.5f) clip = SoldierClip.HitBack;
            else if (local.z > 0.5f) clip = SoldierClip.HitFront;
            else if (local.x > 0f) clip = SoldierClip.HitRight;
            else clip = SoldierClip.HitLeft;
            Anim.PlayAction(clip);
        }

        /// <summary>
        /// Animated death: picks a fall clip by cause/direction, plays it, then
        /// tweens the body to the ground and holds the corpse for CorpseLifetime
        /// seconds before firing CorpseExpired. hitDirection uses the same
        /// convention as PlayHit (victim -> hit source). No physics ragdoll
        /// (mobile cost); the clip + settle reads as a fall at gameplay distance.
        /// </summary>
        public void Die(DamageCause cause, Vector3 hitDirection)
        {
            if (_dead) return;
            _dead = true;
            _deathPhase = 0;
            _deathT = 0f;
            _lodFar = false;
            Anim.SetLod(false);
            Anim.SetAim(0f, 0f, 0f, false);

            SoldierClip clip = SoldierClip.Death;
            switch (cause)
            {
                case DamageCause.Explosion: clip = SoldierClip.DeathExplosive; break;
                case DamageCause.Headshot: clip = SoldierClip.DeathHeadshot; break;
                case DamageCause.Melee: clip = SoldierClip.DeathKneel; break;
                default:
                    Vector3 local = transform.InverseTransformDirection(hitDirection);
                    if (local.z > 0.5f) clip = SoldierClip.DeathFront;
                    else if (local.z < -0.5f) clip = SoldierClip.Death;
                    else if (Mathf.Abs(local.x) > 0.5f) clip = SoldierClip.DeathSide;
                    else clip = (NovaUtils.Range(0f, 1f) < 0.5f) ? SoldierClip.DeathStumble : SoldierClip.DeathKneel;
                    break;
            }
            Anim.Play(clip, 0.08f, 1f);
        }

        public void Revive()
        {
            _dead = false;
            _deathPhase = 0;
            _deathT = 0f;
            _corpseT = 0f;
            Anim.SetEnabled(true);
            Anim.Play(SoldierClip.Idle, 0.2f, 1f);
        }

        // ------------------------------------------------------------------ runtime
        private void Update()
        {
            if (!_built) return;
            // Staggered LOD check (~4Hz per soldier, offset by instance id).
            _lodT -= Time.deltaTime;
            if (_lodT <= 0f)
            {
                _lodT = 0.25f;
                if (_cam == null) _cam = Camera.main;
                if (_cam != null && !_dead)
                {
                    bool far = (transform.position - _cam.transform.position).sqrMagnitude
                        > LodAnimDistance * LodAnimDistance;
                    if (far != _lodFar)
                    {
                        _lodFar = far;
                        Anim.SetLod(far);
                        bool shadows = !far;
                        if (shadows != _shadowsOn)
                        {
                            _shadowsOn = shadows;
                            var mode = shadows
                                ? UnityEngine.Rendering.ShadowCastingMode.On
                                : UnityEngine.Rendering.ShadowCastingMode.Off;
                            for (int i = 0; i < _allRenderers.Count; i++) _allRenderers[i].shadowCastingMode = mode;
                        }
                    }
                }
            }
            // Death state machine (timers only; posing happens in LateUpdate).
            if (_dead)
            {
                _deathT += Time.deltaTime;
                if (_deathPhase == 0)
                {
                    if (_deathT >= Anim.CurrentClipDuration())
                    {
                        _deathPhase = 1;
                        _deathT = 0f;
                        _settleDrop = 0.12f;
                    }
                }
                else if (_deathPhase == 1)
                {
                    if (_deathT >= 0.5f)
                    {
                        _deathPhase = 2;
                        _corpseT = 0f;
                        Anim.SetEnabled(false); // freeze final pose
                    }
                }
                else
                {
                    _corpseT += Time.deltaTime;
                    if (_corpseT >= CorpseLifetime)
                    {
                        _deathPhase = 3;
                        if (CorpseExpired != null) CorpseExpired(this);
                    }
                }
            }
        }

        private void LateUpdate()
        {
            if (!_built || Anim == null) return;
            if (_lodFar && !_dead) return; // frozen pose while far
            Anim.SamplePose(Time.deltaTime);
            // Settle tween: ease the hips toward the ground after the fall clip.
            if (_dead && _deathPhase == 1)
            {
                float k = Mathf.Clamp01(_deathT / 0.5f);
                k = k * k * (3f - 2f * k);
                Transform hips = Bones[BoneIndex("Hips")];
                hips.position = hips.position + Vector3.down * (_settleDrop * k * Time.deltaTime * 2f);
            }
        }
    }
}
