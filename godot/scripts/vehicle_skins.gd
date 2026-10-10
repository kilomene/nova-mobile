class_name VehicleSkins
## NOVA Mobile: vehicle paint jobs — multiple skins per vehicle.
## Applied to the "paint" meshes from VehicleModels.build().

# vid -> [{name, paint: Color, metallic, roughness}]
const SKINS := {
	"sedan": [
		{"name": "Midnight", "paint": Color(0.05, 0.06, 0.10), "metallic": 0.7, "roughness": 0.35},
		{"name": "Crimson", "paint": Color(0.55, 0.04, 0.06), "metallic": 0.6, "roughness": 0.3},
		{"name": "Arctic", "paint": Color(0.82, 0.85, 0.88), "metallic": 0.4, "roughness": 0.4},
		{"name": "Desert Camo", "paint": Color(0.55, 0.48, 0.32), "metallic": 0.1, "roughness": 0.8},
	],
	"suv": [
		{"name": "Onyx", "paint": Color(0.04, 0.04, 0.05), "metallic": 0.7, "roughness": 0.35},
		{"name": "Forest", "paint": Color(0.08, 0.22, 0.12), "metallic": 0.5, "roughness": 0.45},
		{"name": "Sandstorm", "paint": Color(0.72, 0.62, 0.42), "metallic": 0.2, "roughness": 0.7},
		{"name": "Chrome", "paint": Color(0.85, 0.87, 0.9), "metallic": 1.0, "roughness": 0.08},
	],
	"pickup": [
		{"name": "Workhorse Red", "paint": Color(0.5, 0.08, 0.05), "metallic": 0.4, "roughness": 0.5},
		{"name": "Navy", "paint": Color(0.05, 0.12, 0.28), "metallic": 0.5, "roughness": 0.45},
		{"name": "Mud Camo", "paint": Color(0.35, 0.3, 0.2), "metallic": 0.1, "roughness": 0.85},
		{"name": "Sunset", "paint": Color(0.75, 0.35, 0.08), "metallic": 0.6, "roughness": 0.3},
	],
	"sportscar": [
		{"name": "Rosso", "paint": Color(0.65, 0.03, 0.04), "metallic": 0.8, "roughness": 0.2},
		{"name": "Volt", "paint": Color(0.55, 0.8, 0.05), "metallic": 0.7, "roughness": 0.25},
		{"name": "Stealth", "paint": Color(0.03, 0.03, 0.04), "metallic": 0.9, "roughness": 0.15},
		{"name": "Azure", "paint": Color(0.05, 0.25, 0.65), "metallic": 0.75, "roughness": 0.22},
	],
	"atv": [
		{"name": "Olive", "paint": Color(0.25, 0.28, 0.15), "metallic": 0.2, "roughness": 0.7},
		{"name": "Redline", "paint": Color(0.6, 0.08, 0.06), "metallic": 0.3, "roughness": 0.55},
		{"name": "Cobalt", "paint": Color(0.06, 0.2, 0.5), "metallic": 0.3, "roughness": 0.55},
	],
	"armored_suv": [
		{"name": "Matte Black", "paint": Color(0.03, 0.03, 0.035), "metallic": 0.4, "roughness": 0.7},
		{"name": "Gunmetal", "paint": Color(0.18, 0.19, 0.21), "metallic": 0.7, "roughness": 0.45},
		{"name": "Desert Tan", "paint": Color(0.6, 0.52, 0.36), "metallic": 0.2, "roughness": 0.75},
	],
	"jeep": [
		{"name": "Army Green", "paint": Color(0.16, 0.22, 0.12), "metallic": 0.2, "roughness": 0.7},
		{"name": "Rescue Orange", "paint": Color(0.7, 0.3, 0.05), "metallic": 0.4, "roughness": 0.5},
		{"name": "Ocean", "paint": Color(0.05, 0.25, 0.45), "metallic": 0.4, "roughness": 0.5},
	],
	"bike": [
		{"name": "Ninja Black", "paint": Color(0.03, 0.03, 0.04), "metallic": 0.7, "roughness": 0.3},
		{"name": "Flame", "paint": Color(0.6, 0.1, 0.05), "metallic": 0.6, "roughness": 0.35},
		{"name": "Ice", "paint": Color(0.7, 0.8, 0.88), "metallic": 0.5, "roughness": 0.4},
	],
	"truck": [
		{"name": "Fleet White", "paint": Color(0.8, 0.8, 0.82), "metallic": 0.2, "roughness": 0.6},
		{"name": "Logistics Blue", "paint": Color(0.06, 0.18, 0.45), "metallic": 0.3, "roughness": 0.55},
		{"name": "Hazard", "paint": Color(0.65, 0.45, 0.05), "metallic": 0.3, "roughness": 0.55},
	],
	"tank": [
		{"name": "Woodland", "paint": Color(0.15, 0.2, 0.12), "metallic": 0.3, "roughness": 0.75},
		{"name": "Desert", "paint": Color(0.58, 0.5, 0.34), "metallic": 0.3, "roughness": 0.75},
		{"name": "Arctic", "paint": Color(0.75, 0.78, 0.8), "metallic": 0.3, "roughness": 0.75},
	],
	"heli": [
		{"name": "Gunship Grey", "paint": Color(0.2, 0.21, 0.23), "metallic": 0.5, "roughness": 0.5},
		{"name": "Rescue", "paint": Color(0.65, 0.12, 0.08), "metallic": 0.4, "roughness": 0.5},
		{"name": "Stealth", "paint": Color(0.04, 0.04, 0.05), "metallic": 0.7, "roughness": 0.35},
	],
	"boat": [
		{"name": "Coast Guard", "paint": Color(0.75, 0.12, 0.08), "metallic": 0.3, "roughness": 0.5},
		{"name": "Navy", "paint": Color(0.1, 0.16, 0.3), "metallic": 0.3, "roughness": 0.5},
		{"name": "Pearl", "paint": Color(0.85, 0.86, 0.88), "metallic": 0.4, "roughness": 0.45},
	],
	"hoverbike": [
		{"name": "Neon", "paint": Color(0.05, 0.08, 0.16), "metallic": 0.8, "roughness": 0.25},
		{"name": "Ghost", "paint": Color(0.8, 0.82, 0.85), "metallic": 0.6, "roughness": 0.35},
		{"name": "Viper", "paint": Color(0.1, 0.35, 0.08), "metallic": 0.7, "roughness": 0.3},
	],
	"skateboard": [
		{"name": "Street", "paint": Color(0.1, 0.1, 0.12), "metallic": 0.2, "roughness": 0.7},
		{"name": "Flame", "paint": Color(0.55, 0.12, 0.05), "metallic": 0.2, "roughness": 0.7},
		{"name": "Wave", "paint": Color(0.08, 0.3, 0.5), "metallic": 0.2, "roughness": 0.7},
	],
	"b2": [
		{"name": "Spectre", "paint": Color(0.03, 0.03, 0.04), "metallic": 0.6, "roughness": 0.5},
		{"name": "Ghost Grey", "paint": Color(0.25, 0.26, 0.28), "metallic": 0.5, "roughness": 0.55},
		{"name": "Night Ops", "paint": Color(0.02, 0.03, 0.06), "metallic": 0.8, "roughness": 0.3},
	],
}


static func count(vid: String) -> int:
	return (SKINS.get(vid, []) as Array).size()


static func skin(vid: String, idx: int) -> Dictionary:
	var arr: Array = SKINS.get(vid, [])
	if arr.is_empty():
		return {"name": "Standard", "paint": Color(0.2, 0.2, 0.22), "metallic": 0.5, "roughness": 0.5}
	return arr[clampi(idx, 0, arr.size() - 1)]


static func random_idx(vid: String, rng: RandomNumberGenerator) -> int:
	var c := count(vid)
	return rng.randi() % maxi(c, 1)


## Apply a paint job to a built model's "paint" meshes.
static func apply(parts: Dictionary, vid: String, idx: int) -> void:
	var sk := skin(vid, idx)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = sk["paint"]
	mat.metallic = float(sk["metallic"])
	mat.roughness = float(sk["roughness"])
	for m in parts.get("paint", []):
		(m as MeshInstance3D).set_surface_override_material(0, mat)
