#!/usr/bin/env python3
"""Generate Unity GunData.cs from the Godot gun_defs.gd roster (read-only spec).
Usage: python3 gen_gundata.py
Writes: unity/Assets/_Nova/Scripts/Arsenal/GunData.cs
"""
import json, re, os

BASE = "/home/hatch/workspace/nova-mobile-native"
SRC = os.path.join(BASE, "project/scripts/gun_defs.gd")
OUT = os.path.join(BASE, "unity/Assets/_Nova/Scripts/Arsenal/GunData.cs")

src = open(SRC).read()
start = src.index("static var _ROSTER: Array = [")
body = src[start:]
# roster ends at the final "]" of the file
end = body.rfind("]")
raw = body[len("static var _ROSTER: Array = ["):end]
# strip full-line GDScript comments (no '#' inside string literals in the roster)
raw = "\n".join(l for l in raw.split("\n") if not re.match(r"^\s*#", l))
# strip trailing commas before } or ]
wrapped = "[" + raw + "]"
wrapped = re.sub(r",\s*([}\]])", r"\1", wrapped)
roster = json.loads(wrapped)
print("guns:", len(roster))

CLS = {"ar": "AssaultRifle", "smg": "SMG", "lmg": "LMG", "sniper": "Sniper",
       "marksman": "Marksman", "shotgun": "Shotgun", "pistol": "Pistol",
       "launcher": "Launcher", "melee": "Melee"}
AMMO = {"light": "Light", "medium": "Medium", "heavy": "Heavy",
        "shell": "Shell", "rocket": "Rocket", "grenade": "Grenade", "none": "None"}
HEAD = {"sniper": 2.0, "marksman": 1.8, "ar": 1.6, "smg": 1.5, "lmg": 1.5,
        "shotgun": 1.5, "pistol": 1.5, "launcher": 1.0, "melee": 1.0}

def f(v): return repr(float(v))
def cs(s):
    s = str(s).replace("\\", "\\\\").replace('"', '\\"')
    return '"' + s + '"'

def meta_extras(m):
    out = []
    if m.get("receiver", "std") != "std":
        out.append("receiver:" + str(m["receiver"]))
    if m.get("carry_handle", False):
        out.append("carryhandle")
    if m.get("toprail", True) is False:
        out.append("notoprail")
    if m.get("cylinder", False):
        out.append("cylinder")
    if m.get("lever", False):
        out.append("lever")
    if m.get("glow", "none") != "none":
        out.append("glow:" + str(m["glow"]))
    if m.get("twinbarrel", False):
        out.append("twinbarrel")
    return out

def pascal(s):
    # burst_n etc already fine; mode strings
    return {"auto": "Auto", "semi": "Semi", "burst": "Burst", "pump": "Pump",
            "bolt": "Bolt", "melee": "Melee", "rocket": "Rocket",
            "grenade": "Grenade"}[s]

lines = []
lines.append("// AUTO-GENERATED from project/scripts/gun_defs.gd by Tools/gen_gundata.py")
lines.append("// 137 guns. Do not hand-edit; regenerate.")
lines.append("using System;")
lines.append("using UnityEngine;")
lines.append("")
lines.append("namespace NovaMobile.Arsenal")
lines.append("{")
lines.append("    /// <summary>")
lines.append("    /// NOVA arsenal data: 137 original gun designs across all weapon classes.")
lines.append("    /// Ported faithfully from Godot gun_defs.gd. Core contract shape lives here;")
lines.append("    /// GunExtended carries gameplay fields the contract does not (mode, pellets,")
lines.append("    /// spread, penetration, blast, sound mods, reserve).")
lines.append("    /// </summary>")
lines.append("    public enum GunClass { AssaultRifle, SMG, LMG, Sniper, Marksman, Shotgun, Pistol, Launcher, Melee }")
lines.append("    public enum AmmoType { Light, Medium, Heavy, Shell, Rocket, Grenade, None }")
lines.append("    public enum GunFireMode { Auto, Semi, Burst, Pump, Bolt, Melee, Rocket, Grenade }")
lines.append("")
lines.append("    public struct GunModelSpec")
lines.append("    {")
lines.append("        public string Style, Mag, Stock, Sight, Muzzle, Body, Accent;")
lines.append("        public float Barrel;")
lines.append("        public string[] Extras;")
lines.append("    }")
lines.append("")
lines.append("    public struct GunSpec")
lines.append("    {")
lines.append("        public string Id, Name;")
lines.append("        public GunClass Class;")
lines.append("        public AmmoType Ammo;")
lines.append("        public float Damage, HeadMult, Rpm, Range, Recoil, AdsTime, MoveMult;")
lines.append("        public int MagSize;")
lines.append("        public float ReloadTime;")
lines.append("        public GunModelSpec Model;")
lines.append("    }")
lines.append("")
lines.append("    /// <summary>Extended per-gun gameplay data not present in the GunSpec contract.</summary>")
lines.append("    public struct GunExtended")
lines.append("    {")
lines.append("        public string Id, Alias, Role;")
lines.append("        public GunFireMode Mode;")
lines.append("        public int BurstN, Pellets, Reserve0;")
lines.append("        public float RangeNear, HipSpread, Pen, Zoom, Pitch;")
lines.append("        public bool Silent;")
lines.append("        public float BlastRadius, ProjSpeed, ProjGrav;")
lines.append("        public float CrackMult, BodyMult, DecayMult, ThumpMult, DurMult;")
lines.append("        public bool Whoosh;")
lines.append("    }")
lines.append("")
lines.append("    public static class GunData")
lines.append("    {")
lines.append("        public static readonly GunSpec[] Guns = new GunSpec[]")
lines.append("        {")

for g in roster:
    gid = g["id"]; name = g["name"]; cls = g["cls"]
    m = g["model"]
    extras = list(m.get("extras", [])) + meta_extras(m)
    ex_str = "new string[] { " + ", ".join(cs(e) for e in extras) + " }"
    lines.append("            new GunSpec { Id = %s, Name = %s, Class = GunClass.%s, Ammo = AmmoType.%s," % (
        cs(gid), cs(name), CLS[cls], AMMO[g["ammo"]]))
    lines.append("                Damage = %s, HeadMult = %s, Rpm = %s, Range = %s, Recoil = %s, AdsTime = %s, MoveMult = %s," % (
        f(g["damage"]), f(HEAD[cls]), f(g["rpm"]), f(g["range_far"]),
        f(float(g["recoil_v"]) + float(g["recoil_h"])), f(g["ads"]), f(g["move"])))
    lines.append("                MagSize = %d, ReloadTime = %s," % (g["mag"], f(g["reload"])))
    lines.append("                Model = new GunModelSpec { Style = %s, Barrel = %s, Mag = %s, Stock = %s, Sight = %s, Muzzle = %s, Body = %s, Accent = %s, Extras = %s } }," % (
        cs(m.get("style", "modular")), f(m.get("barrel", 0.4)), cs(m.get("mag", "straight")),
        cs(m.get("stock", "fixed")), cs(m.get("sight", "iron")), cs(m.get("muzzle", "flash")),
        cs(m.get("body", "black")), cs(m.get("accent", "none")), ex_str))

lines.append("        };")
lines.append("")
lines.append("        public static readonly GunExtended[] Extended = new GunExtended[]")
lines.append("        {")
for g in roster:
    sm = g.get("sound", {})
    lines.append("            new GunExtended { Id = %s, Alias = %s, Role = %s," % (
        cs(g["id"]), cs(g.get("alias", "")), cs(g.get("role", ""))))
    lines.append("                Mode = GunFireMode.%s, BurstN = %d, Pellets = %d, Reserve0 = %d," % (
        pascal(g["mode"]), g.get("burst_n", 3), g.get("pellets", 1), g.get("reserve0", 0)))
    lines.append("                RangeNear = %s, HipSpread = %s, Pen = %s, Zoom = %s, Pitch = %s, Silent = %s," % (
        f(g["range_near"]), f(g["hip_spread"]), f(g.get("pen", 1.0)), f(g.get("zoom", 0.0)),
        f(g.get("pitch", 1.0)), "true" if g.get("silent", False) else "false"))
    lines.append("                BlastRadius = %s, ProjSpeed = %s, ProjGrav = %s," % (
        f(g.get("blast", 0.0)), f(g.get("proj_speed", 0.0)), f(g.get("proj_grav", 0.0))))
    lines.append("                CrackMult = %s, BodyMult = %s, DecayMult = %s, ThumpMult = %s, DurMult = %s, Whoosh = %s }," % (
        f(sm.get("crack", 1.0)), f(sm.get("body", 1.0)), f(sm.get("decay", 1.0)),
        f(sm.get("thump", 1.0)), f(sm.get("dur", 1.0)),
        "true" if float(sm.get("whoosh", 0.0)) > 0.0 else "false"))
lines.append("        };")
lines.append("")
lines.append('        private static readonly System.Collections.Generic.Dictionary<string, GunSpec> _byId;')
lines.append('        private static readonly System.Collections.Generic.Dictionary<string, GunExtended> _extById;')
lines.append("")
lines.append("        static GunData()")
lines.append("        {")
lines.append('            _byId = new System.Collections.Generic.Dictionary<string, GunSpec>(Guns.Length);')
lines.append('            _extById = new System.Collections.Generic.Dictionary<string, GunExtended>(Extended.Length);')
lines.append("            for (int i = 0; i < Guns.Length; i++) _byId[Guns[i].Id] = Guns[i];")
lines.append("            for (int i = 0; i < Extended.Length; i++) _extById[Extended[i].Id] = Extended[i];")
lines.append("        }")
lines.append("")
lines.append("        public static GunSpec Get(string id)")
lines.append("        {")
lines.append("            GunSpec g;")
lines.append("            return _byId.TryGetValue(id, out g) ? g : default(GunSpec);")
lines.append("        }")
lines.append("")
lines.append("        public static GunExtended GetExtended(string id)")
lines.append("        {")
lines.append("            GunExtended e;")
lines.append("            return _extById.TryGetValue(id, out e) ? e : default(GunExtended);")
lines.append("        }")
lines.append("")
lines.append('        public static bool Has(string id) { return _byId.ContainsKey(id); }')
lines.append("")
lines.append("        public static string FullName(GunSpec g)")
lines.append("        {")
lines.append('            GunExtended e = GetExtended(g.Id);')
lines.append('            return e.Alias.Length > 0 ? g.Name + " \\"" + e.Alias + "\\"" : g.Name;')
lines.append("        }")
lines.append("")
lines.append("        public static string SlotOf(GunClass c)")
lines.append("        {")
lines.append("            if (c == GunClass.Pistol || c == GunClass.Launcher) return \"secondary\";")
lines.append("            if (c == GunClass.Melee) return \"melee\";")
lines.append("            return \"primary\";")
lines.append("        }")
lines.append("")
lines.append("        public static string ClassDisplayName(GunClass c)")
lines.append("        {")
lines.append("            switch (c)")
lines.append("            {")
lines.append('                case GunClass.AssaultRifle: return "Assault Rifle";')
lines.append('                case GunClass.SMG: return "SMG";')
lines.append('                case GunClass.LMG: return "LMG";')
lines.append('                case GunClass.Sniper: return "Sniper";')
lines.append('                case GunClass.Marksman: return "Marksman";')
lines.append('                case GunClass.Shotgun: return "Shotgun";')
lines.append('                case GunClass.Pistol: return "Pistol";')
lines.append('                case GunClass.Launcher: return "Launcher";')
lines.append('                default: return "Melee";')
lines.append("            }")
lines.append("        }")
lines.append("")
lines.append("        /// <summary>Damage with linear falloff between near and far, min 35% past far.</summary>")
lines.append("        public static float DamageAtRange(GunSpec g, float dist)")
lines.append("        {")
lines.append("            GunExtended e = GetExtended(g.Id);")
lines.append("            if (dist <= e.RangeNear) return g.Damage;")
lines.append("            if (dist >= g.Range) return g.Damage * 0.35f;")
lines.append("            float t = (dist - e.RangeNear) / Mathf.Max(g.Range - e.RangeNear, 0.01f);")
lines.append("            return g.Damage * Mathf.Lerp(1f, 0.35f, t);")
lines.append("        }")
lines.append("")
lines.append("        public struct StkInfo { public int Body, Head, ArmoredBody, ArmoredHead; }")
lines.append("")
lines.append("        /// <summary>Shots-to-kill vs 100 HP (body) and 250 armored HP, close range, all landing.</summary>")
lines.append("        public static StkInfo ShotsToKillFull(GunSpec g)")
lines.append("        {")
lines.append("            GunExtended e = GetExtended(g.Id);")
lines.append("            float dmg = g.Damage;")
lines.append("            if (g.Class == GunClass.Shotgun) dmg *= Mathf.Max(e.Pellets, 1);")
lines.append("            if (g.Class == GunClass.Launcher)")
lines.append('                return new StkInfo { Body = 1, Head = 1, ArmoredBody = 1, ArmoredHead = 1 };')
lines.append("            if (dmg <= 0f)")
lines.append('                return new StkInfo { Body = 99, Head = 99, ArmoredBody = 99, ArmoredHead = 99 };')
lines.append("            int body = Mathf.CeilToInt(100f / dmg);")
lines.append("            int head = Mathf.CeilToInt(100f / (dmg * g.HeadMult));")
lines.append("            int abody = Mathf.CeilToInt(250f / dmg);")
lines.append("            int ahead = Mathf.CeilToInt(250f / (dmg * g.HeadMult));")
lines.append("            return new StkInfo { Body = body, Head = head, ArmoredBody = abody, ArmoredHead = ahead };")
lines.append("        }")
lines.append("")
lines.append("        /// <summary>Contract STK: shots-to-kill for one hit profile.</summary>")
lines.append("        public static int ShotsToKill(GunSpec g, bool headshot, bool armored)")
lines.append("        {")
lines.append("            StkInfo s = ShotsToKillFull(g);")
lines.append("            if (headshot) return armored ? s.ArmoredHead : s.Head;")
lines.append("            return armored ? s.ArmoredBody : s.Body;")
lines.append("        }")
lines.append("")
lines.append("        /// <summary>Short STK label for the HUD weapon panel, e.g. \"4 SHOTS · 3 HEAD\".</summary>")
lines.append("        public static string StkLabel(GunSpec g)")
lines.append("        {")
lines.append("            if (g.Class == GunClass.Launcher) return \"1 BLAST KILL\";")
lines.append("            StkInfo s = ShotsToKillFull(g);")
lines.append('            if (g.Class == GunClass.Melee) return s.Body + " SWINGS";')
lines.append('            return s.Body + " SHOTS · " + s.Head + " HEAD";')
lines.append("        }")
lines.append("")
lines.append("        /// <summary>Tier-weighted random gun id. Higher tier -> deadlier classes.</summary>")
lines.append("        public static string RollGun(int tier, System.Random rng)")
lines.append("        {")
lines.append("            var ids = new System.Collections.Generic.List<string>();")
lines.append("            var weights = new System.Collections.Generic.List<double>();")
lines.append("            foreach (GunSpec g in Guns)")
lines.append("            {")
lines.append("                double w = 1.0;")
lines.append("                switch (g.Class)")
lines.append("                {")
lines.append("                    case GunClass.Pistol:")
lines.append("                    case GunClass.Melee: w = tier <= 1 ? 3.0 : 0.4; break;")
lines.append("                    case GunClass.Shotgun:")
lines.append("                    case GunClass.SMG: w = tier <= 2 ? 2.5 : 1.0; break;")
lines.append("                    case GunClass.AssaultRifle: w = tier <= 1 ? 1.5 : 2.5; break;")
lines.append("                    case GunClass.Marksman: w = tier <= 1 ? 0.4 : 2.0; break;")
lines.append("                    case GunClass.LMG:")
lines.append("                    case GunClass.Sniper: w = tier <= 2 ? 0.3 : 2.2; break;")
lines.append("                    case GunClass.Launcher: w = tier <= 2 ? 0.15 : 1.2; break;")
lines.append("                }")
lines.append("                if (tier == 0 && g.Class == GunClass.Launcher) w = 0.0;")
lines.append("                if (g.Id == \"rp7\" && tier >= 4) w = 2.4;")
lines.append("                if (w <= 0.0) continue;")
lines.append("                ids.Add(g.Id); weights.Add(w);")
lines.append("            }")
lines.append("            double total = 0.0;")
lines.append("            for (int i = 0; i < weights.Count; i++) total += weights[i];")
lines.append('            if (total <= 0.0) return "m5";')
lines.append("            double r = rng.NextDouble() * total;")
lines.append("            for (int i = 0; i < ids.Count; i++)")
lines.append("            {")
lines.append("                r -= weights[i];")
lines.append("                if (r <= 0.0) return ids[i];")
lines.append("            }")
lines.append('            return "m5";')
lines.append("        }")
lines.append("")
lines.append("        /// <summary>Default attachments pre-equipped by loot tier (grey->orange).</summary>")
lines.append("        public static string[] TierAttachments(int tier, System.Random rng)")
lines.append("        {")
lines.append('            var outList = new System.Collections.Generic.List<string>();')
lines.append("            if (tier >= 3)")
lines.append("            {")
lines.append('                string[] cands = { "reddot", "foregrip", "extended", "compensator" };')
lines.append("                outList.Add(cands[rng.Next(cands.Length)]);")
lines.append("            }")
lines.append("            if (tier >= 4)")
lines.append("            {")
lines.append('                string[] c2 = { "holo", "suppressor", "laser", "extended" };')
lines.append("                string pick = c2[rng.Next(c2.Length)];")
lines.append("                if (!outList.Contains(pick)) outList.Add(pick);")
lines.append("            }")
lines.append("            if (tier >= 5 && !outList.Contains(\"suppressor\")) outList.Add(\"suppressor\");")
lines.append("            return outList.ToArray();")
lines.append("        }")
lines.append("    }")
lines.append("}")

open(OUT, "w").write("\n".join(lines) + "\n")
print("wrote", OUT)
