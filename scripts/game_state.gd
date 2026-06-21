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
	{ "id": "auger",   "name": "Wide Auger",      "unit": "dig reach",    "base": 14, "growth": 1.7, "max": 5, "per": 1.0 },
	{ "id": "scanner", "name": "Seismic Scanner", "unit": "ore pings",    "base": 12, "growth": 2.0, "max": 3, "per": 1.0 },
]

# Ship-repair meta track (GDD §7). The mid-game goal: smelt Alloy and spend it
# to repair the crashed ship. Ascending cost; payoff teaser shown when complete.
const SHIP_PARTS: Array = [
	{ "id": "hull",  "name": "Hull Breach Seal", "cost": 60,  "desc": "Patch the torn fuselage." },
	{ "id": "comms", "name": "Comms Array",      "cost": 90,  "desc": "Re-establish the uplink." },
	{ "id": "nav",   "name": "Nav Computer",     "cost": 130, "desc": "Restore guidance." },
	{ "id": "drive", "name": "Drive Core",       "cost": 220, "desc": "Recharge the main drive." },
]

# Telemetry beacon: dives can start at a previously-reached 250 m milestone.
const CHECKPOINT_STEP := 250.0

var alloy: int = 0
var best_depth: float = 0.0
var last_run: Dictionary = {}
var levels: Dictionary = {}   # upgrade id -> level (int)
var ship_repaired: Dictionary = {}   # ship part id -> bool
var selected_start_m: float = 0.0    # chosen launch depth (0 = Surface)
var seen_transmissions: Dictionary = {}  # Lore transmission id -> true (Phase 7)
var collected_logs: Dictionary = {}      # Lore data-log id -> true (Phase 7)
var escaped: bool = false                # completed the endgame at least once (Phase 9)

# Audio mixer levels (0..1 linear, per bus), surfaced in the menu settings panel
# and applied to the buses by the Audio autoload.
var volumes: Dictionary = {"Master": 0.9, "Music": 0.7, "SFX": 0.9, "UI": 0.8}


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


# --- Ship repair ---

func _part_def(id: String) -> Dictionary:
	for p in SHIP_PARTS:
		if p["id"] == id:
			return p
	return {}


func part_repaired(id: String) -> bool:
	return bool(ship_repaired.get(id, false))


func can_repair(id: String) -> bool:
	var p := _part_def(id)
	if p.is_empty() or part_repaired(id):
		return false
	return alloy >= int(p["cost"])


func repair(id: String) -> bool:
	if not can_repair(id):
		return false
	alloy -= int(_part_def(id)["cost"])
	ship_repaired[id] = true
	save_game()
	return true


## Number of ship parts repaired so far.
func repaired_count() -> int:
	var done := 0
	for p in SHIP_PARTS:
		if part_repaired(p["id"]):
			done += 1
	return done


## Fraction of ship parts repaired, 0..1.
func ship_progress() -> float:
	if SHIP_PARTS.is_empty():
		return 0.0
	return float(repaired_count()) / float(SHIP_PARTS.size())


func ship_complete() -> bool:
	for p in SHIP_PARTS:
		if not part_repaired(p["id"]):
			return false
	return true


# --- Telemetry beacon (launch-depth checkpoints) ---

## Reachable launch depths: always 0.0 (Surface), plus each CHECKPOINT_STEP
## milestone up to floor(best_depth/STEP)*STEP. Ascending, no duplicates.
func available_checkpoints() -> Array:
	var out: Array = [0.0]
	var count := int(floor(best_depth / CHECKPOINT_STEP))
	for i in range(1, count + 1):
		out.append(float(i) * CHECKPOINT_STEP)
	return out


# --- Lore: transmissions heard + data logs collected (Phase 7) ---

func transmission_seen(id: String) -> bool:
	return bool(seen_transmissions.get(id, false))


func mark_transmission(id: String) -> void:
	if not transmission_seen(id):
		seen_transmissions[id] = true
		save_game()


func log_collected(id: String) -> bool:
	return bool(collected_logs.get(id, false))


func collect_log(id: String) -> void:
	if not log_collected(id):
		collected_logs[id] = true
		save_game()


# --- Endgame (Phase 9) ---

## Transfer the rig's power to the capsule: permanently drain every rig upgrade
## (the Ultimate Sacrifice, GDD §7), mark the run escaped, and persist.
func sacrifice_rig() -> void:
	levels = {}
	escaped = true
	save_game()


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
		"ship_repaired": ship_repaired,
		"selected_start_m": selected_start_m,
		"seen_transmissions": seen_transmissions,
		"collected_logs": collected_logs,
		"escaped": escaped,
		"volumes": volumes,
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
	# Phase 6 fields — safe defaults for old saves that predate them.
	var sr: Variant = data.get("ship_repaired", {})
	ship_repaired = {}
	if typeof(sr) == TYPE_DICTIONARY:
		for k in sr:
			ship_repaired[k] = bool(sr[k])
	selected_start_m = float(data.get("selected_start_m", 0.0))
	# Phase 7 lore flags — safe defaults for older saves.
	seen_transmissions = {}
	var st: Variant = data.get("seen_transmissions", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st:
			seen_transmissions[k] = bool(st[k])
	collected_logs = {}
	var cl: Variant = data.get("collected_logs", {})
	if typeof(cl) == TYPE_DICTIONARY:
		for k in cl:
			collected_logs[k] = bool(cl[k])
	escaped = bool(data.get("escaped", false))
	# Audio levels — merge saved values over defaults so new buses survive old saves.
	var vol: Variant = data.get("volumes", {})
	if typeof(vol) == TYPE_DICTIONARY:
		for k in vol:
			volumes[k] = clampf(float(vol[k]), 0.0, 1.0)
