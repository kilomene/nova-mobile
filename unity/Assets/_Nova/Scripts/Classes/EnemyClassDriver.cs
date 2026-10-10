using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    /// <summary>
    /// Simple class usage for AI enemies, ported from class_system.gd's
    /// _enemy_ability_tick. Attach alongside the enemy's ClassAbility.
    /// Enemy actives: surgeon self-heal, wildfire defensive smoke,
    /// warden point-blank trap, ballista mortar shell at the player.
    /// </summary>
    [RequireComponent(typeof(ClassAbility))]
    public class EnemyClassDriver : MonoBehaviour
    {
        private ClassAbility _ability;
        private IClassBody _body;
        private float _tickT;
        private float _cdLeft;

        private void Awake()
        {
            _ability = GetComponent<ClassAbility>();
            _body = GetComponent<IClassBody>();
        }

        private void Update()
        {
            if (_ability == null || _body == null || !_body.IsAlive) return;
            if (_cdLeft > 0f) _cdLeft -= Time.deltaTime;
            _tickT -= Time.deltaTime;
            if (_tickT > 0f) return;
            _tickT = 1f;

            GameObject player = CombatHelper.FindPlayer();
            float playerDist = player != null
                ? Vector3.Distance(player.transform.position, transform.position)
                : float.MaxValue;

            switch (_ability.ClassId)
            {
                case "surgeon":
                    if (_body.Hp < 50f && _cdLeft <= 0f)
                    {
                        _cdLeft = 30f;
                        _body.Hp = Mathf.Min(_body.Hp + 30f, _body.MaxHp);
                    }
                    break;
                case "wildfire":
                    if (_body.Hp < 40f && _cdLeft <= 0f)
                    {
                        _cdLeft = 35f;
                        ClassFx.SmokeColumn(transform.position, 5f, 8f,
                            new Color(0.5f, 0.5f, 0.52f, 0.8f));
                    }
                    break;
                case "warden":
                    if (playerDist < 8f && _cdLeft <= 0f)
                    {
                        _cdLeft = 20f;
                        var warden = _ability as WardenAbility;
                        if (warden != null) warden.EnemyPlaceTrap();
                    }
                    break;
                case "ballista":
                    if (player != null && _cdLeft <= 0f)
                    {
                        _cdLeft = 12f;
                        Vector3 tgt = player.transform.position;
                        ClassFx.GroundRing(tgt, 3f, 1f, new Color(1f, 0.4f, 0.2f, 0.7f));
                        CombatHelper.ThrowArc(_ability, transform.position, tgt, 8f, 1f, land =>
                        {
                            ClassFx.Explode(land, 2.5f);
                            var pd = player.GetComponent<IDamageable>();
                            if (pd != null && pd.IsAlive &&
                                Vector3.Distance(player.transform.position, land) < 3f)
                                pd.TakeDamage(15f, land, DamageCause.Explosion);
                        });
                    }
                    break;
            }
        }
    }
}
