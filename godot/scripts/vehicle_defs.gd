class_name VehicleDefs
## NOVA Mobile: drivable vehicle roster — specs per vehicle.
## Locomotion: "ground" | "water" | "air" (helicopter VTOL) | "hover" | "plane" (runway takeoff).
## Weapon: "none" | "cannon" | "minigun" | "bombs".

const SPECS := {
	"sedan": {
		"name": "NV-4 Sedan", "loco": "ground", "weapon": "none",
		"top_speed": 24.0, "accel": 16.0, "brake": 26.0, "turn_rate": 1.7,
		"hp": 120, "ram_damage": 25, "desc": "Fast all-rounder",
		"fuel_cap": 60.0, "fuel_rate": 0.60,
	},
	"bike": {
		"name": "KV-2 Bike", "loco": "ground", "weapon": "none",
		"top_speed": 31.0, "accel": 22.0, "brake": 30.0, "turn_rate": 2.4,
		"hp": 60, "ram_damage": 15, "lean": true, "desc": "Fast and fragile",
		"fuel_cap": 40.0, "fuel_rate": 0.35,
	},
	"truck": {
		"name": "HT-8 Hauler", "loco": "ground", "weapon": "none",
		"top_speed": 17.0, "accel": 9.0, "brake": 16.0, "turn_rate": 1.1,
		"hp": 260, "ram_damage": 60, "ram_break": true, "desc": "Heavy, rams through",
		"fuel_cap": 90.0, "fuel_rate": 1.20,
	},
	"tank": {
		"name": "T-90 'Bulwark'", "loco": "ground", "weapon": "cannon",
		"top_speed": 11.0, "accel": 7.0, "brake": 12.0, "turn_rate": 1.2,
		"hp": 500, "ram_damage": 80, "ram_break": true,
		"cannon_damage": 110, "cannon_radius": 6.5, "cannon_cd": 3.0,
		"desc": "Armored cannon platform",
		"fuel_cap": 100.0, "fuel_rate": 1.60,
	},
	"heli": {
		"name": "AH-6 'Kestrel'", "loco": "air", "weapon": "minigun",
		"top_speed": 26.0, "accel": 14.0, "brake": 18.0, "turn_rate": 1.8,
		"hp": 220, "ram_damage": 40,
		"minigun_damage": 14, "minigun_rpm": 900.0,
		"desc": "VTOL gunship",
		"fuel_cap": 80.0, "fuel_rate": 1.80,
	},
	"boat": {
		"name": "PB-12 Patrol Boat", "loco": "water", "weapon": "none",
		"top_speed": 20.0, "accel": 10.0, "brake": 12.0, "turn_rate": 1.3,
		"hp": 150, "ram_damage": 20, "desc": "Water transport",
		"fuel_cap": 70.0, "fuel_rate": 0.90,
	},
	"hoverbike": {
		"name": "HX-1 Hoverbike", "loco": "hover", "weapon": "none",
		"top_speed": 33.0, "accel": 24.0, "brake": 30.0, "turn_rate": 2.6,
		"hp": 80, "ram_damage": 15, "hover_h": 1.1, "desc": "Futuristic floater",
		"fuel_cap": 50.0, "fuel_rate": 0.70,
	},
	"skateboard": {
		"name": "Street Deck", "loco": "ground", "weapon": "none",
		"top_speed": 13.0, "accel": 18.0, "brake": 22.0, "turn_rate": 3.0,
		"hp": 40, "ram_damage": 5, "desc": "Fun and nimble",
		"fuel_cap": 0.0, "fuel_rate": 0.00,
	},
	"b2": {
		"name": "B-2 'Jaka' Stealth Bomber", "loco": "plane", "weapon": "bombs",
		"top_speed": 55.0, "accel": 12.0, "brake": 10.0, "turn_rate": 0.9,
		"hp": 350, "ram_damage": 100,
		"bomb_damage": 160, "bomb_radius": 12.0, "bomb_count": 6, "bomb_cd": 1.2,
		"takeoff_speed": 30.0, "desc": "Signature strike platform",
		"fuel_cap": 0.0, "fuel_rate": 0.00,
	},
	"suv": {
		"name": "GX-7 SUV", "loco": "ground", "weapon": "none",
		"top_speed": 21.0, "accel": 12.0, "brake": 20.0, "turn_rate": 1.4,
		"hp": 200, "ram_damage": 35, "desc": "Big and tough",
		"fuel_cap": 70.0, "fuel_rate": 0.80,
	},
	"pickup": {
		"name": "PX-4 Pickup", "loco": "ground", "weapon": "none",
		"top_speed": 22.0, "accel": 13.0, "brake": 20.0, "turn_rate": 1.4,
		"hp": 180, "ram_damage": 45, "ram_break": true, "desc": "Workhorse",
		"fuel_cap": 70.0, "fuel_rate": 0.85,
	},
	"sportscar": {
		"name": "VX-R Sport", "loco": "ground", "weapon": "none",
		"top_speed": 37.0, "accel": 26.0, "brake": 34.0, "turn_rate": 2.2,
		"hp": 90, "ram_damage": 20, "nitro_mult": 1.7, "desc": "Blinding speed",
		"fuel_cap": 55.0, "fuel_rate": 1.00,
	},
	"atv": {
		"name": "QD-4 Quad", "loco": "ground", "weapon": "none",
		"top_speed": 24.0, "accel": 18.0, "brake": 24.0, "turn_rate": 2.6,
		"hp": 70, "ram_damage": 15, "lean": true, "desc": "Go-anywhere quad",
		"fuel_cap": 45.0, "fuel_rate": 0.45,
	},
	"armored_suv": {
		"name": "AX-9 Armored", "loco": "ground", "weapon": "none",
		"top_speed": 19.0, "accel": 10.0, "brake": 18.0, "turn_rate": 1.2,
		"hp": 340, "ram_damage": 55, "ram_break": true, "desc": "Rolling fortress",
		"fuel_cap": 80.0, "fuel_rate": 1.10,
	},
	"jeep": {
		"name": "WJ-3 Jeep", "loco": "ground", "weapon": "none",
		"top_speed": 20.0, "accel": 14.0, "brake": 20.0, "turn_rate": 1.8,
		"hp": 110, "ram_damage": 25, "desc": "Open-top classic",
		"fuel_cap": 60.0, "fuel_rate": 0.65,
	},
}

## Vehicle spawn table: region name -> list of {type, poi-name-fragment}.
## Matched against POI names in main.gd; falls back to region POIs.
const WORLD_SPAWNS := [
	{"region": "LEKKI", "type": "sedan", "poi": "Admiralty"},
	{"region": "LEKKI", "type": "bike", "poi": "Bridge View"},
	{"region": "COMPUTER VILLAGE", "type": "sedan", "poi": "Tech Plaza"},
	{"region": "BANANA ISLAND", "type": "sedan", "poi": "Palm Boulevard"},
	{"region": "BANANA ISLAND", "type": "boat", "poi": "Marina"},
	{"region": "MAKOKO", "type": "boat", "poi": "Main Dock"},
	{"region": "MAKOKO", "type": "boat", "poi": "Canoe Yard"},
	{"region": "SHIP PORT", "type": "truck", "poi": "Container Yard"},
	{"region": "SHIP PORT", "type": "boat", "poi": "The Ship"},
	{"region": "BARRACKS", "type": "tank", "poi": "Parade Ground"},
	{"region": "BARRACKS", "type": "truck", "poi": "Gatehouse"},
	{"region": "AIRPORT", "type": "heli", "poi": "Helipad"},
	{"region": "AIRBASE", "type": "b2", "poi": "Bomber Row"},
	{"region": "AIRBASE", "type": "heli", "poi": "Control Tower"},
	{"region": "VALLEY", "type": "hoverbike", "poi": "Valley Camp"},
	{"region": "VALLEY", "type": "skateboard", "poi": "Hilltop"},
	{"region": "DOWNTOWN", "type": "sedan", "poi": "Nova Tower"},
	{"region": "DOWNTOWN", "type": "heli", "poi": "Sky Villa"},
	{"region": "DAM", "type": "boat", "poi": "Reservoir"},
	{"region": "STADIUM", "type": "skateboard", "poi": "Stadium"},
	{"region": "TRAIN STATION", "type": "sedan", "poi": "Main Hall"},
	{"region": "LAGOON BRIDGE", "type": "sedan", "poi": "Toll Plaza"},
	{"region": "LEKKI", "type": "suv", "poi": "Estate Gate"},
	{"region": "LEKKI", "type": "sportscar", "poi": "Admiralty Mall"},
	{"region": "BANANA ISLAND", "type": "suv", "poi": "Sky Villa"},
	{"region": "VALLEY", "type": "atv", "poi": "Ruined Compound"},
	{"region": "VALLEY", "type": "jeep", "poi": "River Crossing"},
	{"region": "BARRACKS", "type": "armored_suv", "poi": "Armory"},
	{"region": "SHIP PORT", "type": "pickup", "poi": "Warehouses"},
	{"region": "DOWNTOWN", "type": "sportscar", "poi": "Nova Tower"},
	{"region": "COMPUTER VILLAGE", "type": "pickup", "poi": "Gadget Mall"},
]

## Single-map vehicle spawns: map idx -> list of {type, poi fragment}.
const MAP_SPAWNS := {
	8: [{"type": "heli", "poi": "Helipad"}],       # airport
	9: [{"type": "truck", "poi": "Container"}],    # ship port
	10: [{"type": "b2", "poi": "Bomber"}, {"type": "tank", "poi": "Parade"}],  # airbase
	5: [{"type": "tank", "poi": "Parade"}],        # barracks
	3: [{"type": "boat", "poi": "Marina"}],        # banana island
	0: [{"type": "boat", "poi": "Dock"}],          # makoko
	7: [{"type": "sedan", "poi": "Toll"}],         # lagoon bridge
}


static func spec(vid: String) -> Dictionary:
	return SPECS.get(vid, SPECS["sedan"])


static func ids() -> Array:
	return SPECS.keys()
