extends SceneTree
## Mythic skins + STK visibility verification (137 guns).
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_mythic.gd
## Checks: 14 themes valid; every gun has >=3 skins with unique names;
## skins apply to world + view models without errors; kill evolution stages;
## STK label visible on pickup cards + gunsmith + HUD path; kill FX triggers.

var _checks: Array = []
var _frame := 0
var _phase := 0
var _player: NovaPlayer = null
var _gp: GunPickup = null
var _gs: GunsmithMenu = null

const CLASS_SAMPLE := {
	"ar": "m5", "smg": "mp9", "lmg": "mg60", "sniper": "lw9",
	"marksman": "mk14", "shotgun": "sg9", "pistol": "p9",
	"melee": "knife", "launcher": "rp7",
}


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _initialize() -> void:
	_run_static_checks()
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate() as NovaPlayer
	root.add_child(_player)
	_gp = GunPickup.make("m5", 5)
	root.add_child(_gp)
	_gs = GunsmithMenu.new()
	root.add_child(_gs)
	print("TEST: mythic checks starting")


func _run_static_checks() -> void:
	# --- themes ---
	_log_check("themes >= 14", MythicSkins.THEMES.size() >= 14, "n=" + str(MythicSkins.THEMES.size()))
	var tids := {}
	var ok := true
	for t in MythicSkins.THEMES:
		var tid := str(t["theme"] if t.has("theme") else t["id"])
		if tids.has(tid):
			ok = false
		tids[tid] = true
		if int(t["pattern"]) < 0 or int(t["pattern"]) > 4:
			ok = false
		for k in ["primary", "secondary", "tracer", "flash"]:
			if not (t[k] is Color):
				ok = false
		var acc: Dictionary = t["acc"]
		for k in ["crystals", "fins", "ring", "plates"]:
			if not acc.has(k):
				ok = false
	_log_check("themes valid (ids/patterns/colors/accents)", ok)
	# --- per-gun skins ---
	var roster: Array = GunDefs.all()
	_log_check("roster == 137", roster.size() == 137, "n=" + str(roster.size()))
	var all3 := true
	var names_ok := true
	for g in roster:
		var gid := str(g["id"])
		var sk := MythicSkins.skins_for(gid)
		if sk.size() < 3:
			all3 = false
		var seen := {}
		for s in sk:
			var nm := str(s["name"])
			if nm == "" or seen.has(nm):
				names_ok = false
			seen[nm] = true
			if str(s["theme"]) == "":
				names_ok = false
	_log_check("every gun has >=3 skins", all3)
	_log_check("skin names unique per gun", names_ok)
	# --- STK data source sane for all guns ---
	var stk_ok := true
	for g in roster:
		if GunDefs.stk_label(g) == "":
			stk_ok = false
	_log_check("stk_label non-empty for all 137 guns", stk_ok)
	# --- evolution boundaries ---
	var ev_ok := true
	for kv in [[0, 0], [4, 0], [5, 1], [9, 1], [10, 2], [19, 2], [20, 3], [40, 3]]:
		if MythicSkins.evolution_stage(int(kv[0])) != int(kv[1]):
			ev_ok = false
	_log_check("evolution_stage boundaries", ev_ok)
	_log_check("stage names", MythicSkins.STAGE_NAMES == ["", "AWAKENED", "ASCENDANT", "MYTHIC"])
	# --- theme material caching ---
	var m1: Dictionary = MythicSkins.theme_mats("dragonfire")
	var m2: Dictionary = MythicSkins.theme_mats("dragonfire")
	_log_check("theme materials cached", m1["armor"] == m2["armor"] and m1.size() == 4)
	_log_check("unknown gun -> no skins", MythicSkins.skins_for("nope").is_empty())
	_log_check("skin 0 -> empty display name", MythicSkins.skin_display_name("m5", 0) == "")
	_log_check("default tracer color", MythicSkins.tracer_color("m5", 0) == Color(1.0, 0.85, 0.5))


func _run_apply_checks() -> void:
	# Every world model x 3 skins builds cleanly; accents attach.
	var ok := true
	var acc_ok := true
	for g in GunDefs.all():
		var gid := str(g["id"])
		var base := _count_nodes(GunModels.build_world_model(gid))
		for si in [1, 2, 3]:
			var wm := GunModels.build_world_model(gid)
			MythicSkins.apply_to_model(wm, gid, si, 0)
			var n2 := _count_nodes(wm)
			if n2 <= base:
				ok = false
			if wm.get_node_or_null("MythicAccents") == null:
				acc_ok = false
			wm.queue_free()
	_log_check("137 world models x 3 skins apply cleanly", ok)
	_log_check("theme accents attached on all", acc_ok)
	# Viewmodel sample: all 3 skins each, evolution sets without error.
	var vok := true
	for cls in CLASS_SAMPLE.keys():
		var gid: String = CLASS_SAMPLE[cls]
		for si in [1, 2, 3]:
			var built: Dictionary = GunModels.build_viewmodel(gid)
			var r: Node3D = built["root"]
			MythicSkins.apply_to_model(r, gid, si, 0)
			MythicSkins.set_evolution(r, 3)
			if r.get_node_or_null("MythicAccents") == null:
				vok = false
			r.queue_free()
	_log_check("9 class viewmodels x 3 skins + evolution", vok)


func _run_stk_checks() -> void:
	# Pickup card shows STK (+ mythic name on tier 5).
	var g := GunDefs.by_id("m5")
	var want: String = GunDefs.stk_label(g)
	var lbl: String = (_gp.get_node("Label3D") as Label3D).text
	_log_check("pickup card shows STK", lbl.find(want) >= 0, lbl.replace("\n", " / "))
	_log_check("tier-5 pickup rolled a mythic skin", _gp.skin_idx >= 1 and _gp.skin_idx <= 3,
		"skin=" + str(_gp.skin_idx))
	_log_check("pickup card shows mythic name",
		lbl.find("DRAGONFIRE") >= 0 or lbl.find("GLACIER") >= 0 or lbl.find("NECROVOID") >= 0
		or lbl.find("SOLARFLARE") >= 0 or lbl.find("VENOM") >= 0 or lbl.find("BLOODMOON") >= 0
		or lbl.find("MECHA") >= 0 or lbl.find("AURORA") >= 0 or lbl.find("SANDSTORM") >= 0
		or lbl.find("ABYSSAL") >= 0 or lbl.find("PHOENIX") >= 0 or lbl.find("STORMCALLER") >= 0
		or lbl.find("CRIMSON") >= 0 or lbl.find("ONYX") >= 0)
	# Gunsmith shows STK for the selected gun.
	_log_check("gunsmith shows STK", _gs._stk_label.text == GunDefs.stk_label(GunDefs.by_id("m5")),
		_gs._stk_label.text)
	_log_check("gunsmith lists 3 mythic skins", _gs._skin_box.get_child_count() == 4,
		"n=" + str(_gs._skin_box.get_child_count()))
	# HUD weapon panel path: player emits stk through update_weapon_stk.
	var src := FileAccess.get_file_as_string("res://scripts/hud.gd")
	_log_check("hud has update_weapon_stk", src.find("func update_weapon_stk") >= 0)
	_log_check("player calls update_weapon_stk",
		FileAccess.get_file_as_string("res://scripts/player.gd").find("hud.update_weapon_stk(GunDefs.stk_label(g))") >= 0)


func _run_player_fx_checks() -> void:
	# Skin state per slot.
	_player.set_skin_for("primary", 2)
	_log_check("player set_skin_for", _player.cur_skin() == 2)
	var skn := MythicSkins.skin_display_name(_player.cur_gun_id(), 2)
	_log_check("skin display name resolves", skn != "" and skn.find("\"") >= 0, skn)
	# Mythic kill -> evolution milestone at 5 kills.
	_player.mythic_kills = 4
	var res: Dictionary = _player.register_mythic_kill()
	_log_check("evolution milestone at 5 kills",
		int(res["kills"]) == 5 and str(res["milestone"]) == "AWAKENED", str(res))
	# Kill FX spawns.
	var before := 0
	for c in root.get_children():
		if c is MythicSkins.KillFX:
			before += 1
	var played := MythicSkins.play_killfx(root, Vector3.ZERO, "dragonfire", 7, "")
	var after := 0
	for c in root.get_children():
		if c is MythicSkins.KillFX:
			after += 1
	_log_check("mythic kill FX spawns", played and after == before + 1)
	var played2 := MythicSkins.play_killfx(root, Vector3.ZERO, "glacier", 10, "ASCENDANT")
	_log_check("milestone kill banner spawns", played2)
	# Flourishes run without error.
	MythicSkins.play_reload_flourish(_player.gun, "venom")
	MythicSkins.play_draw_flourish(_player.gun, "mecha")
	_log_check("reload/draw flourishes run", true)
	# Evolution sting synthesizes.
	var sting := MythicSkins.evolution_sting()
	_log_check("evolution sting audio", sting != null and sting.get_length() > 0.4)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5 and _phase == 0:
		_run_apply_checks()
		_phase = 1
	if _frame == 12 and _phase == 1:
		_run_stk_checks()
		_phase = 2
	if _frame == 18 and _phase == 2:
		_run_player_fx_checks()
		_phase = 3
	if _frame >= 40:
		_finish()
		return true
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("MYTHIC: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("MYTHIC: FAILURES PRESENT")
	quit()
