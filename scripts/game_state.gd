extends Node
## Red Descent — GameState (autoload singleton)
##
## Meta-progression that survives across runs and app launches: banked Alloy
## (smelted from ore), the last-run record, and permanent rig UPGRADE levels
## (GDD §6). Saved to user://.

const SAVE_PATH := "user://red_descent.save"
const ALLOY_PER_ORE := 1

# Permanent upgrades. cost(level) = round(base * growth^level); each level adds
# `per` to the relevant rig stat. Applied in player.gd._apply_upgrades().
const UPGRADES: Array = [
	{ "id": "battery", "name": "Battery Cells",   "unit": "max energy",   "base": 6,  "growth": 1.6, "max": 6, "per": 35.0 },
	{ "id": "drill",   "name": "Drill Servo",     "unit": "drill power",  "base": 8,  "growth": 1.7, "max": 6, "per": 0.30 },
	{ "id": "cooling", "name": "Coolant Vanes",   "unit": "heat venting", "base": 6,  "growth": 1.6, "max": 5, "per": 5.0 },
	{ "id": "hull",    "name": "Hull Plating",    "unit": "max hull",     "base": 8,  "growth": 1.7, "max": 5, "per": 25.0 },
	{ "id": "auger",   "name": "Wide Auger",      "unit": "dig width",    "base": 18, "growth": 2.5, "max": 2, "per": 1.0 },
	{ "id": "scanner", "name": "Seismic Scanner", "unit": "ore pings",    "base": 12, "growth": 2.0, "max": 3, "per": 1.0 },
]

var alloy: int = 0
var best_depth: float = 0.0
var last_run: Dictionary = {}
var levels: Dictionary = {}   # upgrade id -> level (int)


func _ready() -> void:
	load_game()


# --- Upgrades ---

func level(id: String) -> int:
	return int(levels.get(id, 0))


func _def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}


## Cost of the next level, or -1 if maxed.
func upgrade_cost(id: String) -> int:
	var u := _def(id)
	if u.is_empty():
		return -1
	var lv := level(id)
	if lv >= int(u["max"]):
		return -1
	return int(round(float(u["base"]) * pow(float(u["growth"]), lv)))


func is_maxed(id: String) -> bool:
	var u := _def(id)
	return not u.is_empty() and level(id) >= int(u["max"])


func can_buy(id: String) -> bool:
	var c := upgrade_cost(id)
	return c >= 0 and alloy >= c


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	alloy -= upgrade_cost(id)
	levels[id] = level(id) + 1
	save_game()
	return true


## Total stat bonus from an upgrade (level * per-level effect).
func effect(id: String) -> float:
	var u := _def(id)
	if u.is_empty():
		return 0.0
	return float(level(id)) * float(u["per"])


# --- Runs ---

func record_run(reason: String, ore: int, depth: float, banked: bool) -> void:
	last_run = { "reason": reason, "ore": ore, "depth": depth, "banked": banked }
	if banked:
		alloy += ore * ALLOY_PER_ORE
	best_depth = maxf(best_depth, depth)
	save_game()


# --- Persistence ---

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"alloy": alloy,
		"best_depth": best_depth,
		"levels": levels,
	}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	alloy = int(data.get("alloy", 0))
	best_depth = float(data.get("best_depth", 0.0))
	var lv: Variant = data.get("levels", {})
	levels = {}
	if typeof(lv) == TYPE_DICTIONARY:
		for k in lv:
			levels[k] = int(lv[k])
