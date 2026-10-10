using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// Attachment slots + definitions, ported from GunDefs.ATTACHMENTS (gun_defs.gd).
    /// Mod keys (dmg, rpm, rec, ads, magadd, spread, range, silent, move, reload, zoom)
    /// multiply the base gun stats, exactly like Godot's effective().
    /// </summary>
    public struct AttachmentMod
    {
        public string Id, Name, Slot;
        public float DmgMult, RpmMult, RecoilMult, AdsMult, SpreadMult,
                     RangeMult, MoveMult, ReloadMult, Zoom;
        public int MagAdd;
        public bool Silent;
    }

    public struct EffStats
    {
        public float Damage, Rpm, RangeNear, RangeFar, Ads, Move, Spread,
                     RecoilV, RecoilH, Reload, Zoom;
        public int Mag;
        public bool Silent;
    }

    public static class AttachmentData
    {
        public static readonly string[] Slots = new string[] { "muzzle", "optic", "magazine", "underbarrel" };

        /// <summary>Attachment loot pickups that can appear in the world.</summary>
        public static readonly string[] AttachLoot = new string[]
        {
            "suppressor", "compensator", "reddot", "holo",
            "extended", "foregrip", "laser", "scope4"
        };

        private static AttachmentMod A(string id, string name, string slot,
            float dmg = 1f, float rpm = 1f, float rec = 1f, float ads = 1f,
            float spread = 1f, float range = 1f, float move = 1f, float reload = 1f,
            float zoom = 0f, int magadd = 0, bool silent = false)
        {
            return new AttachmentMod
            {
                Id = id, Name = name, Slot = slot,
                DmgMult = dmg, RpmMult = rpm, RecoilMult = rec, AdsMult = ads,
                SpreadMult = spread, RangeMult = range, MoveMult = move,
                ReloadMult = reload, Zoom = zoom, MagAdd = magadd, Silent = silent
            };
        }

        public static readonly AttachmentMod[] Mods = new AttachmentMod[]
        {
            // muzzle
            A("suppressor", "VX Suppressor", "muzzle", dmg: 0.92f, rec: 0.82f, range: 0.9f, ads: 1.06f, silent: true),
            A("compensator", "Tri-Port Comp", "muzzle", rec: 0.78f, ads: 1.04f),
            A("flashhider", "Birdcage FH", "muzzle", rec: 0.92f, spread: 0.94f),
            A("brake", "Tanker Brake", "muzzle", rec: 0.72f, spread: 1.08f, ads: 1.05f),
            // optic
            A("reddot", "RD-1 Dot", "optic", ads: 0.94f, spread: 0.92f),
            A("holo", "HX Holo", "optic", ads: 0.96f, spread: 0.9f),
            A("scope4", "4x Ranger", "optic", ads: 1.18f, range: 1.15f, zoom: 4f),
            A("scope8", "8x Longeye", "optic", ads: 1.3f, range: 1.25f, zoom: 8f),
            // magazine
            A("extended", "Ext. Mag", "magazine", magadd: 12, ads: 1.06f, reload: 1.1f),
            A("fast", "Speed Mag", "magazine", magadd: -4, reload: 0.8f),
            A("drum", "Drum 60", "magazine", magadd: 30, ads: 1.12f, move: 0.97f, reload: 1.25f),
            // underbarrel
            A("foregrip", "Vert Grip", "underbarrel", rec: 0.85f, spread: 0.94f),
            A("bipod", "Tact. Bipod", "underbarrel", rec: 0.7f, ads: 1.1f, move: 0.98f),
            A("laser", "Tac Laser", "underbarrel", spread: 0.8f, ads: 0.95f),
        };

        private static Dictionary<string, AttachmentMod> _byId;

        static AttachmentData()
        {
            _byId = new Dictionary<string, AttachmentMod>(Mods.Length);
            for (int i = 0; i < Mods.Length; i++) _byId[Mods[i].Id] = Mods[i];
        }

        public static bool TryGet(string id, out AttachmentMod mod)
        {
            return _byId.TryGetValue(id, out mod);
        }

        public static string AttachSlot(string id)
        {
            AttachmentMod m;
            return _byId.TryGetValue(id, out m) ? m.Slot : "";
        }

        public static string ModDescription(AttachmentMod m)
        {
            var parts = new List<string>();
            if (m.DmgMult != 1f) parts.Add(string.Format("dmg {0:+0;-0}%", (m.DmgMult - 1f) * 100f));
            if (m.RpmMult != 1f) parts.Add(string.Format("rpm {0:+0;-0}%", (m.RpmMult - 1f) * 100f));
            if (m.RecoilMult != 1f) parts.Add(string.Format("rec {0:+0;-0}%", (m.RecoilMult - 1f) * 100f));
            if (m.AdsMult != 1f) parts.Add(string.Format("ads {0:+0;-0}%", (m.AdsMult - 1f) * 100f));
            if (m.MagAdd != 0) parts.Add(string.Format("mag {0:+0;-0}", m.MagAdd));
            if (m.SpreadMult != 1f) parts.Add(string.Format("spread {0:+0;-0}%", (m.SpreadMult - 1f) * 100f));
            if (m.RangeMult != 1f) parts.Add(string.Format("range {0:+0;-0}%", (m.RangeMult - 1f) * 100f));
            if (m.MoveMult != 1f) parts.Add(string.Format("move {0:+0;-0}%", (m.MoveMult - 1f) * 100f));
            if (m.ReloadMult != 1f) parts.Add(string.Format("reload {0:+0;-0}%", (m.ReloadMult - 1f) * 100f));
            if (m.Silent) parts.Add("suppressed");
            return string.Join(", ", parts.ToArray());
        }

        /// <summary>
        /// Effective stats after attachments, mirroring GunDefs.effective().
        /// Recoil mult applies to both vertical and horizontal (Godot splits GunSpec.Recoil
        /// back 55/45 — same relative order as the original recoil_v/recoil_h).
        /// </summary>
        public static EffStats Effective(GunSpec g, string[] attachIds)
        {
            GunExtended e = GunData.GetExtended(g.Id);
            EffStats s = new EffStats
            {
                Damage = g.Damage, Rpm = g.Rpm,
                RangeNear = e.RangeNear, RangeFar = g.Range,
                Mag = g.MagSize, Ads = g.AdsTime, Move = g.MoveMult,
                Spread = e.HipSpread,
                RecoilV = g.Recoil * 0.55f, RecoilH = g.Recoil * 0.45f,
                Reload = g.ReloadTime, Silent = e.Silent,
                Zoom = e.Zoom
            };
            if (attachIds == null) return s;
            for (int i = 0; i < attachIds.Length; i++)
            {
                AttachmentMod m;
                if (!_byId.TryGetValue(attachIds[i], out m)) continue;
                s.Damage *= m.DmgMult;
                s.Rpm *= m.RpmMult;
                s.RecoilV *= m.RecoilMult;
                s.RecoilH *= m.RecoilMult;
                s.Ads *= m.AdsMult;
                s.Mag = Mathf.Max(1, s.Mag + m.MagAdd);
                s.Spread *= m.SpreadMult;
                s.RangeNear *= m.RangeMult;
                s.RangeFar *= m.RangeMult;
                s.Move *= m.MoveMult;
                s.Reload *= m.ReloadMult;
                if (m.Zoom > 0f) s.Zoom = m.Zoom;
                if (m.Silent) s.Silent = true;
            }
            return s;
        }
    }
}
