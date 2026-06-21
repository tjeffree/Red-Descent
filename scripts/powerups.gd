extends Node
## Red Descent — Powerups (autoload singleton "Powerups")
##
## Short-term, single-dive boons. Unlike the permanent GameState UPGRADES (bought
## with Alloy), these are SALVAGE: caches of strange tech buried in the strata,
## far more advanced than anything the colony — or Earth — ever fielded. Nobody
## knows who left them. The rig grabs one by digging within reach (exactly like a
## buried data-log), the effect fires INSTANTLY, and it lasts only the current
## dive. Some are timed (too strong to leave running); some run the whole dive;
## one arms a single save. They STACK — finding two live at once is rare but
## legal, and gloriously overpowered.
##
## This module is STATELESS content + helpers. The live effects live on the rig
## (player.gd `_boosts`); placement + buried markers live in world.gd; the pickup
## popup and the active-boost readout live in hud.gd.
##
## Each entry:
##   id        unique key — matched verbatim by player.gd's effect logic
##   name      HUD display name
##   duration  >0 timed seconds · -1.0 rest-of-dive · 0.0 instant one-shot
##   min_depth earliest depth (m) it can be buried at (gates deep-only salvage)
##   color     HUD chip / popup accent
##   flash     short pickup banner line (the "story" version)
##   desc      flavour — what it does, with a nod to its impossible origin
##   effect    plain mechanical one-liner; the pickup popup shows it (with the
##             duration auto-appended) in brackets beneath the story line

const REST_OF_DIVE := -1.0
const INSTANT := 0.0

const POWERUPS: Array = [
	# --- Drill / mining ---------------------------------------------------------
	{ "id": "overclock", "name": "OVERCLOCK CORE", "duration": 12.0, "min_depth": 0.0,
	  "color": Color(1.0, 0.6, 0.2),
	  "flash": "OVERCLOCK CORE — the drill screams",
	  "desc": "A power cell that shouldn't fit in this housing. Drill output triples for a few brutal seconds.",
	  "effect": "Drill power ×3" },
	{ "id": "diamond_bit", "name": "ADAMANT BIT", "duration": 6.0, "min_depth": 0.0,
	  "color": Color(0.9, 0.95, 1.0),
	  "flash": "ADAMANT BIT — nothing holds",
	  "desc": "A drill head of some impossible alloy. Briefly, every block shatters in a single pass — basalt like dirt.",
	  "effect": "Any block breaks in one pass" },
	{ "id": "auger_surge", "name": "AUGER SURGE", "duration": 12.0, "min_depth": 0.0,
	  "color": Color(1.0, 0.7, 0.3),
	  "flash": "AUGER SURGE — the bore widens",
	  "desc": "Field coils that splay the dig wide and deep. Carve tunnels in seconds — mind the ceilings.",
	  "effect": "Dig reach greatly widened" },
	{ "id": "magnet", "name": "ORE MAGNET", "duration": REST_OF_DIVE, "min_depth": 0.0,
	  "color": Color(1.0, 0.8, 0.35),
	  "flash": "ORE MAGNET — ore comes to you",
	  "desc": "A collector loop older than mining itself. For the rest of the dive, nearby ore is torn loose and banked automatically.",
	  "effect": "Nearby ore auto-collected" },
	{ "id": "prospector", "name": "PROSPECTOR EYE", "duration": REST_OF_DIVE, "min_depth": 0.0,
	  "color": Color(0.5, 0.9, 1.0),
	  "flash": "PROSPECTOR EYE — the rock lights up",
	  "desc": "An alien survey lens. Every vein within range pings on your compass for the rest of the dive.",
	  "effect": "Every vein in range pings the compass" },

	# --- Thermal / energy -------------------------------------------------------
	{ "id": "cryo", "name": "CRYO FLUSH", "duration": 10.0, "min_depth": 0.0,
	  "color": Color(0.4, 0.85, 1.0),
	  "flash": "CRYO FLUSH — heat dumped",
	  "desc": "A coolant charge from a colder world. Heat drops to zero now, and the rig sheds warmth far faster for a while.",
	  "effect": "Heat cleared, then vents faster" },
	{ "id": "capacitor", "name": "POWER CACHE", "duration": INSTANT, "min_depth": 0.0,
	  "color": Color(0.45, 0.7, 1.0),
	  "flash": "POWER CACHE — battery full",
	  "desc": "A sealed cell still holding charge after untold centuries. Energy refills to full, instantly.",
	  "effect": "Energy refilled to full" },
	{ "id": "overcharge", "name": "OVERCHARGE", "duration": 8.0, "min_depth": 0.0,
	  "color": Color(0.55, 0.8, 1.0),
	  "flash": "OVERCHARGE — actions are free",
	  "desc": "A draw the battery was never rated for. For a few seconds drilling and thrusting cost no energy at all.",
	  "effect": "Drilling & thrusting cost no energy" },
	{ "id": "heatsink", "name": "HEAT-SINK SKIN", "duration": 10.0, "min_depth": 0.0,
	  "color": Color(0.6, 0.9, 1.0),
	  "flash": "HEAT-SINK SKIN — drill runs cold",
	  "desc": "A film that drinks heat and gives nothing back. Drilling generates no heat at all for a short window.",
	  "effect": "Drilling makes no heat" },
	{ "id": "pressure_seal", "name": "PRESSURE SEAL", "duration": REST_OF_DIVE, "min_depth": 500.0,
	  "color": Color(0.6, 0.85, 0.95),
	  "flash": "PRESSURE SEAL — the deep lets go",
	  "desc": "A hull skin that ignores the crushing deep. The depth pressure penalty is cancelled for the rest of the dive.",
	  "effect": "Depth pressure penalty removed" },

	# --- Mobility / defense -----------------------------------------------------
	{ "id": "plating", "name": "AEGIS PLATING", "duration": 10.0, "min_depth": 0.0,
	  "color": Color(0.7, 0.95, 0.7),
	  "flash": "AEGIS PLATING — nothing gets through",
	  "desc": "A shimmer of armour that isn't quite matter. Falling rock and toxic gas do no damage for a short time.",
	  "effect": "No damage from debris or gas" },
	{ "id": "phase_dash", "name": "PHASE DRIVE", "duration": 7.0, "min_depth": 0.0,
	  "color": Color(0.6, 0.95, 0.8),
	  "flash": "PHASE DRIVE — dash through stone",
	  "desc": "A drive that walks the rig sideways out of reality. For a few seconds, dashing passes clean through solid rock.",
	  "effect": "Dash passes through solid rock" },
	{ "id": "hover", "name": "HOVER FIELD", "duration": 8.0, "min_depth": 0.0,
	  "color": Color(0.55, 0.95, 0.7),
	  "flash": "HOVER FIELD — gravity loosens",
	  "desc": "An anti-grav plate that never wears down. The thruster booster runs free, no charge or energy, for a while.",
	  "effect": "Free thruster booster" },
	{ "id": "hazmat", "name": "WARD FIELD", "duration": REST_OF_DIVE, "min_depth": 500.0,
	  "color": Color(0.65, 0.9, 0.75),
	  "flash": "WARD FIELD — the Mantle can't touch you",
	  "desc": "A bubble that shrugs off the deep's poisons. Immune to toxic gas and radiation for the rest of the dive.",
	  "effect": "Immune to gas & radiation" },

	# --- Risk / reward ----------------------------------------------------------
	{ "id": "nitro", "name": "NITRO CORE", "duration": 15.0, "min_depth": 150.0,
	  "color": Color(1.0, 0.45, 0.5),
	  "flash": "NITRO CORE — mine like a monster",
	  "desc": "Raw, unstable power. Drill output quadruples — but it runs twice as hot. Watch your heat, or it's your hull.",
	  "effect": "Drill power ×4, but double heat" },
	{ "id": "last_gasp", "name": "LAST GASP", "duration": REST_OF_DIVE, "min_depth": 100.0,
	  "color": Color(1.0, 0.55, 0.6),
	  "flash": "LAST GASP — one death deferred",
	  "desc": "A reflex circuit that refuses to let the rig die once. The next lethal hull failure leaves you at 1%. Armed until spent.",
	  "effect": "Survive one lethal hit at 1% hull" },
]


## Definition for an id, or {} if unknown.
func get_def(id: String) -> Dictionary:
	for p in POWERUPS:
		if p["id"] == id:
			return p
	return {}


## A random powerup eligible to be buried at `depth_m` (its min_depth is reached),
## or {} if none qualify. Uniform pick across eligible entries.
func random_for_depth(depth_m: float) -> Dictionary:
	var pool: Array = []
	for p in POWERUPS:
		if depth_m >= float(p.get("min_depth", 0.0)):
			pool.append(p)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


## Accent colour for an id (white if unknown).
func color_of(id: String) -> Color:
	var d := get_def(id)
	return d.get("color", Color.WHITE) if not d.is_empty() else Color.WHITE


## The plain mechanical effect with its duration, bracketed — for the pickup popup,
## e.g. "(Drill power ×3 · 12s)" or "(Nearby ore auto-collected · rest of dive)".
## "" if the def has no `effect`. Instant boons get no duration suffix.
func effect_line(def: Dictionary) -> String:
	var e := String(def.get("effect", ""))
	if e == "":
		return ""
	var d: float = float(def.get("duration", INSTANT))
	if d > 0.0:
		return "(%s · %ds)" % [e, int(round(d))]
	elif d == REST_OF_DIVE:
		return "(%s · rest of dive)" % e
	return "(%s)" % e
