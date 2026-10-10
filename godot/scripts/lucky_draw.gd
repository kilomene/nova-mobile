class_name LuckyDraw
extends RefCounted
## Lucky Draw engine — CODM's draw rules:
##  - 10 slots, each spin costs an escalating amount of NP
##    (30, 60, 110, 180, 270, 380, 510, 660, 830, 1020)
##  - Owned items are REMOVED from the pool (never win duplicates)
##  - The 10th spin GUARANTEES the top (mythic) prize
##  - Otherwise each spin draws from the remaining pool weighted by odds
##    (mythic 3% / epic 12% / rare 30% / common 55%)
##  - Draw state (spins used, won items) persists in the wallet ledger.


## Cost of the next spin given how many spins are already used.
static func spin_cost(spins_used: int) -> int:
	if spins_used < 0 or spins_used >= StoreDefs.DRAW_SPIN_COSTS.size():
		return -1
	return int(StoreDefs.DRAW_SPIN_COSTS[spins_used])


## Remaining items in the pool after removing already-won ones.
## won: Array of item indices already drawn.
static func pool(draw: Dictionary, won: Array) -> Array:
	var out: Array = []
	var items: Array = draw["items"]
	for i in range(items.size()):
		if not won.has(i):
			out.append({"idx": i, "item": items[i]})
	return out


## Perform one spin. rng is a RandomNumberContainer (seeded in tests).
## Returns {"ok": true, "won_idx": i, "item": {...}, "guaranteed": bool}
## or {"ok": false, "reason": "..."}.
static func spin(draw_id: String, won: Array, rng: RandomNumberGenerator) -> Dictionary:
	var draw := StoreDefs.draw_by_id(draw_id)
	if draw.is_empty():
		return {"ok": false, "reason": "unknown draw"}
	var cost := spin_cost(won.size())
	if cost < 0:
		return {"ok": false, "reason": "draw complete"}
	var remaining := pool(draw, won)
	if remaining.is_empty():
		return {"ok": false, "reason": "pool empty"}
	if not StoreWallet.spend_np(cost, "draw:%s spin %d" % [draw_id, won.size() + 1]):
		return {"ok": false, "reason": "insufficient NP"}
	# Final spin: guarantee the mythic if it is still in the pool.
	var guaranteed := false
	var pick: Dictionary = {}
	if remaining.size() == 1:
		pick = remaining[0]
		guaranteed = str(pick["item"]["kind"]) == "mythic"
	else:
		var roll := rng.randf()
		var acc := 0.0
		var weights: Array = []
		for e in remaining:
			var k := str(e["item"]["kind"])
			weights.append(float(StoreDefs.DRAW_ODDS.get(k, 0.0)))
		var total := 0.0
		for w in weights:
			total += w
		if total <= 0.0:
			pick = remaining[rng.randi_range(0, remaining.size() - 1)]
		else:
			for i in range(remaining.size()):
				acc += float(weights[i]) / total
				if roll <= acc:
					pick = remaining[i]
					break
			if pick.is_empty():
				pick = remaining[remaining.size() - 1]
		# CODM pity: if the mythic is the ONLY item left next spin, force it
		# on the final spin — handled by the remaining.size()==1 branch.
	_grant(draw_id, pick["item"])
	var ni := int(pick["idx"])
	won.append(ni)
	return {"ok": true, "won_idx": ni, "item": pick["item"], "guaranteed": guaranteed}


static func _grant(draw_id: String, item: Dictionary) -> void:
	var k := str(item["kind"])
	if k == "mythic":
		StoreWallet.grant_skin(str(item["gun"]), int(item["skin_idx"]), "draw:" + draw_id)
	else:
		StoreWallet.grant_flair(StoreDefs.item_label(item), "draw:" + draw_id)


## Simulated full draw (all 10 spins) for odds verification in tests.
## Returns the mythic prize won (should ALWAYS be present — guaranteed).
static func simulate_full_draw(draw_id: String, seed: int) -> Dictionary:
	var draw := StoreDefs.draw_by_id(draw_id)
	var won: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mythic_won: Dictionary = {}
	for _i in range(10):
		var r := spin(draw_id, won, rng)
		if not bool(r.get("ok", false)):
			return {"mythic": mythic_won, "error": str(r.get("reason", "?"))}
		if str(r["item"]["kind"]) == "mythic":
			mythic_won = r["item"]
	return {"mythic": mythic_won, "spins": won.size()}
