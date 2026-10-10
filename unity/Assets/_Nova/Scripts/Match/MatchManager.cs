using System;
using UnityEngine;
using NovaMobile.Classes;
using NovaMobile.Player;
using NovaMobile.Soldiers;

namespace NovaMobile.Match
{
    /// <summary>
    /// Match state machine: Lobby -> Drop -> Combat -> Victory/Defeat.
    /// Contract singleton (DontDestroyOnLoad): Instance, Phase, AliveCount.
    /// Ported from main.gd (match flow, drop-in handoff, zone ownership,
    /// kill accounting, airdrops, end screens).
    /// </summary>
    /// <summary>Match flow phases: Lobby -> Drop -> Combat -> Victory/Defeat.</summary>
    public enum MatchPhase { Lobby, Drop, Combat, Victory, Defeat }

    public class MatchManager : MonoBehaviour
    {
        // ---------------- exact contract ----------------
        public static MatchManager Instance;
        public MatchPhase Phase;
        public int AliveCount;

        // ---------------- config ----------------
        /// <summary>Combatants at match start (player + 3 AI teammates + 96 hostile bots).</summary>
        public const int StartAliveCount = 100;
        private const float FirstAirdropAt = 75f;
        private const float AirdropWarnLead = 12f;

        // ---------------- match state ----------------
        public LoadoutData Loadout { get; private set; }
        public PlayerController Player { get; private set; }
        public TouchHUD Hud { get; private set; }

        public int PlayerKills { get; private set; }
        public float DamageDealt { get; private set; }
        public float MatchTime { get; private set; }
        public int Placement { get; private set; }
        public bool WasVictory { get; private set; }

        private LobbyScene _lobby;
        private DropIn _dropIn;
        private Collapse _collapse;
        private bool _airdropWarned;
        private bool _airdropDone;
        private GameObject _touchMinimapMask; // legacy circular minimap, hidden during matches

        public event Action<MatchPhase> PhaseChanged;

        // ---------------- singleton ----------------

        public static MatchManager Ensure()
        {
            if (Instance == null)
            {
                var go = new GameObject("MatchManager");
                Instance = go.AddComponent<MatchManager>();
            }
            return Instance;
        }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }
            Instance = this;
            DontDestroyOnLoad(gameObject);
            Phase = MatchPhase.Lobby;
            AliveCount = StartAliveCount;
            Loadout = LoadoutData.Load();

            // Real explosion FX for class abilities (ClassFx.RequestExplosion).
            ClassFx.RequestExplosion -= ExplosionFx.Spawn;
            ClassFx.RequestExplosion += ExplosionFx.Spawn;
            MatchEvents.PlayerDamageDealt += OnPlayerDamageDealt;
        }

        private void OnDestroy()
        {
            ClassFx.RequestExplosion -= ExplosionFx.Spawn;
            MatchEvents.PlayerDamageDealt -= OnPlayerDamageDealt;
            if (Instance == this) Instance = null;
        }

        private void Start()
        {
            ShowLobby();
        }

        private void Update()
        {
            ExplosionFx.Tick(Time.deltaTime);
            if (Phase != MatchPhase.Combat) return;
            MatchTime += Time.deltaTime;
            UpdateAirdrops();
        }

        // ---------------- flow ----------------

        public void ShowLobby()
        {
            Phase = MatchPhase.Lobby;
            if (_lobby == null) _lobby = LobbyScene.Show(this);
            else _lobby.Show();
            RestoreTouchMinimap();
            RaisePhaseChanged();
        }

        /// <summary>Lobby START button: straight into the drop-in (no pre-match screens).</summary>
        public void StartMatch()
        {
            if (Phase != MatchPhase.Lobby) return;
            Loadout = LoadoutData.Load(); // re-read in case the lobby just saved
            if (_lobby != null) _lobby.Hide();

            Phase = MatchPhase.Drop;
            AliveCount = StartAliveCount;
            PlayerKills = 0;
            DamageDealt = 0f;
            MatchTime = 0f;
            _airdropWarned = false;
            _airdropDone = false;

            EnsureHud();
            EnsurePlayer();
            HideTouchMinimap(); // visual bible: square Match minimap replaces the circular one
            Collapse.Ensure().Reset(); // fresh zone; begins on BeginCombat
            Minimap.Ensure(Hud);
            Killfeed.Ensure(Hud);
            FeedbackLayer.Ensure(Hud).SetAlive(AliveCount, StartAliveCount);
            CorpseManager.Ensure();

            if (_dropIn == null) _dropIn = gameObject.AddComponent<DropIn>();
            _dropIn.Begin(Player, Hud);

            RaisePhaseChanged();
        }

        /// <summary>Drop-in finished: combat starts, zone timer starts.</summary>
        public void BeginCombat()
        {
            if (Phase != MatchPhase.Drop) return;
            Phase = MatchPhase.Combat;
            _collapse = Collapse.Ensure();
            _collapse.Begin();
            MatchEvents.RaiseKillReported("", "100 COMBATANTS DEPLOYED — 25 SQUADS", "");
            RaisePhaseChanged();
        }

        public void EndMatch(bool victory, int placement)
        {
            if (Phase == MatchPhase.Victory || Phase == MatchPhase.Defeat) return;
            WasVictory = victory;
            Placement = placement;
            Phase = victory ? MatchPhase.Victory : MatchPhase.Defeat;
            if (_collapse != null) _collapse.Stop();
            VictoryDefeat.Show(victory, placement, PlayerKills, DamageDealt, MatchTime);
            RaisePhaseChanged();
        }

        /// <summary>Back to the main menu (lobby loadout).</summary>
        public void ToLobby()
        {
            if (_dropIn != null) { Destroy(_dropIn); _dropIn = null; }
            if (_collapse != null) { _collapse.Stop(); }
            if (Minimap.Instance != null) Destroy(Minimap.Instance.gameObject);
            if (Player != null) { Destroy(Player.gameObject); Player = null; }
            VictoryDefeat.Hide();
            AliveCount = StartAliveCount;
            ShowLobby();
        }

        // ---------------- kills ----------------

        /// <summary>
        /// A combatant died. Called by the Squads/combat systems.
        /// Ported from main.gd _on_enemy_killed (+ victory checks).
        /// </summary>
        public void RegisterKill(string killerName, string victimName, string gunId, bool byPlayer)
        {
            if (Phase != MatchPhase.Combat && Phase != MatchPhase.Drop) return;
            AliveCount = Math.Max(0, AliveCount - 1);
            MatchEvents.RaiseKillReported(killerName, victimName, gunId);
            if (byPlayer)
            {
                PlayerKills++;
                FeedbackLayer.Iface.ShowKillBanner(PlayerKills);
            }
            if (FeedbackLayer.Iface != null)
                FeedbackLayer.Iface.SetAlive(AliveCount, StartAliveCount);
            // Last-one-standing victory.
            if (AliveCount <= 1 && Player != null && Player.IsAlive)
                EndMatch(true, 1);
        }

        private void OnPlayerDied()
        {
            if (Phase != MatchPhase.Combat && Phase != MatchPhase.Drop) return;
            int placement = Math.Max(2, AliveCount); // player out with N left standing
            EndMatch(false, placement);
        }

        private void OnPlayerDamageDealt(float amount, Vector3 worldPos)
        {
            DamageDealt += amount;
            if (FeedbackLayer.Iface != null)
                FeedbackLayer.Iface.SpawnDamageNumber(worldPos, amount);
        }

        // ---------------- airdrops ----------------

        private void UpdateAirdrops()
        {
            if (_airdropDone) return;
            if (!_airdropWarned && MatchTime >= FirstAirdropAt - AirdropWarnLead)
            {
                _airdropWarned = true;
                FeedbackLayer.Iface.ShowBanner("FIRST AIRDROP", "SUPPLY DROP INBOUND",
                    new Color(1f, 0.62f, 0.15f), 3f);
            }
            if (MatchTime >= FirstAirdropAt)
            {
                _airdropDone = true;
                Vector3 dropPos = PickAirdropPos();
                AirdropCrate.Spawn(dropPos); // registers its own minimap marker
                MatchEvents.RaiseKillReported("", "AIRDROP LANDED — TOP-TIER LOOT", "");
            }
        }

        private Vector3 PickAirdropPos()
        {
            Vector3 p = Player != null ? Player.transform.position : Vector3.zero;
            float half = World.WorldData.WorldSize * 0.5f - 60f;
            float x = Mathf.Clamp(p.x + UnityEngine.Random.Range(-160f, 160f), -half, half);
            float z = Mathf.Clamp(p.z + UnityEngine.Random.Range(-160f, 160f), -half, half);
            return new Vector3(x, 120f, z);
        }

        // ---------------- setup ----------------

        private void EnsureHud()
        {
            Hud = FindObjectOfType<TouchHUD>();
            if (Hud == null)
            {
                var go = new GameObject("TouchHUD");
                Hud = go.AddComponent<TouchHUD>();
            }
        }

        /// <summary>
        /// The visual bible mandates the square Match minimap; hide the legacy
        /// circular TouchHUD minimap while a match runs (Player agent owns that UI).
        /// </summary>
        private void HideTouchMinimap()
        {
            if (Hud == null || Hud.MinimapView == null) return;
            _touchMinimapMask = Hud.MinimapView.transform.parent.gameObject;
            _touchMinimapMask.SetActive(false);
        }

        private void RestoreTouchMinimap()
        {
            if (_touchMinimapMask != null) _touchMinimapMask.SetActive(true);
            _touchMinimapMask = null;
        }

        private void EnsurePlayer()
        {
            Player = FindObjectOfType<PlayerController>();
            if (Player == null)
            {
                var go = new GameObject("Player");
                Player = go.AddComponent<PlayerController>();
            }
            // Soldiers rig, parented to the player by the Match system.
            var rig = Player.GetComponentInChildren<SoldierRig>();
            if (rig == null) rig = SoldierRig.Build(ToVariant(Loadout.CharacterVariant), "PlayerRig");
            if (rig.transform.parent != Player.transform)
                rig.transform.SetParent(Player.transform, false);
            rig.SetVariant(ToVariant(Loadout.CharacterVariant));

            // Class ability from the lobby loadout.
            if (!string.IsNullOrEmpty(Loadout.ClassId) && ClassAbilityRegistry.Has(Loadout.ClassId))
                ClassAbilityRegistry.Attach(Player.gameObject, Loadout.ClassId);

            if (Hud != null) Player.Hud = Hud;

            Player.Died -= OnPlayerDied;
            Player.Died += OnPlayerDied;

            // Corpse recycling for any SoldierRig the player spawns with is not
            // needed (player has no corpse); bot corpses register via CorpseManager.Register.
        }

        private static SoldierVariant ToVariant(int v)
        {
            return v == 1 ? SoldierVariant.Breacher : SoldierVariant.Sentinel;
        }

        private void RaisePhaseChanged()
        {
            var h = PhaseChanged; if (h != null) h(Phase);
        }
    }
}
