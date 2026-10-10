using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;
using NovaMobile.Player;   // FragGrenade.OnDetonated hook
using NovaMobile.World;    // WorldBuilder.EnemySpawns + GroundHeight

namespace NovaMobile.Squads
{
    /// <summary>
    /// 100-combatant battle royale director, ported from squad_manager.gd:
    /// 25 squads x 4. Squad 0 = local player + 3 AI teammates; squads 1–24 =
    /// 96 enemy bots. Squad tactics (focus fire, flank while others suppress,
    /// revives, zone rotation), throttled hostile targeting, gunshot hearing
    /// (investigate, never wallhack), and abstract resolution of far-away
    /// squad fights so the lobby keeps shrinking where the player can't see.
    ///
    /// ONLINE ROADMAP (Phase 2 — dedicated server + realtime sync):
    /// human_slot 1..30 are architecturally reserved for real network players.
    /// They run as AI today (ReservedOnline) so every match is a full 100
    /// combatants. AttachRemotePlayer is the server hook (returns false until
    /// the server exists).
    /// </summary>
    public class SquadManager : MonoBehaviour
    {
        public static SquadManager Instance { get; private set; }
        public static readonly System.Random Rng = new System.Random();

        public const int SquadSize = 4;
        public const int SquadCount = 25;
        public const int ReservedCount = 30; // human_slot 1..30
        public const int RedeployCost = 2000;

        public static readonly string[] SquadNames = {
            "ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF",
            "HOTEL", "INDIA", "JULIET", "KILO", "LIMA", "MIKE", "NOVEMBER",
            "OSCAR", "PAPA", "QUEBEC", "ROMEO", "SIERRA", "TANGO", "UNIFORM",
            "VICTOR", "WHISKEY", "XRAY", "YANKEE"
        };

        public class Squad
        {
            public int Id;
            public string Name;
            public Color Color;
            public readonly List<BotAgent> Members = new List<BotAgent>();
            public int AliveCount;
            public Vector3 Centroid;
            public SquadOrder Order = SquadOrder.Regroup;
            public Vector3 OrderPos;
            public Squad Focus;
            public readonly Dictionary<BotAgent, string> Roles = new Dictionary<BotAgent, string>();
        }

        // ------------------------------------------------------------------ state
        public Squad[] Squads;
        public readonly List<BotAgent> Combatants = new List<BotAgent>();
        public GameObject Player;
        public Vector3 PlayerPos;
        public bool GameOver;
        public bool TestCeasefire;   // test hook: no targeting, no abstract skirmishes
        public bool AutoSpawn = true; // boot the 100-bot lobby from code

        // Zone data (wired by the Match system; huge defaults = no pressure).
        public Vector2 ZoneCenter = Vector2.zero;
        public float ZoneRadius = 100000f;
        public Vector2 NextZoneCenter = Vector2.zero;
        public float NextZoneRadius = 100000f;

        // Dog tags the local player is carrying (callsigns).
        public readonly List<string> CarriedTags = new List<string>();

        // In-match cash hooks (wired by the Economy system's BuyStation).
        public static Func<int> CashBalance;
        public static Func<int, bool> SpendCash;

        // ------------------------------------------------------------------ events
        /// <summary>Radio net: (callsign, line). UI shows these in the killfeed area.</summary>
        public static event Action<string, string> OnRadioBark;
        /// <summary>Killfeed: (killerCallsign, victimCallsign, cause).</summary>
        public static event Action<string, string, string> OnKillFeed;
        /// <summary>Loot ping: (worldPos, tier 0-6, label). Raised by the Loot system.</summary>
        public static event Action<Vector3, int, string> LootPingged;
        /// <summary>Fired when no hostile combatant remains standing.</summary>
        public static event Action AllHostilesDead;

        public static void RadioBark(string callsign, string[] pool)
        {
            if (pool == null || pool.Length == 0 || OnRadioBark == null) return;
            OnRadioBark(callsign, pool[Rng.Next(pool.Length)]);
        }

        public static void RadioBarkRaw(string callsign, string line)
        {
            if (OnRadioBark != null) OnRadioBark(callsign, line);
        }

        public static void RaiseLootPing(Vector3 pos, int tier, string label)
        {
            if (LootPingged != null) LootPingged(pos, tier, label);
        }

        // ------------------------------------------------------------------ player-fire hook
        private float _playerFireT;
        private Vector3 _playerFirePos;

        /// <summary>Called by the Player weapon code whenever the player fires.</summary>
        public static void NotifyPlayerFired(Vector3 aimPoint)
        {
            if (Instance == null) return;
            Instance._playerFireT = 2f;
            Instance._playerFirePos = aimPoint;
        }

        public bool PlayerFiredRecently(out Vector3 pos)
        {
            pos = _playerFirePos;
            return _playerFireT > 0f;
        }

        // ------------------------------------------------------------------ lifecycle
        private float _squadTickT;
        private int _squadTickI;
        private float _abstractT = 6f;
        private readonly Dictionary<BotAgent, TargetCache> _targetCache =
            new Dictionary<BotAgent, TargetCache>();
        private readonly Dictionary<BotAgent, Vector3> _homePos =
            new Dictionary<BotAgent, Vector3>();
        private readonly List<BotAgent> _aliveScratch = new List<BotAgent>(4);

        private struct TargetCache { public ITargetable Tgt; public float T; }
        private PlayerTarget _playerTarget;

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }
            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        private void OnEnable()
        {
            FragGrenade.OnDetonated += OnExplosionHeard;
        }

        private void OnDisable()
        {
            FragGrenade.OnDetonated -= OnExplosionHeard;
        }

        private void Start()
        {
            if (AutoSpawn) SpawnSquads();
        }

        private void Update()
        {
            if (GameOver) return;
            if (Player != null) PlayerPos = Player.transform.position;
            if (_playerFireT > 0f) _playerFireT -= Time.deltaTime;

            _squadTickT -= Time.deltaTime;
            if (_squadTickT <= 0f)
            {
                _squadTickT = 0.5f;
                SquadThinkTick();
            }
            _abstractT -= Time.deltaTime;
            if (_abstractT <= 0f)
            {
                _abstractT = 4f;
                AbstractTick();
            }
            BotNameplate.Tick();
        }

        private void OnExplosionHeard(Vector3 pos, float radius)
        {
            HearShot(pos, -1); // explosions attract everyone nearby
        }

        // ------------------------------------------------------------------ spawning
        /// <summary>Which (squad_id, slot) pairs are reserved for real online players.</summary>
        public static bool IsReservedSlot(int squadId, int slot)
        {
            if (squadId == 0) return false;
            if (squadId >= 1 && squadId <= 6) return slot <= 1;
            return slot == 0;
        }

        public void RegisterPlayer(GameObject p)
        {
            Player = p;
            if (p != null)
            {
                PlayerPos = p.transform.position;
                _playerTarget = p.GetComponent<PlayerTarget>();
                if (_playerTarget == null) _playerTarget = p.AddComponent<PlayerTarget>();
            }
        }

        public void SpawnSquads()
        {
            if (Squads != null) return; // already spawned
            if (Player == null)
            {
                try
                {
                    var p = GameObject.FindWithTag("Player");
                    if (p != null) RegisterPlayer(p);
                }
                catch (UnityException) { /* tag undefined */ }
            }
            if (Player == null)
            {
                Debug.LogWarning("[SquadManager] No player found; squad spawn aborted.");
                return;
            }
            PlayerPos = Player.transform.position;

            Squads = new Squad[SquadCount];
            Combatants.Clear();
            _targetCache.Clear();
            _homePos.Clear();
            var used = new HashSet<string>();

            // Squad 0: local player (not a BotAgent) + 3 AI teammates.
            var s0 = NewSquad(0);
            Squads[0] = s0;
            for (int i = 0; i < 3; i++)
            {
                Vector3 pos = PlayerPos + Player.transform.right * (i - 1) * 2f
                    - Player.transform.forward * 2f;
                pos.y = GroundY(pos.x, pos.z);
                var a = SpawnBot(pos, 0, i, BotNames.Pick(Rng, used), true, -1, false);
                a.ShotDamage = 10f;
                var tm = a.GetComponent<TeammateAI>();
                if (tm != null) tm.SetupSlot(i);
                s0.Members.Add(a);
                Combatants.Add(a);
            }

            // Squads 1..24: 4 hostile bots each.
            int nextReserved = 1;
            int spawnIdx = 0;
            for (int sid = 1; sid < SquadCount; sid++)
            {
                var s = NewSquad(sid);
                Squads[sid] = s;
                for (int slot = 0; slot < SquadSize; slot++)
                {
                    Vector3 pos = GetSpawnPoint(spawnIdx++);
                    var e = SpawnBot(pos, sid, slot, BotNames.Pick(Rng, used),
                        false, -1, false);
                    if (IsReservedSlot(sid, slot))
                    {
                        e.ReservedOnline = true;
                        e.HumanSlot = nextReserved++;
                    }
                    s.Members.Add(e);
                    Combatants.Add(e);
                }
            }
            RefreshCounts();
        }

        private BotAgent SpawnBot(Vector3 pos, int squadId, int slot, string callsign,
            bool isTeammate, int humanSlot, bool reservedOnline)
        {
            var go = new GameObject("bot");
            var agent = go.AddComponent<BotAgent>();   // adds CharacterController
            if (isTeammate) go.AddComponent<TeammateAI>();
            else go.AddComponent<BotBrain>();
            agent.Setup(squadId, slot, callsign, isTeammate, humanSlot, reservedOnline, this);
            go.transform.position = pos;
            _homePos[agent] = pos;
            agent.Build(Rng);
            return agent;
        }

        private Squad NewSquad(int sid)
        {
            return new Squad
            {
                Id = sid,
                Name = SquadNames[sid % SquadNames.Length],
                Color = Color.HSVToRGB((float)sid / SquadCount, 0.65f, 1f),
            };
        }

        private Vector3 GetSpawnPoint(int i)
        {
            var wb = WorldBuilder.Instance;
            if (wb != null && wb.EnemySpawns.Count > 0)
            {
                Vector3 p = wb.EnemySpawns[i % wb.EnemySpawns.Count];
                p.y = wb.GroundHeight(p.x, p.z) + 0.5f;
                return p;
            }
            // Fallback ring when the world isn't built (tests).
            float a = (i * 2.39996f); // golden angle
            float r = 90f + (i % 40) * 5f;
            return new Vector3(Mathf.Cos(a) * r, 0.5f, Mathf.Sin(a) * r);
        }

        private float GroundY(float x, float z)
        {
            var wb = WorldBuilder.Instance;
            return wb != null ? wb.GroundHeight(x, z) + 0.1f : 0.5f;
        }

        public Vector3 HomePosition(BotAgent a)
        {
            Vector3 h;
            return _homePos.TryGetValue(a, out h) ? h : a.transform.position;
        }

        /// <summary>Phase 2 hook: the dedicated server claims a reserved slot.
        /// Returns false until the server exists — the slot keeps running as AI.</summary>
        public bool AttachRemotePlayer(int humanSlot)
        {
            return false;
        }

        // ------------------------------------------------------------------ queries
        public Squad SquadOf(BotAgent a)
        {
            if (a == null || Squads == null) return null;
            int sid = a.SquadId;
            return (sid >= 0 && sid < Squads.Length) ? Squads[sid] : null;
        }

        public Vector3 SquadOrderPos(BotAgent a)
        {
            var sq = SquadOf(a);
            return sq != null ? sq.OrderPos : a.transform.position;
        }

        public bool HasLivingMate(BotAgent bot)
        {
            var sq = SquadOf(bot);
            if (sq == null) return false;
            for (int i = 0; i < sq.Members.Count; i++)
            {
                var m = sq.Members[i];
                if (m != bot && m != null && !m.IsDead && !m.IsDowned) return true;
            }
            return false;
        }

        public BotAgent DownedMate(BotAgent bot)
        {
            var sq = SquadOf(bot);
            if (sq == null) return null;
            for (int i = 0; i < sq.Members.Count; i++)
            {
                var m = sq.Members[i];
                if (m != bot && m != null && !m.IsDead && m.IsDowned) return m;
            }
            return null;
        }

        /// <summary>
        /// Throttled nearest-hostile lookup (0.6s cache per bot). No aimbot
        /// data: callers must still pass a line-of-sight check before engaging.
        /// The local player is a valid hostile for every bot squad; skydiving
        /// targets are skipped (PlayerTarget reports dead while dropping).
        /// </summary>
        public ITargetable NearestHostile(BotAgent bot, float maxDist = 45f)
        {
            if (TestCeasefire || bot == null) return null;
            float now = Time.time;
            TargetCache c;
            if (_targetCache.TryGetValue(bot, out c))
            {
                if (now - c.T < 0.6f && c.Tgt != null && !c.Tgt.IsDead
                    && c.Tgt.SquadId != bot.SquadId)
                    return c.Tgt;
            }
            Vector3 bp = bot.transform.position;
            ITargetable best = null;
            float bestD = maxDist;
            int bs = bot.SquadId;
            for (int i = 0; i < Combatants.Count; i++)
            {
                var o = Combatants[i];
                if (o == null || o == bot || o.IsDead || o.SquadId == bs) continue;
                Vector3 op = o.transform.position;
                float dx = op.x - bp.x, dz = op.z - bp.z;
                float dd = Mathf.Sqrt(dx * dx + dz * dz);
                if (dd < bestD) { bestD = dd; best = o; }
            }
            if (bs != 0 && _playerTarget != null && !_playerTarget.IsDead
                && Player != null && Player.activeInHierarchy)
            {
                float dx = PlayerPos.x - bp.x, dz = PlayerPos.z - bp.z;
                float dd = Mathf.Sqrt(dx * dx + dz * dz);
                if (dd < bestD) { bestD = dd; best = _playerTarget; }
            }
            _targetCache[bot] = new TargetCache { Tgt = best, T = now };
            return best;
        }

        public int AliveHostiles()
        {
            int n = 0;
            for (int i = 0; i < Combatants.Count; i++)
            {
                var c = Combatants[i];
                if (c != null && !c.IsDead && c.SquadId != 0) n++;
            }
            return n;
        }

        public int AliveSquads()
        {
            if (Squads == null) return 0;
            int n = 0;
            for (int i = 0; i < Squads.Length; i++)
                if (Squads[i] != null && Squads[i].AliveCount > 0) n++;
            return n;
        }

        public bool IsPlayerAlive()
        {
            if (Player == null || !Player.activeInHierarchy) return false;
            var d = Player.GetComponent<IDamageable>();
            if (d != null && !d.IsAlive) return false;
            var dp = Player.GetComponent<IDownedPlayer>();
            if (dp != null && dp.IsDowned) return false;
            return true;
        }

        // ------------------------------------------------------------------ combat events
        public void OnCombatantDown(BotAgent c) { RefreshCounts(); }

        public void OnCombatantDead(BotAgent c, DamageCause cause, bool headshot)
        {
            _targetCache.Remove(c);
            RefreshCounts();
            if (OnKillFeed != null)
                OnKillFeed(c.KillerName(), c.Callsign, CauseString(cause, headshot));
            if (c.IsTeammate)
                DogTag.Make(c.Callsign, this, c.transform.position);
            if (AliveHostiles() == 0 && AllHostilesDead != null)
                AllHostilesDead();
        }

        private static string CauseString(DamageCause cause, bool headshot)
        {
            if (headshot) return "headshot";
            switch (cause)
            {
                case DamageCause.Explosion: return "explosive";
                case DamageCause.Zone: return "zone";
                case DamageCause.Melee: return "melee";
                default: return "bullet";
            }
        }

        /// <summary>
        /// Gunfire attracts nearby squads (hearing, not wallhack: they
        /// investigate the position, they don't gain targets).
        /// </summary>
        public void HearShot(Vector3 pos, int shooterSquadId)
        {
            if (Squads == null) return;
            for (int i = 0; i < Squads.Length; i++)
            {
                var s = Squads[i];
                if (s == null || s.Id == shooterSquadId) continue;
                float dx = s.Centroid.x - pos.x, dz = s.Centroid.z - pos.z;
                if (dx * dx + dz * dz > 55f * 55f) continue;
                for (int k = 0; k < s.Members.Count; k++)
                {
                    var m = s.Members[k];
                    if (m != null && !m.IsDead && !m.IsDowned && m.Driver != null)
                        m.Driver.Investigate(pos, 6f);
                }
            }
        }

        private void RefreshCounts()
        {
            if (Squads == null) return;
            for (int i = 0; i < Squads.Length; i++)
            {
                var s = Squads[i];
                if (s == null) continue;
                int n = 0;
                Vector3 c = Vector3.zero;
                for (int k = 0; k < s.Members.Count; k++)
                {
                    var m = s.Members[k];
                    if (m != null && !m.IsDead)
                    {
                        n++;
                        c += m.transform.position;
                    }
                }
                s.AliveCount = n;
                s.Centroid = n > 0 ? c / n : Vector3.zero;
            }
        }

        // ------------------------------------------------------------------ squad think
        private void SquadThinkTick()
        {
            RefreshCounts();
            if (Squads == null) return;
            int n = Squads.Length;
            for (int k = 0; k < 5; k++)
            {
                var s = Squads[(_squadTickI + k) % n];
                if (s != null) SquadThink(s);
            }
            _squadTickI = (_squadTickI + 5) % n;
        }

        private void SquadThink(Squad s)
        {
            _aliveScratch.Clear();
            var alive = _aliveScratch;
            for (int i = 0; i < s.Members.Count; i++)
            {
                var m = s.Members[i];
                if (m != null && !m.IsDead && !m.IsDowned) alive.Add(m);
            }
            if (alive.Count == 0) return;
            Vector3 centroid = Vector3.zero;
            for (int i = 0; i < alive.Count; i++) centroid += alive[i].transform.position;
            centroid /= alive.Count;
            s.Centroid = centroid;
            int sid = s.Id;

            // 1) Downed mate -> nearest free buddy revives, squad defends.
            BotAgent dm = null;
            for (int i = 0; i < s.Members.Count; i++)
            {
                var m = s.Members[i];
                if (m != null && !m.IsDead && m.IsDowned) { dm = m; break; }
            }
            if (dm != null && alive.Count >= 2)
            {
                BotAgent buddy = null;
                float bd = float.MaxValue;
                for (int i = 0; i < alive.Count; i++)
                {
                    float d = (alive[i].transform.position - dm.transform.position)
                        .sqrMagnitude;
                    if (d < bd) { bd = d; buddy = alive[i]; }
                }
                s.Order = SquadOrder.Defend;
                s.Roles.Clear();
                if (buddy != null) s.Roles[buddy] = "revive";
                return;
            }

            // 2) Zone: rotate early if the centroid is outside the next circle.
            float fdx = centroid.x - NextZoneCenter.x, fdz = centroid.z - NextZoneCenter.y;
            if (Mathf.Sqrt(fdx * fdx + fdz * fdz) > NextZoneRadius && sid != 0)
            {
                s.Order = SquadOrder.Rotate;
                Vector2 flat = new Vector2(centroid.x, centroid.z);
                Vector2 toIn = (NextZoneCenter - flat).normalized;
                s.OrderPos = new Vector3(
                    flat.x + toIn.x * 25f, 0f, flat.y + toIn.y * 25f);
                s.Roles.Clear();
                return;
            }

            // 3) Nearest hostile squad -> attack with focus fire + a flanker.
            Squad foe = null;
            float foeD = float.MaxValue;
            for (int i = 0; i < Squads.Length; i++)
            {
                var o = Squads[i];
                if (o == null || o.Id == sid || o.AliveCount <= 0) continue;
                float dx = o.Centroid.x - centroid.x, dz = o.Centroid.z - centroid.z;
                float d = Mathf.Sqrt(dx * dx + dz * dz);
                if (d < foeD) { foeD = d; foe = o; }
            }
            if (foe != null && foeD < 75f)
            {
                s.Order = SquadOrder.Attack;
                s.Focus = foe;
                Vector2 flat = new Vector2(centroid.x, centroid.z);
                Vector2 fdir = (new Vector2(foe.Centroid.x, foe.Centroid.z) - flat).normalized;
                BotAgent flank = null;
                float bestLat = -1f;
                for (int i = 0; i < alive.Count; i++)
                {
                    Vector3 mp = alive[i].transform.position;
                    float rx = mp.x - centroid.x, rz = mp.z - centroid.z;
                    float lat = Mathf.Abs(rx * -fdir.y + rz * fdir.x);
                    if (lat > bestLat) { bestLat = lat; flank = alive[i]; }
                }
                s.Roles.Clear();
                for (int i = 0; i < alive.Count; i++)
                    s.Roles[alive[i]] = (alive[i] == flank && alive.Count >= 3)
                        ? "flank" : "suppress";
                return;
            }

            // 4) Default: regroup / hold.
            s.Order = SquadOrder.Regroup;
            s.OrderPos = centroid;
            s.Roles.Clear();
        }

        // ------------------------------------------------------------------ abstraction
        /// <summary>
        /// Abstract resolution for far-away squad fights: the lobby keeps
        /// shrinking even where the player can't see. Never touches squad 0.
        /// </summary>
        private void AbstractTick()
        {
            if (TestCeasefire || Squads == null) return;
            RefreshCounts();

            // Zone attrition for bots caught outside the current circle.
            for (int i = 0; i < Combatants.Count; i++)
            {
                var c = Combatants[i];
                if (c == null || c.IsDead || c.SquadId == 0 || c.IsTeammate) continue;
                Vector3 cp = c.transform.position;
                float dx = cp.x - ZoneCenter.x, dz = cp.z - ZoneCenter.y;
                if (Mathf.Sqrt(dx * dx + dz * dz) > ZoneRadius)
                {
                    c.SkipDowned = true;
                    c.DamageBot(12f, cp, DamageCause.Zone, false, null);
                    c.SkipDowned = false;
                }
            }

            // Pairwise skirmishes between close hostile squads, far from player.
            for (int i = 0; i < Squads.Length; i++)
            {
                var a = Squads[i];
                if (a == null || a.Id == 0 || a.AliveCount <= 0) continue;
                float adx = a.Centroid.x - PlayerPos.x, adz = a.Centroid.z - PlayerPos.z;
                if (adx * adx + adz * adz < 220f * 220f) continue; // real AI handles it
                for (int j = i + 1; j < Squads.Length; j++)
                {
                    var b = Squads[j];
                    if (b == null || b.Id == 0 || b.AliveCount <= 0) continue;
                    float ddx = a.Centroid.x - b.Centroid.x, ddz = a.Centroid.z - b.Centroid.z;
                    if (ddx * ddx + ddz * ddz > 90f * 90f) continue;
                    AbstractSkirmish(a, b);
                }
            }
        }

        private void AbstractSkirmish(Squad a, Squad b)
        {
            float sa = a.AliveCount + (float)Rng.NextDouble() * 1.5f;
            float sb = b.AliveCount + (float)Rng.NextDouble() * 1.5f;
            Squad loser = sa >= sb ? b : a;
            Squad winner = sa >= sb ? a : b;
            BotAgent victim = null;
            for (int i = 0; i < loser.Members.Count; i++)
            {
                var m = loser.Members[i];
                if (m != null && !m.IsDead && !m.IsDowned) { victim = m; break; }
            }
            if (victim == null) return;
            BotAgent killer = null;
            for (int i = 0; i < winner.Members.Count; i++)
            {
                var m = winner.Members[i];
                if (m != null && !m.IsDead) { killer = m; break; }
            }
            victim.SkipDowned = true;
            victim.DamageBot(9999f, victim.transform.position,
                DamageCause.Bullet, false, killer != null ? killer.gameObject : null);
            victim.SkipDowned = false;
        }

        // ------------------------------------------------------------------ dog tags / redeploy
        public void CollectTag(string callsign)
        {
            if (!CarriedTags.Contains(callsign))
            {
                CarriedTags.Add(callsign);
                RadioBarkRaw("YOU", "Got " + callsign + "'s tag — redeploy at a buy station.");
            }
        }

        /// <summary>
        /// CODM-style redeploy: spend $2000 at a buy station to drop a dead
        /// teammate back into the match near the player.
        /// </summary>
        public bool TryRedeployTag(string callsign, out string reason)
        {
            reason = null;
            if (!CarriedTags.Contains(callsign))
            {
                reason = "No dog tag carried for " + callsign + ".";
                return false;
            }
            BotAgent mate = null;
            for (int i = 0; i < Combatants.Count; i++)
            {
                var c = Combatants[i];
                if (c != null && c.IsTeammate && c.Callsign == callsign && c.IsDead)
                { mate = c; break; }
            }
            if (mate == null)
            {
                reason = callsign + " is not awaiting redeploy.";
                return false;
            }
            if (SpendCash == null)
            {
                reason = "Buy station economy not connected.";
                return false;
            }
            if (!SpendCash(RedeployCost))
            {
                reason = "Need $2000 to redeploy.";
                return false;
            }
            CarriedTags.Remove(callsign);
            Vector3 at = PlayerPos + new Vector3(Rng.Next(-6, 7), 0f, Rng.Next(-6, 7));
            at.y = GroundY(at.x, at.z);
            mate.Redeploy(at);
            RadioBarkRaw(callsign, "Back in the fight!");
            return true;
        }
    }
}
