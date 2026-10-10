using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Soldiers
{
    /// <summary>All animation clips. Covers the 31-clip concept from the spec
    /// (Idle/Walk/Run/Sprint/Crouch/Prone/Slide/Jump/Land/ADS/Reload/Melee/
    /// Grenade/Hit x4/Death x4/Inspect/Emote x6/Victory) plus the spec's extra
    /// variety clips (executions, wingsuit, parachute, vault, death variants).</summary>
    public enum SoldierClip
    {
        Idle, Walk, Run, Sprint, SprintStop,
        Takeoff, JumpAir, Land,
        Hipfire, Ads,
        ReloadRifle, ReloadPistol, ReloadLauncher, ReloadMelee,
        GrenadeThrow, GrenadeCook,
        Slide, CrouchIdle, CrouchWalk, ProneIdle, ProneCrawl,
        Vault, Melee,
        Wingsuit, Parachute,
        HitFront, HitBack, HitLeft, HitRight,
        Death, DeathHeadshot, DeathExplosive, DeathFront, DeathSide, DeathKneel, DeathStumble,
        ExecNecksnap, ExecThroat, ExecSilent,
        ExecVictimNeck, ExecVictimThroat, ExecVictimSilent,
        Inspect,
        EmoteWave, EmotePoint, EmoteTaunt, EmoteNod, EmoteShrug, EmoteSalute,
        Victory, VictoryCasual,
    }

    /// <summary>One keyframe. pos = final local position (rest + authored offset);
    /// eul = euler OFFSET in degrees, composed as restRot * Euler(offset).</summary>
    public struct AnimKey
    {
        public float time;
        public Vector3 pos;
        public Vector3 eul;
    }

    /// <summary>Baked clip: per-bone key tracks. Built once, shared by all soldiers.</summary>
    public sealed class AnimClipData
    {
        public string Name;
        public float Duration;
        public bool Loop;
        public bool UpperOnly;
        public int[] Bones;
        public AnimKey[][] Keys;
    }

    /// <summary>
    /// Code-driven pose animation for SoldierRig. Clips are data (bone keyframe
    /// tracks authored from the Godot spec), sampled with smoothstep easing.
    /// Layers: base clip + crossfade from previous + one-shot action overlay
    /// + aim layer (upper-body pose + procedural yaw/pitch) + strafe offset +
    /// per-shot jolt. Poses are written straight to bone Transforms — no Unity
    /// AnimationClips (no editor available). The clip library is built once and
    /// shared by every soldier; per-frame work is allocation-free.
    /// The rig drives this via SamplePose(dt) from its own LateUpdate so death
    /// settle tweaks can be applied after sampling, in guaranteed order.
    /// </summary>
    public class SoldierAnim : MonoBehaviour
    {
        private static readonly string[] UpperBones = {
            "Chest", "Neck", "Head", "ClavicleL", "ClavicleR",
            "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
            "HandL", "HandR", "FingerL", "FingerR", "VestPlate", "Backpack", "WeaponMount",
        };

        private static Dictionary<string, AnimClipData> _clips;

        public static string ClipName(SoldierClip c)
        {
            switch (c)
            {
                case SoldierClip.Idle: return "idle";
                case SoldierClip.Walk: return "walk";
                case SoldierClip.Run: return "run";
                case SoldierClip.Sprint: return "sprint";
                case SoldierClip.SprintStop: return "sprint_stop";
                case SoldierClip.Takeoff: return "jump_takeoff";
                case SoldierClip.JumpAir: return "jump_air";
                case SoldierClip.Land: return "jump_land";
                case SoldierClip.Hipfire: return "hipfire_pose";
                case SoldierClip.Ads: return "ads_pose";
                case SoldierClip.ReloadRifle: return "reload_rifle";
                case SoldierClip.ReloadPistol: return "reload_pistol";
                case SoldierClip.ReloadLauncher: return "reload_launcher";
                case SoldierClip.ReloadMelee: return "reload_melee";
                case SoldierClip.GrenadeThrow: return "grenade_throw";
                case SoldierClip.GrenadeCook: return "grenade_cook";
                case SoldierClip.Slide: return "slide";
                case SoldierClip.CrouchIdle: return "crouch_idle";
                case SoldierClip.CrouchWalk: return "crouch_walk";
                case SoldierClip.ProneIdle: return "prone_idle";
                case SoldierClip.ProneCrawl: return "prone_crawl";
                case SoldierClip.Vault: return "vault";
                case SoldierClip.Melee: return "melee_lunge";
                case SoldierClip.Wingsuit: return "wingsuit";
                case SoldierClip.Parachute: return "parachute";
                case SoldierClip.HitFront: return "hit_F";
                case SoldierClip.HitBack: return "hit_B";
                case SoldierClip.HitLeft: return "hit_L";
                case SoldierClip.HitRight: return "hit_R";
                case SoldierClip.Death: return "death";
                case SoldierClip.DeathHeadshot: return "death_head";
                case SoldierClip.DeathExplosive: return "death_explosive";
                case SoldierClip.DeathFront: return "death_fwd";
                case SoldierClip.DeathSide: return "death_side";
                case SoldierClip.DeathKneel: return "death_kneel";
                case SoldierClip.DeathStumble: return "death_stumble";
                case SoldierClip.ExecNecksnap: return "exec_necksnap";
                case SoldierClip.ExecThroat: return "exec_throat";
                case SoldierClip.ExecSilent: return "exec_silent";
                case SoldierClip.ExecVictimNeck: return "exec_victim_neck";
                case SoldierClip.ExecVictimThroat: return "exec_victim_throat";
                case SoldierClip.ExecVictimSilent: return "exec_victim_silent";
                case SoldierClip.Inspect: return "inspect";
                case SoldierClip.EmoteWave: return "emote_wave";
                case SoldierClip.EmotePoint: return "emote_point";
                case SoldierClip.EmoteTaunt: return "emote_taunt";
                case SoldierClip.EmoteNod: return "emote_nod";
                case SoldierClip.EmoteShrug: return "emote_shrug";
                case SoldierClip.EmoteSalute: return "emote_salute";
                case SoldierClip.Victory: return "victory";
                case SoldierClip.VictoryCasual: return "victory_casual";
                default: return "idle";
            }
        }

        // ------------------------------------------------------------- instance
        private Transform[] _bones;
        private Vector3[] _restPos;
        private Quaternion[] _restRot;
        private bool[] _upper;
        private int _chestIdx = -1, _neckIdx = -1, _shoulderLIdx = -1, _shoulderRIdx = -1;

        private SoldierClip _base = SoldierClip.Idle;
        private float _baseT;
        private float _baseRate = 1f;
        private SoldierClip? _prev;
        private float _prevT, _prevRate = 1f, _prevFadeLeft, _prevFadeDur = 0.2f;
        private SoldierClip? _action;
        private float _actionT;
        private float _aimW, _aimYaw, _aimPitch;
        private bool _aimAds;
        private float _strafeYaw;
        private float _jolt;
        private bool _enabled = true;
        private bool _lod;

        public void Setup(SoldierRig rig)
        {
            _bones = rig.Bones;
            _restPos = rig.RestPos;
            _restRot = rig.RestRot;
            _upper = new bool[_bones.Length];
            foreach (string b in UpperBones)
            {
                int i = SoldierRig.BoneIndexOf(b);
                if (i >= 0) _upper[i] = true;
            }
            _chestIdx = SoldierRig.BoneIndexOf("Chest");
            _neckIdx = SoldierRig.BoneIndexOf("Neck");
            _shoulderLIdx = SoldierRig.BoneIndexOf("ShoulderL");
            _shoulderRIdx = SoldierRig.BoneIndexOf("ShoulderR");
            EnsureLibrary();
        }

        public bool HasClip(SoldierClip c) { return _clips.ContainsKey(ClipName(c)); }
        public float ClipDuration(SoldierClip c)
        {
            AnimClipData d;
            return _clips.TryGetValue(ClipName(c), out d) ? d.Duration : 0f;
        }
        public float CurrentClipDuration() { return ClipDuration(_base); }
        public SoldierClip CurrentBase() { return _base; }
        public bool IsActionPlaying() { return _action.HasValue; }

        public void Play(SoldierClip c, float fade = 0.2f, float rate = 1f)
        {
            if (!HasClip(c)) return;
            if (_base == c) { _baseRate = rate; return; }
            _prev = _base; _prevT = _baseT; _prevRate = _baseRate;
            _prevFadeLeft = fade; _prevFadeDur = fade;
            _base = c; _baseT = 0f; _baseRate = rate;
        }

        public void PlayAction(SoldierClip c)
        {
            if (!HasClip(c)) return;
            _action = c; _actionT = 0f;
        }

        public void SetAim(float weight, float yaw, float pitch, bool ads = false)
        {
            _aimW = Mathf.Clamp01(weight);
            _aimYaw = yaw; _aimPitch = pitch; _aimAds = ads;
        }

        public void SetStrafe(float yaw) { _strafeYaw = yaw; }
        public void AddJolt(float a) { _jolt = Mathf.Min(_jolt + a, 2.5f); }
        public void SetEnabled(bool b) { _enabled = b; }
        public void SetLod(bool far) { _lod = far; }

        /// <summary>Test helper: sample a clip at mid-duration; false on error.</summary>
        public bool SampleTest(SoldierClip c)
        {
            string name = ClipName(c);
            if (!_clips.ContainsKey(name) || _bones == null) return false;
            Apply(name, _clips[name].Duration * 0.5f, 1f, false);
            Apply(name, _clips[name].Duration * 0.99f, 0.5f, true);
            return true;
        }

        // ------------------------------------------------------------- sampling
        public void SamplePose(float dt)
        {
            if (!_enabled || _lod || _bones == null) return;
            AnimClipData bc = _clips[ClipName(_base)];
            _baseT = Adv(_baseT, _baseRate * dt, bc);
            if (_prev.HasValue)
            {
                AnimClipData pc = _clips[ClipName(_prev.Value)];
                _prevT = Adv(_prevT, _prevRate * dt, pc);
                _prevFadeLeft -= dt;
                if (_prevFadeLeft <= 0f) _prev = null;
            }
            if (_action.HasValue)
            {
                AnimClipData ac = _clips[ClipName(_action.Value)];
                _actionT += dt;
                if (_actionT >= ac.Duration) _action = null;
            }
            _jolt = Mathf.MoveTowards(_jolt, 0f, dt * 7f);
            // Reset to rest pose.
            for (int i = 0; i < _bones.Length; i++)
            {
                _bones[i].localPosition = _restPos[i];
                _bones[i].localRotation = _restRot[i];
            }
            // Base layer.
            Apply(ClipName(_base), _baseT, 1f, false);
            // Crossfade from previous.
            if (_prev.HasValue)
                Apply(ClipName(_prev.Value), _prevT,
                    Mathf.Clamp01(_prevFadeLeft / _prevFadeDur), false);
            // Action overlay (fast in, smooth out).
            if (_action.HasValue)
            {
                AnimClipData ac = _clips[ClipName(_action.Value)];
                float at = _actionT, dur = ac.Duration;
                float w = Mathf.Min(at / 0.08f, 1f) * Mathf.Clamp01((dur - at) / 0.12f);
                Apply(ClipName(_action.Value), at, w, ac.UpperOnly);
            }
            // Aim layer: upper-body pose + procedural yaw/pitch.
            if (_aimW > 0.01f)
            {
                Apply(_aimAds ? "ads_pose" : "hipfire_pose", _baseT % 1f, _aimW, true);
                ApplyAimProcedural();
            }
            // Strafe torso offset.
            if (Mathf.Abs(_strafeYaw) > 0.01f && _chestIdx >= 0)
                AddYaw(_chestIdx, _strafeYaw * 0.5f);
            // Per-shot jolt on shoulders (pitch sign mirrored for +Z facing).
            if (_jolt > 0.01f)
            {
                if (_shoulderLIdx >= 0) AddPitch(_shoulderLIdx, -_jolt * 0.10f);
                if (_shoulderRIdx >= 0) AddPitch(_shoulderRIdx, -_jolt * 0.10f);
                if (_chestIdx >= 0) AddPitch(_chestIdx, -_jolt * 0.05f);
            }
        }

        private static float Adv(float t, float dt, AnimClipData c)
        {
            t += dt;
            if (c.Loop) return c.Duration > 0f ? t % c.Duration : 0f;
            return Mathf.Min(t, c.Duration - 0.001f);
        }

        private void Apply(string name, float t, float weight, bool upperOnly)
        {
            if (weight <= 0.001f) return;
            AnimClipData c = _clips[name];
            bool full = weight >= 0.999f;
            for (int bi = 0; bi < c.Bones.Length; bi++)
            {
                int idx = c.Bones[bi];
                if (upperOnly && !_upper[idx]) continue;
                AnimKey[] keys = c.Keys[bi];
                int i0 = 0, i1 = 0;
                if (keys.Length > 1)
                {
                    if (t <= keys[0].time) { i0 = 0; i1 = 0; }
                    else if (t >= keys[keys.Length - 1].time) { i0 = keys.Length - 1; i1 = keys.Length - 1; }
                    else
                    {
                        for (int k = 0; k < keys.Length - 1; k++)
                            if (t >= keys[k].time && t <= keys[k + 1].time) { i0 = k; i1 = k + 1; break; }
                    }
                }
                float f = 0f;
                if (i1 != i0)
                {
                    float span = keys[i1].time - keys[i0].time;
                    if (span > 0.0001f) f = (t - keys[i0].time) / span;
                    f = f * f * (3f - 2f * f); // smoothstep
                }
                Vector3 p = Vector3.Lerp(keys[i0].pos, keys[i1].pos, f);
                Vector3 e = Vector3.Lerp(keys[i0].eul, keys[i1].eul, f);
                Transform bone = _bones[idx];
                Quaternion target = _restRot[idx] * Quaternion.Euler(e);
                if (full)
                {
                    bone.localPosition = p;
                    bone.localRotation = target;
                }
                else
                {
                    bone.localPosition = Vector3.Lerp(bone.localPosition, p, weight);
                    bone.localRotation = Quaternion.Slerp(bone.localRotation, target, weight);
                }
            }
        }

        private void ApplyAimProcedural()
        {
            if (_chestIdx < 0) return;
            Quaternion q = _bones[_chestIdx].localRotation;
            // Pitch negated: positive _aimPitch = look up, but +X euler pitches down in Unity.
            q = q * Quaternion.AngleAxis(_aimYaw * 0.45f * _aimW, Vector3.up)
                  * Quaternion.AngleAxis(-_aimPitch * 0.30f * _aimW, Vector3.right);
            _bones[_chestIdx].localRotation = q;
            if (_neckIdx >= 0)
            {
                Quaternion qn = _bones[_neckIdx].localRotation;
                _bones[_neckIdx].localRotation =
                    qn * Quaternion.AngleAxis(_aimYaw * 0.30f * _aimW, Vector3.up);
            }
        }

        private void AddYaw(int idx, float yawDeg)
        {
            _bones[idx].localRotation = _bones[idx].localRotation
                * Quaternion.AngleAxis(yawDeg, Vector3.up);
        }

        private void AddPitch(int idx, float pitchDeg)
        {
            _bones[idx].localRotation = _bones[idx].localRotation
                * Quaternion.AngleAxis(pitchDeg, Vector3.right);
        }

        // ------------------------------------------------------------- library
        private sealed class ClipBuilder
        {
            public readonly Dictionary<string, List<AnimKey>> tracks =
                new Dictionary<string, List<AnimKey>>();

            // Authored in Godot spec values (faces -Z, radians). Converted here:
            // front/back Z mirrored, pitch X negated, radians -> degrees.
            public void K(string bone, float t,
                float px, float py, float pz, float rx, float ry, float rz)
            {
                bone = SoldierRig.RemapBoneName(bone);
                List<AnimKey> list;
                if (!tracks.TryGetValue(bone, out list))
                {
                    list = new List<AnimKey>();
                    tracks[bone] = list;
                }
                list.Add(new AnimKey
                {
                    time = t,
                    pos = new Vector3(px, py, -pz),
                    eul = new Vector3(-rx, ry, rz) * Mathf.Rad2Deg,
                });
            }
        }

        private static void EnsureLibrary()
        {
            if (_clips != null) return;
            _clips = new Dictionary<string, AnimClipData>();
            BuildIdle();
            BuildLocomotion();
            BuildJump();
            BuildAimPoses();
            BuildReloads();
            BuildGrenade();
            BuildSlideCrouchProne();
            BuildVaultMelee();
            BuildAir();
            BuildHits();
            BuildDeathVictory();
            BuildKillVariety();
            BuildExecutions();
            BuildInspectEmotes();
        }

        private static void Done(string name, ClipBuilder b, float dur, bool loop, bool upperOnly = false)
        {
            var bones = new List<int>();
            var keys = new List<AnimKey[]>();
            foreach (var kv in b.tracks)
            {
                int idx = SoldierRig.BoneIndexOf(kv.Key);
                if (idx < 0) continue;
                var list = kv.Value;
                list.Sort((a, b2) => a.time.CompareTo(b2.time));
                Vector3 rest = SoldierRig.RestLocalPos(kv.Key);
                var arr = new AnimKey[list.Count];
                for (int i = 0; i < list.Count; i++)
                {
                    var k = list[i];
                    k.pos = rest + k.pos; // clips author offsets; rest added at build
                    arr[i] = k;
                }
                bones.Add(idx);
                keys.Add(arr);
            }
            _clips[name] = new AnimClipData
            {
                Name = name, Duration = dur, Loop = loop, UpperOnly = upperOnly,
                Bones = bones.ToArray(), Keys = keys.ToArray(),
            };
        }

        // ------------------------------------------------------------- clips
        private static void BuildIdle()
        {
            var b = new ClipBuilder();
            float d = 2.4f;
            for (int i = 0; i < 5; i++)
            {
                float t = d * i / 4f;
                float br = Mathf.Sin(t / d * Mathf.PI * 2f);
                b.K("Spine1", t, 0, 0.004f * br, 0, 0.02f * br, 0, 0);
                b.K("Head", t, 0, 0, 0, 0.03f * br, 0.05f * Mathf.Sin(t * 0.7f), 0);
                b.K("ShoulderL", t, 0, 0, 0, 0.45f + 0.02f * br, 0, 0.10f);
                b.K("ShoulderR", t, 0, 0, 0, 0.45f + 0.02f * br, 0, -0.10f);
                b.K("ForearmL", t, 0, 0, 0, 1.00f, 0, 0);
                b.K("ForearmR", t, 0, 0, 0, 1.00f, 0, 0);
                b.K("Weapon", t, 0, 0, 0, -1.80f, 0, 0);
                b.K("Hips", t, 0, 0.006f * Mathf.Sin(t / d * Mathf.PI * 4f), 0, 0, 0, 0);
                b.K("Backpack", t, 0, 0.004f * br, 0, 0, 0, 0);
            }
            Done("idle", b, d, true);
        }

        private static void BuildLocomotion()
        {
            Loco("walk", 0.615f, 0.44f, 0.75f, 0.06f, 0.030f, "lowready", 0.012f);
            // Run carries the gun ONE-HANDED at the side (like sprint, milder).
            Loco("run", 0.476f, 0.62f, 1.05f, 0.14f, 0.055f, "run_onehand", 0.022f);
            Loco("sprint", 0.329f, 0.78f, 1.25f, 0.30f, 0.075f, "sprint", 0.035f);
            // sprint_stop: 2-3 step decel, torso pitches back then settles.
            var b = new ClipBuilder();
            float d = 0.55f;
            b.K("Spine1", 0, 0, 0, 0, 0.30f, 0, 0);
            b.K("Spine1", d * 0.45f, 0, 0, 0, -0.18f, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.02f, 0, 0);
            for (int i = 0; i < 3; i++)
            {
                float t = d * i / 2f;
                float ph = t / d * Mathf.PI * 2f;
                b.K("ThighL", t, 0, 0, 0, 0.5f * Mathf.Sin(ph), 0, 0);
                b.K("ThighR", t, 0, 0, 0, 0.5f * Mathf.Sin(ph + Mathf.PI), 0, 0);
                b.K("ShinL", t, 0, 0, 0, -0.8f * Mathf.Max(0f, Mathf.Sin(ph + 0.9f)), 0, 0);
                b.K("ShinR", t, 0, 0, 0, -0.8f * Mathf.Max(0f, Mathf.Sin(ph + Mathf.PI + 0.9f)), 0, 0);
            }
            b.K("ShoulderL", 0, 0, 0, 0, 0.15f, 0, 0.1f);
            b.K("ShoulderL", d, 0, 0, 0, 0.45f, 0, 0.1f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.15f, 0, -0.1f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.1f);
            b.K("ForearmL", 0, 0, 0, 0, 0.35f, 0, 0);
            b.K("ForearmL", d, 0, 0, 0, 1.0f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 0.35f, 0, 0);
            b.K("ForearmR", d, 0, 0, 0, 1.0f, 0, 0);
            b.K("Weapon", 0, 0, 0, 0, -0.2f, 0, 0);
            b.K("Weapon", d, 0, 0, 0, -1.8f, 0, 0);
            b.K("Hips", 0, 0, -0.02f, 0, 0, 0, 0);
            b.K("Hips", d, 0, 0, 0, 0, 0, 0);
            Done("sprint_stop", b, d, false);
        }

        private static void Loco(string name, float dur, float swing, float knee,
            float lean, float bob, string armMode, float pack)
        {
            var b = new ClipBuilder();
            int n = 8;
            for (int i = 0; i <= n; i++)
            {
                float t = dur * i / n;
                float ph = t / dur * Mathf.PI * 2f;
                float s = Mathf.Sin(ph);
                b.K("ThighL", t, 0, 0, 0, swing * s, 0, 0);
                b.K("ThighR", t, 0, 0, 0, swing * Mathf.Sin(ph + Mathf.PI), 0, 0);
                b.K("ShinL", t, 0, 0, 0, -knee * Mathf.Max(0f, Mathf.Sin(ph + 0.9f)), 0, 0);
                b.K("ShinR", t, 0, 0, 0, -knee * Mathf.Max(0f, Mathf.Sin(ph + Mathf.PI + 0.9f)), 0, 0);
                b.K("FootL", t, 0, 0, 0, -0.35f * s - 0.25f * Mathf.Max(0f, Mathf.Sin(ph - 0.6f)), 0, 0);
                b.K("FootR", t, 0, 0, 0, -0.35f * Mathf.Sin(ph + Mathf.PI) - 0.25f * Mathf.Max(0f, Mathf.Sin(ph + Mathf.PI - 0.6f)), 0, 0);
                b.K("Hips", t, 0, -bob * (0.5f - 0.5f * Mathf.Cos(2f * ph)), 0, 0.03f * s, 0, 0.02f * s);
                b.K("Spine", t, 0, 0, 0, lean * 0.5f, 0, 0);
                b.K("Spine1", t, 0, 0, 0, lean * 0.5f + 0.02f * Mathf.Sin(2f * ph), 0, 0);
                b.K("Head", t, 0, 0, 0, -lean * 0.55f, 0, 0);
                b.K("Backpack", t, 0, pack * Mathf.Sin(2f * ph + 1.1f), 0.004f * Mathf.Sin(2f * ph + 1.1f),
                    0.06f * Mathf.Sin(2f * ph + 1.1f), 0, 0);
                b.K("VestPlate", t, 0, 0.5f * pack * Mathf.Sin(2f * ph + 0.9f), 0, 0, 0, 0);
                if (armMode == "lowready" || armMode == "lowready_bounce")
                {
                    float bc = armMode == "lowready_bounce" ? 0.10f : 0.03f;
                    b.K("ShoulderL", t, 0, 0, 0, 0.45f + 0.05f * Mathf.Sin(ph + Mathf.PI), 0, 0.12f);
                    b.K("ShoulderR", t, 0, 0, 0, 0.45f + 0.05f * s, 0, -0.12f);
                    b.K("ForearmL", t, 0, 0, 0, 1.00f + bc * Mathf.Sin(2f * ph), 0, 0);
                    b.K("ForearmR", t, 0, 0, 0, 1.00f + bc * Mathf.Sin(2f * ph + 0.5f), 0, 0);
                    b.K("Weapon", t, 0, 0, 0, -1.80f - bc * Mathf.Sin(2f * ph), 0, 0);
                }
                else if (armMode == "run_onehand")
                {
                    b.K("ShoulderR", t, 0, 0, 0, 0.18f + 0.10f * s, 0, -0.06f);
                    b.K("ForearmR", t, 0, 0, 0, 0.35f, 0, 0);
                    b.K("Weapon", t, 0, 0, 0, -0.90f + 1.00f * Mathf.Sin(ph - 0.4f), 0, 0);
                    b.K("ShoulderL", t, 0, 0, 0, 0.60f * Mathf.Sin(ph + 0.4f), 0, 0.14f);
                    b.K("ForearmL", t, 0, 0, 0, 0.55f + 0.40f * Mathf.Max(0f, Mathf.Sin(ph + 1.6f)), 0, 0);
                }
                else if (armMode == "sprint")
                {
                    b.K("ShoulderR", t, 0, 0, 0, 0.16f + 0.06f * s, 0, -0.06f);
                    b.K("ForearmR", t, 0, 0, 0, 0.30f, 0, 0);
                    // Muzzle NOT fixed: swings with the arm pump through the stride.
                    b.K("Weapon", t, 0, 0, 0, -1.24f + 1.70f * Mathf.Sin(ph - 0.4f), 0, 0);
                    b.K("ShoulderL", t, 0, 0, 0, 0.85f * Mathf.Sin(ph + 0.4f), 0, 0.14f);
                    b.K("ForearmL", t, 0, 0, 0, 0.55f + 0.45f * Mathf.Max(0f, Mathf.Sin(ph + 1.6f)), 0, 0);
                }
            }
            Done(name, b, dur, true);
        }

        private static void BuildJump()
        {
            var b = new ClipBuilder();
            float d = 0.16f;
            b.K("Hips", 0, 0, 0, 0, 0, 0, 0);
            b.K("Hips", d, 0, -0.16f, 0, 0, 0, 0);
            b.K("ThighL", 0, 0, 0, 0, 0, 0, 0);
            b.K("ThighR", 0, 0, 0, 0, 0, 0, 0);
            b.K("ThighL", d, 0, 0, 0, 0.55f, 0, 0);
            b.K("ThighR", d, 0, 0, 0, 0.55f, 0, 0);
            b.K("ShinL", d, 0, 0, 0, -0.85f, 0, 0);
            b.K("ShinR", d, 0, 0, 0, -0.85f, 0, 0);
            b.K("ShoulderL", d, 0, 0, 0, -0.5f, 0, 0.2f);
            b.K("ShoulderR", d, 0, 0, 0, -0.5f, 0, -0.2f);
            b.K("Spine1", d, 0, 0, 0, 0.18f, 0, 0);
            Done("jump_takeoff", b, d, false);
            // Air: EXTREME tuck — knees to chest, body pitched ~30° forward.
            b = new ClipBuilder();
            d = 0.6f;
            b.K("Hips", 0, 0, -0.10f, 0, 0, 0, 0);
            b.K("ThighL", 0, 0, 0, 0, 1.78f, 0, 0);
            b.K("ThighR", 0, 0, 0, 0, 1.88f, 0, 0);
            b.K("ShinL", 0, 0, 0, 0, -2.25f, 0, 0);
            b.K("ShinR", 0, 0, 0, 0, -2.35f, 0, 0);
            b.K("FootL", 0, 0, 0, 0, 0.5f, 0, 0);
            b.K("FootR", 0, 0, 0, 0, 0.5f, 0, 0);
            b.K("ShoulderL", 0, 0, 0, 0, 0.55f, 0, 0.15f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.55f, 0, -0.15f);
            b.K("ForearmL", 0, 0, 0, 0, 1.15f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 1.15f, 0, 0);
            b.K("Weapon", 0, 0, 0, 0, -1.70f, 0, 0);
            b.K("Spine1", 0, 0, 0, 0, 0.50f, 0, 0);
            Done("jump_air", b, d, true);
            // Land: VERY deep absorption — near-kneel, torso upright.
            b = new ClipBuilder();
            d = 0.28f;
            b.K("Hips", 0, 0, -0.52f, 0, 0, 0, 0);
            b.K("Hips", d, 0, 0, 0, 0, 0, 0);
            b.K("ThighL", 0, 0, 0, 0, 1.85f, 0, 0);
            b.K("ThighR", 0, 0, 0, 0, 0.55f, 0, 0);
            b.K("ThighL", d, 0, 0, 0, 0, 0, 0);
            b.K("ThighR", d, 0, 0, 0, 0, 0, 0);
            b.K("ShinL", 0, 0, 0, 0, -2.35f, 0, 0);
            b.K("ShinR", 0, 0, 0, 0, -2.10f, 0, 0);
            b.K("ShinL", d, 0, 0, 0, 0, 0, 0);
            b.K("ShinR", d, 0, 0, 0, 0, 0, 0);
            b.K("Spine1", 0, 0, 0, 0, 0.18f, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.02f, 0, 0);
            b.K("ShoulderL", 0, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("ForearmL", 0, 0, 0, 0, 1.0f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 1.0f, 0, 0);
            b.K("Weapon", 0, 0, 0, 0, -1.8f, 0, 0);
            Done("jump_land", b, d, false);
        }

        private static void BuildAimPoses()
        {
            var b = new ClipBuilder();
            b.K("ShoulderL", 0, 0, 0, 0, 0.38f, 0, 0.28f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.38f, 0, -0.28f);
            b.K("ForearmL", 0, 0, 0, 0, 0.72f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 0.72f, 0, 0);
            b.K("Weapon", 0, 0, 0, 0, -1.30f, 0, 0);
            b.K("Spine1", 0, 0, 0, 0, 0.06f, 0, 0);
            b.K("Head", 0, 0, 0, 0, -0.04f, 0, 0);
            Done("hipfire_pose", b, 1f, true);
            b = new ClipBuilder();
            b.K("ShoulderL", 0, 0, 0, 0, 0.95f, 0, 0.10f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.88f, 0, -0.16f);
            b.K("ForearmL", 0, 0, 0, 0, 0.28f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 0.42f, 0, 0);
            b.K("Weapon", 0, 0, 0.10f, 0.02f, -1.12f, -0.06f, 0);
            b.K("Spine1", 0, 0, 0, 0, 0.10f, -0.10f, 0);
            b.K("Head", 0, 0, 0, 0, 0.16f, 0.06f, -0.08f);
            b.K("Neck", 0, 0, 0, 0, 0.08f, 0, 0);
            Done("ads_pose", b, 1f, true);
        }

        private static void BuildReloads()
        {
            // Rifle: gun at CHEST height, canted 30-45° LEFT; head stays up.
            var b = new ClipBuilder();
            float d = 2.2f;
            b.K("Weapon", 0, 0, 0.08f, 0, -1.80f, 0, 0.65f);
            b.K("Weapon", d * 0.3f, -0.05f, 0.02f, 0, -1.80f, 0, 0.68f);
            b.K("Weapon", d * 0.7f, -0.05f, 0.02f, 0, -1.80f, 0, 0.62f);
            b.K("Weapon", d, 0, 0.08f, 0, -1.80f, 0, 0.65f);
            b.K("ShoulderL", 0, 0, 0, 0, 0.55f, 0, 0.12f);
            b.K("ShoulderL", d * 0.3f, 0, 0, 0, 0.38f, 0, 0.25f);
            b.K("ShoulderL", d * 0.55f, 0, 0, 0, 0.62f, 0, 0.10f);
            b.K("ShoulderL", d, 0, 0, 0, 0.55f, 0, 0.12f);
            b.K("ForearmL", 0, 0, 0, 0, 1.0f, 0, 0);
            b.K("ForearmL", d * 0.3f, 0, 0, 0, 1.25f, 0, 0);
            b.K("ForearmL", d * 0.55f, 0, 0, 0, 0.85f, 0, 0);
            b.K("ForearmL", d, 0, 0, 0, 1.0f, 0, 0);
            b.K("Head", 0, 0, 0, 0, 0, 0, 0);
            b.K("Head", d * 0.5f, 0, 0, 0, -0.03f, 0.12f, 0);
            b.K("Head", d, 0, 0, 0, 0, 0, 0);
            Done("reload_rifle", b, d, false, true);
            // Pistol: one hand, slide rack.
            b = new ClipBuilder();
            d = 1.6f;
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.10f);
            b.K("ShoulderR", d * 0.5f, 0, 0, 0, 0.35f, 0, -0.10f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.10f);
            b.K("ForearmR", 0, 0, 0, 0, 0.9f, 0, 0);
            b.K("ForearmR", d * 0.4f, 0, 0, 0, 1.15f, 0, 0);
            b.K("ForearmR", d, 0, 0, 0, 0.9f, 0, 0);
            b.K("ShoulderL", d * 0.55f, 0, 0, 0, 0.75f, 0, 0.15f);
            b.K("ShoulderL", d * 0.8f, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("Weapon", d * 0.5f, 0, 0, 0, -1.5f, 0, 0.35f);
            b.K("Weapon", d, 0, 0, 0, -1.8f, 0, 0);
            Done("reload_pistol", b, d, false, true);
            // Launcher: front-load warhead, muzzle tips up.
            b = new ClipBuilder();
            d = 3.0f;
            b.K("Weapon", 0, 0, 0, 0, -0.4f, 0, 0);
            b.K("Weapon", d * 0.35f, 0, 0.05f, 0, -1.15f, 0.3f, 0);
            b.K("Weapon", d * 0.7f, 0, 0.05f, 0, -1.15f, -0.2f, 0);
            b.K("Weapon", d, 0, 0, 0, -0.4f, 0, 0);
            b.K("ShoulderR", d * 0.35f, 0, 0, 0, 0.9f, 0, -0.2f);
            b.K("ShoulderL", d * 0.35f, 0, 0, 0, 0.7f, 0, 0.3f);
            b.K("Spine1", d * 0.35f, 0, 0, 0, -0.12f, 0.2f, 0);
            Done("reload_launcher", b, d, false, true);
            // Melee: quick weapon check / knife flip.
            b = new ClipBuilder();
            d = 0.8f;
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.1f);
            b.K("ShoulderR", d * 0.5f, 0, 0, 0, 0.15f, 0, -0.35f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.1f);
            b.K("ForearmR", d * 0.5f, 0, 0, 0, 1.6f, 0, 0);
            b.K("Weapon", d * 0.5f, 0, 0, 0, -1.2f, 0, 0.5f);
            Done("reload_melee", b, d, false, true);
        }

        private static void BuildGrenade()
        {
            var b = new ClipBuilder();
            float d = 1.0f;
            b.K("ShoulderL", 0, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderL", 0.22f, 0, 0, 0, -0.85f, 0, 0.35f);
            b.K("ShoulderL", 0.42f, 0, 0, 0, 1.05f, 0, 0.05f);
            b.K("ShoulderL", d, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ForearmL", 0, 0, 0, 0, 1.0f, 0, 0);
            b.K("ForearmL", 0.22f, 0, 0, 0, 2.05f, 0, 0);
            b.K("ForearmL", 0.42f, 0, 0, 0, 0.35f, 0, 0);
            b.K("ForearmL", d, 0, 0, 0, 1.0f, 0, 0);
            b.K("Spine1", 0.22f, 0, 0, 0, -0.10f, 0.25f, 0);
            b.K("Spine1", 0.42f, 0, 0, 0, 0.22f, -0.18f, 0);
            b.K("Spine1", d, 0, 0, 0, 0.02f, 0, 0);
            b.K("ShoulderR", 0.22f, 0, 0, 0, 0.25f, 0, -0.08f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.10f);
            b.K("Weapon", 0.22f, 0, 0, 0, -1.45f, 0, 0);
            b.K("Weapon", d, 0, 0, 0, -1.80f, 0, 0);
            Done("grenade_throw", b, d, false);
            // Cook hold: frozen windup pose (loop).
            b = new ClipBuilder();
            d = 0.6f;
            b.K("ShoulderL", 0, 0, 0, 0, -0.85f, 0, 0.35f);
            b.K("ShoulderL", d, 0, 0, 0, -0.82f, 0, 0.35f);
            b.K("ForearmL", 0, 0, 0, 0, 2.05f, 0, 0);
            b.K("ForearmL", d, 0, 0, 0, 2.02f, 0, 0);
            b.K("Spine1", 0, 0, 0, 0, -0.10f, 0.25f, 0);
            b.K("ShoulderR", 0, 0, 0, 0, 0.25f, 0, -0.08f);
            b.K("Weapon", 0, 0, 0, 0, -1.45f, 0, 0);
            Done("grenade_cook", b, d, true);
        }

        private static void BuildSlideCrouchProne()
        {
            // Slide: body low, legs forward TOGETHER, torso leaned BACK ~27.5°,
            // gun forward and shootable.
            var b = new ClipBuilder();
            float d = 0.7f;
            b.K("Hips", 0, 0, -0.18f, 0, 0, 0, 0);
            b.K("Hips", d * 0.3f, 0, -0.52f, 0, 0, 0, 0);
            b.K("Hips", d, 0, -0.48f, 0, 0, 0, 0);
            b.K("ThighL", d * 0.3f, 0, 0, 0, 1.30f, 0, 0);
            b.K("ThighR", d * 0.3f, 0, 0, 0, 1.22f, 0, 0);
            b.K("ShinL", d * 0.3f, 0, 0, 0, -0.15f, 0, 0);
            b.K("ShinR", d * 0.3f, 0, 0, 0, -0.18f, 0, 0);
            b.K("Spine1", d * 0.3f, 0, 0, 0, -0.48f, 0, 0);
            b.K("ShoulderL", d * 0.3f, 0, 0, 0, 0.75f, 0, 0.15f);
            b.K("ShoulderR", d * 0.3f, 0, 0, 0, 0.75f, 0, -0.15f);
            b.K("ForearmL", d * 0.3f, 0, 0, 0, 0.55f, 0, 0);
            b.K("ForearmR", d * 0.3f, 0, 0, 0, 0.55f, 0, 0);
            b.K("Weapon", d * 0.3f, 0, 0, 0, -1.45f, 0, 0);
            b.K("Head", d * 0.3f, 0, 0, 0, 0.28f, 0, 0);
            Done("slide", b, d, false);
            // Crouch idle.
            b = new ClipBuilder();
            d = 2.0f;
            for (int i = 0; i < 5; i++)
            {
                float t = d * i / 4f;
                float br = Mathf.Sin(t / d * Mathf.PI * 2f);
                b.K("Hips", t, 0, -0.42f + 0.008f * br, 0, 0, 0, 0);
                b.K("ThighL", t, 0, 0, 0, 1.30f, 0, 0);
                b.K("ThighR", t, 0, 0, 0, 1.30f, 0, 0);
                b.K("ShinL", t, 0, 0, 0, -1.95f, 0, 0);
                b.K("ShinR", t, 0, 0, 0, -1.95f, 0, 0);
                b.K("FootL", t, 0, 0, 0, 0.65f, 0, 0);
                b.K("FootR", t, 0, 0, 0, 0.65f, 0, 0);
                b.K("Spine1", t, 0, 0, 0, 0.28f + 0.02f * br, 0, 0);
                b.K("Head", t, 0, 0, 0, -0.22f, 0, 0);
                b.K("ShoulderL", t, 0, 0, 0, 0.55f, 0, 0.14f);
                b.K("ShoulderR", t, 0, 0, 0, 0.55f, 0, -0.14f);
                b.K("ForearmL", t, 0, 0, 0, 0.95f, 0, 0);
                b.K("ForearmR", t, 0, 0, 0, 0.95f, 0, 0);
                b.K("Weapon", t, 0, 0, 0, -1.70f, 0, 0);
            }
            Done("crouch_idle", b, d, true);
            LocoCrouch("crouch_walk", 0.72f);
            // Prone idle.
            b = new ClipBuilder();
            d = 2.4f;
            for (int i = 0; i < 5; i++)
            {
                float t = d * i / 4f;
                float br = Mathf.Sin(t / d * Mathf.PI * 2f);
                b.K("Hips", t, 0, -0.82f, 0, 0, 0, 0);
                b.K("Spine", t, 0, 0, 0, 0.55f, 0, 0);
                b.K("Spine1", t, 0, 0.01f * br, -0.02f, 0.75f + 0.02f * br, 0, 0);
                b.K("Head", t, 0, 0, 0, -1.05f, 0, 0);
                b.K("ThighL", t, 0, 0, 0, -0.45f, 0, -0.06f);
                b.K("ThighR", t, 0, 0, 0, -0.45f, 0, 0.06f);
                b.K("ShinL", t, 0, 0, 0, -0.12f, 0, 0);
                b.K("ShinR", t, 0, 0, 0, -0.12f, 0, 0);
                b.K("ShoulderL", t, 0, 0, 0, 0.85f, 0, 0.35f);
                b.K("ShoulderR", t, 0, 0, 0, 0.85f, 0, -0.35f);
                b.K("ForearmL", t, 0, 0, 0, 0.55f, 0, 0);
                b.K("ForearmR", t, 0, 0, 0, 0.55f, 0, 0);
                b.K("Weapon", t, 0, 0, 0, -1.35f, 0, 0);
            }
            Done("prone_idle", b, d, true);
            // Prone crawl.
            b = new ClipBuilder();
            d = 0.95f;
            int n = 6;
            for (int i = 0; i <= n; i++)
            {
                float t = d * i / n;
                float ph = t / d * Mathf.PI * 2f;
                b.K("Hips", t, 0, -0.82f, 0, 0, 0.06f * Mathf.Sin(ph), 0);
                b.K("Spine1", t, 0, 0, 0, 0.75f, 0, 0.05f * Mathf.Sin(ph));
                b.K("Head", t, 0, 0, 0, -1.05f, 0, 0);
                b.K("ThighL", t, 0, 0, 0, -0.45f + 0.35f * Mathf.Sin(ph), 0, -0.06f);
                b.K("ThighR", t, 0, 0, 0, -0.45f + 0.35f * Mathf.Sin(ph + Mathf.PI), 0, 0.06f);
                b.K("ShinL", t, 0, 0, 0, -0.12f - 0.35f * Mathf.Max(0f, Mathf.Sin(ph + 1.2f)), 0, 0);
                b.K("ShinR", t, 0, 0, 0, -0.12f - 0.35f * Mathf.Max(0f, Mathf.Sin(ph + Mathf.PI + 1.2f)), 0, 0);
                b.K("ShoulderL", t, 0, 0, 0, 0.85f + 0.25f * Mathf.Sin(ph + Mathf.PI), 0, 0.35f);
                b.K("ShoulderR", t, 0, 0, 0, 0.85f + 0.25f * Mathf.Sin(ph), 0, -0.35f);
                b.K("Weapon", t, 0, 0, 0, -1.35f, 0, 0);
            }
            Done("prone_crawl", b, d, true);
        }

        private static void LocoCrouch(string name, float dur)
        {
            var b = new ClipBuilder();
            int n = 6;
            for (int i = 0; i <= n; i++)
            {
                float t = dur * i / n;
                float ph = t / dur * Mathf.PI * 2f;
                float s = Mathf.Sin(ph);
                b.K("Hips", t, 0, -0.42f - 0.02f * (0.5f - 0.5f * Mathf.Cos(2f * ph)), 0, 0, 0, 0);
                b.K("ThighL", t, 0, 0, 0, 1.30f + 0.30f * s, 0, 0);
                b.K("ThighR", t, 0, 0, 0, 1.30f + 0.30f * Mathf.Sin(ph + Mathf.PI), 0, 0);
                b.K("ShinL", t, 0, 0, 0, -1.95f - 0.30f * Mathf.Max(0f, Mathf.Sin(ph + 0.9f)), 0, 0);
                b.K("ShinR", t, 0, 0, 0, -1.95f - 0.30f * Mathf.Max(0f, Mathf.Sin(ph + Mathf.PI + 0.9f)), 0, 0);
                b.K("FootL", t, 0, 0, 0, 0.65f - 0.2f * s, 0, 0);
                b.K("FootR", t, 0, 0, 0, 0.65f - 0.2f * Mathf.Sin(ph + Mathf.PI), 0, 0);
                b.K("Spine1", t, 0, 0, 0, 0.28f, 0, 0);
                b.K("Head", t, 0, 0, 0, -0.22f, 0, 0);
                b.K("ShoulderL", t, 0, 0, 0, 0.55f, 0, 0.14f);
                b.K("ShoulderR", t, 0, 0, 0, 0.55f, 0, -0.14f);
                b.K("ForearmL", t, 0, 0, 0, 0.95f, 0, 0);
                b.K("ForearmR", t, 0, 0, 0, 0.95f, 0, 0);
                b.K("Weapon", t, 0, 0, 0, -1.70f, 0, 0);
            }
            Done(name, b, dur, true);
        }

        private static void BuildVaultMelee()
        {
            var b = new ClipBuilder();
            float d = 0.6f;
            b.K("Hips", 0, 0, 0, 0, 0, 0, 0);
            b.K("Hips", d * 0.5f, 0, 0.55f, 0, 0, 0, 0);
            b.K("Hips", d, 0, 0, 0, 0, 0, 0);
            b.K("ShoulderL", d * 0.3f, 0, 0, 0, 1.35f, 0, 0.2f);
            b.K("ShoulderR", d * 0.3f, 0, 0, 0, 1.35f, 0, -0.2f);
            b.K("ForearmL", d * 0.3f, 0, 0, 0, 0.4f, 0, 0);
            b.K("ForearmR", d * 0.3f, 0, 0, 0, 0.4f, 0, 0);
            b.K("ThighL", d * 0.55f, 0, 0, 0, 1.25f, 0, 0);
            b.K("ShinL", d * 0.55f, 0, 0, 0, -0.9f, 0, 0);
            b.K("ThighR", d * 0.7f, 0, 0, 0, 0.9f, 0, 0);
            b.K("ShinR", d * 0.7f, 0, 0, 0, -1.1f, 0, 0);
            b.K("Spine1", d * 0.5f, 0, 0, 0, 0.25f, 0.15f, 0);
            Done("vault", b, d, false);
            // Melee lunge: knife hand stabs forward, torso twist.
            b = new ClipBuilder();
            d = 0.45f;
            b.K("Spine1", 0, 0, 0, 0, 0.05f, 0, 0);
            b.K("Spine1", d * 0.45f, 0, 0, 0, 0.30f, -0.55f, 0);
            b.K("Spine1", d, 0, 0, 0, 0.05f, 0, 0);
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.1f);
            b.K("ShoulderR", d * 0.45f, 0, 0, 0, 1.35f, 0, -0.05f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.1f);
            b.K("ForearmR", d * 0.45f, 0, 0, 0, 0.15f, 0, 0);
            b.K("ShoulderL", d * 0.45f, 0, 0, 0, 0.2f, 0, 0.4f);
            b.K("Hips", d * 0.45f, 0, -0.08f, 0, 0, 0, 0);
            b.K("Head", d * 0.45f, 0, 0, 0, 0, -0.3f, 0);
            Done("melee_lunge", b, d, false, true);
        }

        private static void BuildAir()
        {
            // Wingsuit: full SPREAD-EAGLE, body flat horizontal, head up.
            var b = new ClipBuilder();
            b.K("Spine", 0, 0, 0, 0, 1.15f, 0, 0);
            b.K("Spine1", 0, 0, 0, 0, 0.30f, 0, 0);
            b.K("Head", 0, 0, 0, 0, -1.05f, 0, 0);
            b.K("ShoulderL", 0, 0, 0, 0, 0.15f, 0, 1.45f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.15f, 0, -1.45f);
            b.K("ForearmL", 0, 0, 0, 0, 0.05f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 0.05f, 0, 0);
            b.K("ThighL", 0, 0, 0, 0, -0.15f, 0, -0.38f);
            b.K("ThighR", 0, 0, 0, 0, -0.15f, 0, 0.38f);
            b.K("ShinL", 0, 0, 0, 0, -0.05f, 0, 0);
            b.K("ShinR", 0, 0, 0, 0, -0.05f, 0, 0);
            Done("wingsuit", b, 1f, true);
            // Parachute: upright, hands up on risers, legs slightly bent.
            b = new ClipBuilder();
            b.K("ShoulderL", 0, 0, 0, 0, 2.55f, 0, 0.25f);
            b.K("ShoulderR", 0, 0, 0, 0, 2.55f, 0, -0.25f);
            b.K("ForearmL", 0, 0, 0, 0, 0.45f, 0, 0);
            b.K("ForearmR", 0, 0, 0, 0, 0.45f, 0, 0);
            b.K("ThighL", 0, 0, 0, 0, 0.28f, 0, 0);
            b.K("ThighR", 0, 0, 0, 0, 0.28f, 0, 0);
            b.K("ShinL", 0, 0, 0, 0, -0.38f, 0, 0);
            b.K("ShinR", 0, 0, 0, 0, -0.38f, 0, 0);
            b.K("Spine1", 0, 0, 0, 0, 0.06f, 0, 0);
            b.K("Head", 0, 0, 0, 0, -0.25f, 0, 0);
            Done("parachute", b, 1.2f, true);
        }

        private static void BuildHits()
        {
            var defs = new System.Collections.Generic.KeyValuePair<string, Vector3>[] {
                new System.Collections.Generic.KeyValuePair<string, Vector3>("hit_F", new Vector3(-0.38f, 0, 0)),
                new System.Collections.Generic.KeyValuePair<string, Vector3>("hit_B", new Vector3(0.38f, 0, 0)),
                new System.Collections.Generic.KeyValuePair<string, Vector3>("hit_L", new Vector3(0, 0, -0.32f)),
                new System.Collections.Generic.KeyValuePair<string, Vector3>("hit_R", new Vector3(0, 0, 0.32f)),
            };
            foreach (var kv in defs)
            {
                var b = new ClipBuilder();
                float d = 0.35f;
                Vector3 j = kv.Value;
                b.K("Spine1", 0, 0, 0, 0, 0, 0, 0);
                b.K("Spine1", d * 0.3f, j.x * 0.2f, 0, j.z * 0.2f, j.x, j.y, j.z);
                b.K("Spine1", d, 0, 0, 0, 0, 0, 0);
                b.K("Head", d * 0.3f, 0, 0, 0, j.x * 0.7f, j.y * 0.7f, j.z * 0.7f);
                b.K("Head", d, 0, 0, 0, 0, 0, 0);
                b.K("ShoulderL", d * 0.3f, 0, 0, 0, j.x * 0.8f, 0, j.z * 0.8f);
                b.K("ShoulderR", d * 0.3f, 0, 0, 0, j.x * 0.8f, 0, j.z * 0.8f);
                b.K("Hips", d * 0.3f, j.x * 0.15f, -0.03f, j.z * 0.15f, 0, 0, 0);
                b.K("Hips", d, 0, 0, 0, 0, 0, 0);
                Done(kv.Key, b, d, false);
            }
        }

        private static void BuildDeathVictory()
        {
            // Death handoff: body crumples (animated fall; no physics ragdoll).
            var b = new ClipBuilder();
            float d = 0.45f;
            b.K("Hips", 0, 0, 0, 0, 0, 0, 0);
            b.K("Hips", d, 0, -0.35f, 0, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.45f, 0.2f, 0);
            b.K("Head", d, 0, 0, 0, 0.35f, 0, 0);
            b.K("ShoulderL", d, 0, 0, 0, 0.1f, 0, 0.35f);
            b.K("ShoulderR", d, 0, 0, 0, 0.1f, 0, -0.35f);
            b.K("ForearmL", d, 0, 0, 0, 0.25f, 0, 0);
            b.K("ForearmR", d, 0, 0, 0, 0.25f, 0, 0);
            b.K("ThighL", d, 0, 0, 0, 0.35f, 0, 0);
            b.K("ThighR", d, 0, 0, 0, 0.25f, 0, 0);
            Done("death", b, d, false);
            // Victory: weapon raised high.
            b = new ClipBuilder();
            d = 2.5f;
            b.K("ShoulderL", 0, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderL", d * 0.3f, 0, 0, 0, 2.7f, 0, 0.15f);
            b.K("ShoulderL", d, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("ShoulderR", d * 0.3f, 0, 0, 0, 2.7f, 0, -0.15f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("Weapon", d * 0.3f, 0, 0, 0, -2.6f, 0, 0);
            b.K("Spine1", d * 0.3f, 0, 0, 0, -0.12f, 0, 0);
            b.K("Head", d * 0.3f, 0, 0, 0, -0.2f, 0, 0);
            b.K("Hips", d * 0.45f, 0, 0.06f, 0, 0, 0, 0);
            b.K("Hips", d * 0.6f, 0, 0, 0, 0, 0, 0);
            Done("victory", b, d, false);
            // Victory casual: weapon lowered, confident nod.
            b = new ClipBuilder();
            d = 2.0f;
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("ShoulderR", d * 0.5f, 0, 0, 0, 0.55f, 0, -0.12f);
            b.K("Head", d * 0.3f, 0, 0, 0, -0.25f, 0, 0);
            b.K("Head", d * 0.6f, 0, 0, 0, 0.1f, 0, 0);
            b.K("Head", d, 0, 0, 0, 0, 0, 0);
            b.K("Spine1", d * 0.5f, 0, 0, 0, -0.08f, 0, 0);
            Done("victory_casual", b, d, false);
        }

        private static void BuildKillVariety()
        {
            var b = new ClipBuilder();
            float d = 0.4f;
            // Headshot snap-back.
            b.K("Head", 0, 0, 0, 0, 0, 0, 0);
            b.K("Head", d * 0.35f, 0, 0, 0, -0.85f, 0, 0);
            b.K("Head", d, 0, 0, 0, -0.3f, 0, 0);
            b.K("Spine1", d * 0.35f, 0, 0, 0, -0.4f, 0, 0);
            b.K("Hips", d, 0, -0.3f, 0, 0, 0, 0);
            b.K("ShoulderL", d * 0.35f, 0, 0, 0, -0.3f, 0, 0.3f);
            b.K("ShoulderR", d * 0.35f, 0, 0, 0, -0.3f, 0, -0.3f);
            Done("death_head", b, d, false);
            // Explosive: hurled backward, limbs flailing.
            b = new ClipBuilder();
            d = 0.45f;
            b.K("Hips", 0, 0, 0, 0, 0, 0, 0);
            b.K("Hips", d, 0, 0.25f, 0.6f, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, -0.6f, 0, 0.2f);
            b.K("Head", d, 0, 0, 0, -0.7f, 0, 0);
            b.K("ShoulderL", d, 0, 0, 0, -1.2f, 0, 0.9f);
            b.K("ShoulderR", d, 0, 0, 0, -1.2f, 0, -0.9f);
            b.K("ThighL", d, 0, 0, 0, 0.9f, 0, 0.2f);
            b.K("ThighR", d, 0, 0, 0, 0.7f, 0, -0.2f);
            Done("death_explosive", b, d, false);
            // Collapse forward onto face.
            b = new ClipBuilder();
            d = 0.5f;
            b.K("Hips", d, 0, -0.5f, -0.15f, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.9f, 0, 0);
            b.K("Head", d, 0, 0, 0, 0.6f, 0, 0);
            b.K("ThighL", d, 0, 0, 0, 0.5f, 0, 0);
            b.K("ThighR", d, 0, 0, 0, 0.4f, 0, 0);
            Done("death_fwd", b, d, false);
            // Crumple sideways.
            b = new ClipBuilder();
            d = 0.5f;
            b.K("Hips", d, 0.25f, -0.45f, 0, 0, 0, 0.5f);
            b.K("Spine1", d, 0, 0, 0, 0, 0, 0.8f);
            b.K("Head", d, 0, 0, 0, 0, 0, 0.6f);
            b.K("ThighL", d, 0, 0, 0, 0, 0, 0.4f);
            Done("death_side", b, d, false);
            // Drop to knees, then pitch over.
            b = new ClipBuilder();
            d = 0.7f;
            b.K("Hips", d * 0.45f, 0, -0.55f, 0, 0, 0, 0);
            b.K("ThighL", d * 0.45f, 0, 0, 0, 1.9f, 0, 0);
            b.K("ThighR", d * 0.45f, 0, 0, 0, 1.7f, 0, 0);
            b.K("ShinL", d * 0.45f, 0, 0, 0, -1.9f, 0, 0);
            b.K("ShinR", d * 0.45f, 0, 0, 0, -1.8f, 0, 0);
            b.K("Hips", d, 0, -0.7f, -0.1f, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.7f, 0, 0);
            b.K("Head", d, 0, 0, 0, 0.4f, 0, 0);
            Done("death_kneel", b, d, false);
            // Two staggering steps, then fall.
            b = new ClipBuilder();
            d = 0.8f;
            b.K("Hips", d * 0.3f, 0, -0.1f, -0.25f, 0.15f, 0, 0.1f);
            b.K("Hips", d * 0.6f, 0, -0.25f, -0.1f, -0.1f, 0, -0.15f);
            b.K("Hips", d, 0, -0.55f, 0.1f, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.5f, 0, 0.2f);
            b.K("ShoulderL", d * 0.5f, 0, 0, 0, 0.6f, 0, 0.5f);
            b.K("ShoulderR", d * 0.5f, 0, 0, 0, 0.6f, 0, -0.5f);
            Done("death_stumble", b, d, false);
        }

        private static void BuildExecutions()
        {
            float d = 1.4f;
            var b = new ClipBuilder();
            // exec_necksnap: grab head, sharp twist.
            b.K("ShoulderR", 0, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("ShoulderR", d * 0.35f, 0, 0.1f, -0.25f, 1.4f, 0, -0.5f);
            b.K("ForearmR", d * 0.35f, 0, 0, 0, 1.1f, 0, 0);
            b.K("ShoulderR", d * 0.55f, 0, 0.1f, -0.25f, 1.4f, -0.9f, -0.5f);
            b.K("Head", d * 0.55f, 0, 0, 0, 0, -0.5f, 0);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("Spine1", d * 0.45f, 0, 0, 0, 0.25f, 0, 0);
            Done("exec_necksnap", b, d, false);
            // exec_throat: arm across throat, drag back.
            b = new ClipBuilder();
            b.K("ShoulderR", d * 0.3f, 0, 0.15f, -0.3f, 1.1f, 0, -1.2f);
            b.K("ForearmR", d * 0.3f, 0, 0, 0, 1.6f, 0, 0);
            b.K("ShoulderR", d * 0.6f, 0, 0.1f, -0.1f, 0.9f, 0, -1.4f);
            b.K("Spine1", d * 0.6f, 0, 0, 0, -0.2f, 0, 0);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.12f);
            Done("exec_throat", b, d, false);
            // exec_silent: hand over mouth, strike, lower the body.
            b = new ClipBuilder();
            b.K("ShoulderL", d * 0.3f, 0, 0.15f, -0.28f, 1.2f, 0, 0.6f);
            b.K("ShoulderR", d * 0.45f, 0, 0.05f, -0.2f, 1.8f, 0, -0.3f);
            b.K("Spine1", d * 0.7f, 0, 0, 0, 0.35f, 0, 0);
            b.K("Hips", d * 0.7f, 0, -0.25f, 0, 0, 0, 0);
            b.K("ShoulderL", d, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.12f);
            Done("exec_silent", b, d, false);
            // Victim variants.
            b = new ClipBuilder();
            b.K("Head", d * 0.5f, 0, 0, 0, 0, 1.4f, 0.3f);
            b.K("Spine1", d * 0.55f, 0, 0, 0, -0.3f, 0.4f, 0);
            b.K("Hips", d * 0.8f, 0, -0.6f, 0, 0, 0, 0);
            b.K("ShoulderL", d * 0.5f, 0, 0, 0, 0.8f, 0, 0.6f);
            b.K("ShoulderR", d * 0.5f, 0, 0, 0, 0.8f, 0, -0.6f);
            Done("exec_victim_neck", b, d, false);
            b = new ClipBuilder();
            b.K("Head", d * 0.5f, 0, 0, 0, -0.5f, 0, 0);
            b.K("ShoulderL", d * 0.4f, 0, 0, 0, 1.0f, 0, 0.8f);
            b.K("Hips", d * 0.8f, 0, -0.65f, 0.1f, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, -0.5f, 0, 0);
            Done("exec_victim_throat", b, d, false);
            b = new ClipBuilder();
            b.K("Head", d * 0.4f, 0, 0, 0, 0.3f, 0, 0);
            b.K("Hips", d, 0, -0.75f, 0, 0, 0, 0);
            b.K("Spine1", d, 0, 0, 0, 0.4f, 0, 0);
            b.K("ThighL", d, 0, 0, 0, 1.4f, 0, 0);
            b.K("ThighR", d, 0, 0, 0, 1.4f, 0, 0);
            Done("exec_victim_silent", b, d, false);
        }

        private struct EmoteSpec
        {
            public SoldierClip clip;
            public string bone;
            public float peak;
            public Vector3 rot;
            public EmoteSpec(SoldierClip c, string b, float p, Vector3 r)
            { clip = c; bone = b; peak = p; rot = r; }
        }

        private static void BuildInspectEmotes()
        {
            // Weapon inspect: lift and look over the gun (~3 s, upper body).
            var b = new ClipBuilder();
            float d = 3.0f;
            b.K("ShoulderL", 0, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderL", d * 0.25f, 0, 0.12f, -0.1f, 0.9f, 0, 0.3f);
            b.K("ShoulderR", d * 0.25f, 0, 0.12f, -0.1f, 0.9f, 0, -0.3f);
            b.K("Head", d * 0.25f, 0, 0, 0, 0.35f, 0, 0);
            b.K("Weapon", d * 0.4f, 0, 0, 0, 0, 0.9f, 0.2f);
            b.K("Weapon", d * 0.6f, 0, 0, 0, 0, -0.9f, -0.2f);
            b.K("Head", d * 0.8f, 0, 0, 0, -0.1f, 0.3f, 0);
            b.K("ShoulderL", d, 0, 0, 0, 0.45f, 0, 0.12f);
            b.K("ShoulderR", d, 0, 0, 0, 0.45f, 0, -0.12f);
            b.K("Head", d, 0, 0, 0, 0, 0, 0);
            b.K("Weapon", d, 0, 0, 0, 0, 0, 0);
            Done("inspect", b, d, false);
            // Emotes: upper-body only, modest 2 s.
            var emotes = new EmoteSpec[] {
                new EmoteSpec(SoldierClip.EmoteWave, "ShoulderR", 0.5f, new Vector3(2.4f, 0, -0.3f)),
                new EmoteSpec(SoldierClip.EmoteWave, "ForearmR", 0.5f, new Vector3(0.3f, 0, 0)),
                new EmoteSpec(SoldierClip.EmotePoint, "ShoulderR", 0.4f, new Vector3(1.5f, 0, -0.1f)),
                new EmoteSpec(SoldierClip.EmotePoint, "Head", 0.4f, new Vector3(0, -0.4f, 0)),
                new EmoteSpec(SoldierClip.EmoteTaunt, "ShoulderL", 0.4f, new Vector3(1.2f, 0, 0.9f)),
                new EmoteSpec(SoldierClip.EmoteTaunt, "ShoulderR", 0.4f, new Vector3(1.2f, 0, -0.9f)),
                new EmoteSpec(SoldierClip.EmoteTaunt, "Head", 0.4f, new Vector3(-0.2f, 0, 0)),
                new EmoteSpec(SoldierClip.EmoteNod, "Head", 0.5f, new Vector3(0.4f, 0, 0)),
                new EmoteSpec(SoldierClip.EmoteShrug, "ShoulderL", 0.5f, new Vector3(0.9f, 0, 0.7f)),
                new EmoteSpec(SoldierClip.EmoteShrug, "ShoulderR", 0.5f, new Vector3(0.9f, 0, -0.7f)),
                new EmoteSpec(SoldierClip.EmoteShrug, "Head", 0.5f, new Vector3(0.15f, 0, 0.2f)),
                new EmoteSpec(SoldierClip.EmoteSalute, "ShoulderR", 0.4f, new Vector3(1.1f, 0, -1.5f)),
                new EmoteSpec(SoldierClip.EmoteSalute, "ForearmR", 0.4f, new Vector3(1.9f, 0, 0)),
                new EmoteSpec(SoldierClip.EmoteSalute, "Head", 0.4f, new Vector3(-0.1f, 0, 0)),
            };
            SoldierClip cur = (SoldierClip)(-1);
            ClipBuilder eb = null;
            foreach (var e in emotes)
            {
                if (e.clip != cur)
                {
                    if (eb != null) Done(ClipName(cur), eb, 2.0f, false, true);
                    cur = e.clip;
                    eb = new ClipBuilder();
                }
                eb.K(e.bone, 0, 0, 0, 0, 0, 0, 0);
                eb.K(e.bone, 2.0f * e.peak, 0, 0, 0, e.rot.x, e.rot.y, e.rot.z);
                eb.K(e.bone, 2.0f, 0, 0, 0, 0, 0, 0);
            }
            if (eb != null) Done(ClipName(cur), eb, 2.0f, false, true);
        }
    }
}
