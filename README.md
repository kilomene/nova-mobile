# NOVA Mobile

**NOVA Mobile** — a native 3D battle-royale game for Android, built with **Godot Engine 4.3**. Set in Lagos, Nigeria. CODM-grade systems, NOVA-original advancements.

## Get the APK

Nobody builds the APK by hand. **GitHub Actions builds it**: every push to `main` that touches `godot/` produces a signed, installable debug APK. Download it from the **Actions** tab → latest run → **Artifacts** → `nova-mobile-debug-apk`.

## Layout

- `godot/` — the Godot 4.3 project: scenes, scripts, guns, mythic skins, vehicles, store, export presets (`com.novamobile.game`, landscape)
- `server/` — NOVA payments backend: tiny Flutterwave relay (holds the secret key, creates checkout links, verifies transactions). The game never ships the secret key.
- `3d-shooter-game.html` — the original web prototype, kept as design history only

## The game

- One connected BR world (NOVA WORLD): 14 Lagos-inspired regions, 100 combatants, 25 squads
- 137 original NOVA guns + 411 mythic skins with kill evolution
- 30 original BR classes, CODM-exact touch controls, full vehicle fleet (incl. pilotable B2), fuel + filling stations (a NOVA original), buy stations, airdrops, NOVA Points store
- Battle royale only. Multiplayer modes and true online play are later phases.

## Build locally (not the delivery path)

```bash
# Godot 4.3 + export templates required
Godot_v4.3-stable_linux.x86_64 --headless --path godot --export-debug "Android" out.apk
```
