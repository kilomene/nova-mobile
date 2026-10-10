class_name StoreDefs
extends RefCounted
## NOVA store catalog — data-only definitions for the CODM-style store.
##
## Tabs: Featured, Lucky Draws, Weapon Skins, Bundles, Characters (locked hook
## for the deferred premium operators), Battle Pass (locked teaser), Buy NOVA Points.
##
## NOVA Points (NP) are the premium currency, our COD Points equivalent:
## bought with REAL money (via Flutterwave) and spent on mythic weapon skins
## and bundles. Guns themselves stay free gameplay items — NP buys SKINS.
##
## DISTRIBUTION NOTE (flag for Zenas): Google Play's policy requires Google
## Play Billing for digital goods sold inside apps distributed via the Play
## Store. Flutterwave fits a direct-download APK (own website / sideload)
## or a web store. This is a distribution decision Zenas must make.

const TABS := [
	{"id": "featured", "name": "FEATURED", "locked": false},
	{"id": "draws", "name": "LUCKY DRAWS", "locked": false},
	{"id": "skins", "name": "WEAPON SKINS", "locked": false},
	{"id": "bundles", "name": "BUNDLES", "locked": false},
	{"id": "characters", "name": "CHARACTERS", "locked": true,
		"lock_note": "PREMIUM OPERATORS — COMING SOON"},
	{"id": "pass", "name": "BATTLE PASS", "locked": true,
		"lock_note": "SEASON 1 BATTLE PASS — COMING SOON"},
	{"id": "np", "name": "BUY NOVA POINTS", "locked": false},
]

## NP packs. Prices in NGN + USD. Bonus packs give more NP per naira.
## Real-money purchase goes through Payments.purchase_np_pack (Flutterwave).
const NP_PACKS := [
	{"id": "np_100", "np": 100, "ngn": 1500, "usd": 1.0, "bonus": "",
		"name": "Handful of Points"},
	{"id": "np_500", "np": 500, "ngn": 6500, "usd": 4.5, "bonus": "+25 BONUS",
		"name": "Stack of Points"},
	{"id": "np_1000", "np": 1100, "ngn": 12000, "usd": 8.0, "bonus": "+100 BONUS",
		"name": "Pile of Points"},
	{"id": "np_2500", "np": 2900, "ngn": 27500, "usd": 18.0, "bonus": "+400 BONUS",
		"name": "Vault of Points"},
	{"id": "np_5000", "np": 6200, "ngn": 50000, "usd": 32.0, "bonus": "+1200 BONUS",
		"name": "Fortune of Points"},
]

## Direct-buy mythic skins (sample of the 411 catalog; one per gun, mixed
## themes). "skin_idx" is the 1-based index into MythicSkins.skins_for(gun).
const MYTHIC_PRICE := 950
const SKIN_OFFERS := [
	{"gun": "m5", "skin_idx": 1}, {"gun": "kv47", "skin_idx": 2},
	{"gun": "mp9", "skin_idx": 1}, {"gun": "dg12", "skin_idx": 3},
	{"gun": "mg60", "skin_idx": 2}, {"gun": "lw9", "skin_idx": 1},
	{"gun": "mk14", "skin_idx": 3}, {"gun": "sg9", "skin_idx": 2},
	{"gun": "p9", "skin_idx": 1}, {"gun": "knife", "skin_idx": 2},
	{"gun": "rp7", "skin_idx": 1}, {"gun": "kn44", "skin_idx": 3},
	{"gun": "lk24", "skin_idx": 1}, {"gun": "vsk9", "skin_idx": 2},
	{"gun": "k10", "skin_idx": 3}, {"gun": "p45", "skin_idx": 1},
	{"gun": "bx200", "skin_idx": 2}, {"gun": "sr8", "skin_idx": 3},
	{"gun": "sr4", "skin_idx": 1}, {"gun": "sa9", "skin_idx": 2},
	{"gun": "mp50", "skin_idx": 3}, {"gun": "katana", "skin_idx": 1},
	{"gun": "rl4", "skin_idx": 2}, {"gun": "br9", "skin_idx": 1},
]

## Bundles: mythic skin + operator card + calling card + avatar frame.
const BUNDLES := [
	{"id": "bundle_dragonfire", "name": "DRAGONFIRE ARSENAL",
		"gun": "kv47", "skin_idx": 1, "price": 1500,
		"desc": "Mythic KV-47 skin + Ember operator card + Molten calling card + Flame avatar frame"},
	{"id": "bundle_glacier", "name": "GLACIER PROTOCOL",
		"gun": "lw9", "skin_idx": 1, "price": 1500,
		"desc": "Mythic LW-9 skin + Frost operator card + Icefield calling card + Crystal avatar frame"},
	{"id": "bundle_necrovoid", "name": "NECROVOID UPRISING",
		"gun": "m5", "skin_idx": 2, "price": 1800,
		"desc": "Mythic M5 skin + Void operator card + Abyss calling card + Rift avatar frame + animated banner"},
]

## Lucky draws: 10 slots, escalating spin costs (CODM rule: owned items are
## removed from the pool; the 10th spin guarantees the top prize).
## "items": 10 entries — kind "mythic" (gun+skin_idx), "epic" (named loot
## flair), "rare"/"common" (named flair). Only mythic grants are gameplay
## items; flair items are cosmetic inventory entries.
const DRAW_SPIN_COSTS := [30, 60, 110, 180, 270, 380, 510, 660, 830, 1020]
const DRAW_ODDS := {"mythic": 0.03, "epic": 0.12, "rare": 0.30, "common": 0.55}
const DRAWS := [
	{"id": "draw_dragonfire", "name": "DRAGONFIRE DRAW",
		"ends_in_days": 6,
		"items": [
			{"kind": "mythic", "gun": "kv47", "skin_idx": 1},
			{"kind": "epic", "label": "Ember Calling Card"},
			{"kind": "epic", "label": "Molten Avatar Frame"},
			{"kind": "rare", "label": "Dragonfire Weapon Charm"},
			{"kind": "rare", "label": "Ember Operator Card"},
			{"kind": "common", "label": "500 Cash Bundle (BR)"},
			{"kind": "common", "label": "Armor Shard Pack"},
			{"kind": "common", "label": "Smoke Grenade Skin: Ember"},
			{"kind": "common", "label": "Frag Grenade Skin: Magma"},
			{"kind": "common", "label": "Parachute Skin: Firestorm"},
		]},
	{"id": "draw_glacier", "name": "GLACIER DRAW",
		"ends_in_days": 13,
		"items": [
			{"kind": "mythic", "gun": "lw9", "skin_idx": 1},
			{"kind": "epic", "label": "Icefield Calling Card"},
			{"kind": "epic", "label": "Crystal Avatar Frame"},
			{"kind": "rare", "label": "Glacier Weapon Charm"},
			{"kind": "rare", "label": "Frost Operator Card"},
			{"kind": "common", "label": "500 Cash Bundle (BR)"},
			{"kind": "common", "label": "Armor Shard Pack"},
			{"kind": "common", "label": "Smoke Grenade Skin: Blizzard"},
			{"kind": "common", "label": "Frag Grenade Skin: Icicle"},
			{"kind": "common", "label": "Parachute Skin: Whiteout"},
		]},
	{"id": "draw_necrovoid", "name": "NECROVOID DRAW",
		"ends_in_days": 20,
		"items": [
			{"kind": "mythic", "gun": "m5", "skin_idx": 2},
			{"kind": "epic", "label": "Abyss Calling Card"},
			{"kind": "epic", "label": "Rift Avatar Frame"},
			{"kind": "rare", "label": "Necrovoid Weapon Charm"},
			{"kind": "rare", "label": "Void Operator Card"},
			{"kind": "common", "label": "500 Cash Bundle (BR)"},
			{"kind": "common", "label": "Armor Shard Pack"},
			{"kind": "common", "label": "Smoke Grenade Skin: Voidmist"},
			{"kind": "common", "label": "Frag Grenade Skin: Singularity"},
			{"kind": "common", "label": "Parachute Skin: Eventide"},
		]},
]


static func np_pack_by_id(pid: String) -> Dictionary:
	for p in NP_PACKS:
		if str(p["id"]) == pid:
			return p
	return {}


static func draw_by_id(did: String) -> Dictionary:
	for d in DRAWS:
		if str(d["id"]) == did:
			return d
	return {}


static func bundle_by_id(bid: String) -> Dictionary:
	for b in BUNDLES:
		if str(b["id"]) == bid:
			return b
	return {}


static func draw_top_prize(did: String) -> Dictionary:
	var d := draw_by_id(did)
	if d.is_empty():
		return {}
	for it in d["items"]:
		if str(it["kind"]) == "mythic":
			return it
	return {}


## Full-draw cost (all 10 spins) — for display ("GUARANTEED MYTHIC FOR X NP").
static func draw_full_cost() -> int:
	var t := 0
	for c in DRAW_SPIN_COSTS:
		t += int(c)
	return t


## Display label for a draw/bundle item. Mythic labels come from the real
## skin catalog so they can never go stale.
static func item_label(item: Dictionary) -> String:
	if str(item.get("kind", "")) == "mythic":
		var nm := MythicSkins.skin_display_name(str(item["gun"]), int(item["skin_idx"]))
		if nm != "":
			return "MYTHIC: " + nm
		return "MYTHIC SKIN"
	return str(item.get("label", "ITEM"))
