extends Node
## Red Descent — Lore (autoload singleton, Phase 7)
##
## The narrative content + trigger evaluation for the "what's happening" beats.
## Channels:
##   TRANSMISSIONS — the pilot's running log, fired ONCE each during a dive when a
##     condition (depth/biome/hazard/event) is met; shown as a HUD subtitle.
##   AMBIENT_PILOT — repeatable filler chatter shown between story beats, so the
##     descent keeps feeling alive across many dives.
##   DATA_LOGS — fabricated artifacts buried in the strata; dug up mid-dive, each
##     reveals a fragment of what the ancient terraformers left behind (GDD §7).
##   EARTH_COMMS — progress-gated contact received at the surface hub; Earth drifts
##     from reassurance into confusion and intrigue.
##   AMBIENT_EARTH — repeatable hub small-talk when there's no new gated comm.
##
## VARIETY ("bake-time"): each story beat carries a `variants` pool; line() picks
## one at random and fills templating tokens ({depth} {ore} {hull} {deepest}
## {alloy} {shippct}) from a ctx dict. The archive shows canonical() (variant 0)
## so the official record reads consistently while delivery varies per run.
##
## This module is STATELESS. "Seen"/"collected" flags live in GameState (saved).

# Each transmission: one trigger key — depth(float)>= / biome(String)== /
# hazard(String)== / event(String)== — and a `variants` pool of phrasings.
const TRANSMISSIONS: Array = [
	{ "id": "t_start",  "trigger": { "depth": 0.0 }, "variants": [
		"Suit telemetry online. This rig was built for rock that floats — not rock that bites back. Find my ship's guts, get off this rust-ball.",
		"Systems green. Wrong planet, wrong gear, wrong everything. Let's dig anyway.",
		"Drill spun up. Somewhere under all this rust are the parts that get me home." ] },
	{ "id": "t_d100",   "trigger": { "depth": 100.0 }, "variants": [
		"Hull groans at every metre. Martian crust is denser than the briefings promised.",
		"A hundred metres and the walls are already pushing back. Briefings lied.",
		"The deeper I go, the heavier everything feels. Including me." ] },
	{ "id": "t_d250",   "trigger": { "depth": 250.0 }, "variants": [
		"Strange. The rock down here is layered too evenly — almost like someone poured it.",
		"These strata are too neat. Nature doesn't lay courses like a bricklayer.",
		"Two hundred fifty metres. Either Mars is tidy, or someone tidied it." ] },
	{ "id": "t_cavein", "trigger": { "event": "cavein" }, "variants": [
		"The whole ceiling came down. On Mars my impactors don't clear rock — they bury you in it.",
		"Cave-in. My zero-g charges are death traps under real gravity.",
		"Rock's still falling. Note to self: stop digging so wide." ] },
	{ "id": "t_mantle", "trigger": { "biome": "mantle" }, "variants": [
		"Into the Mantle. Heat's climbing. The walls glow like they remember a fire.",
		"Crossed into the Mantle. It's hotter, darker, and it does not want me here.",
		"The Mantle. Everything down here glows faintly, like the rock is embarrassed." ] },
	{ "id": "t_lava",   "trigger": { "hazard": "lava" }, "variants": [
		"Lava tube. Beautiful. Lethal. Keep the drill moving.",
		"Molten channel ahead — my heat gauge just spiked. Through it, not into it.",
		"A river of fire older than the colony. Don't stop, don't stare." ] },
	{ "id": "t_gas",    "trigger": { "hazard": "gas" }, "variants": [
		"Toxic pocket — that hiss is my hull thinning. Don't linger.",
		"Gas. The corrosion alarm is the loudest thing on this rig right now.",
		"Something's eating my plating. Get clear of this pocket, now." ] },
	{ "id": "t_rad",    "trigger": { "hazard": "radiation" }, "variants": [
		"Telemetry's screaming static. This radiation isn't natural decay — it's shielded leakage. Shielded by what?",
		"Instruments are garbage in here. This isn't background rad — something down here is leaking through shielding.",
		"Radiation scrambling my readouts. You don't shield a rock. You shield a machine." ] },
	{ "id": "t_d750",   "trigger": { "depth": 750.0 }, "variants": [
		"Found metal in the strata. Not ore — fabricated. Rivets older than the colony charter.",
		"That's worked metal in the rock. Rivets. Seams. Someone built down here.",
		"Seven hundred fifty metres and I'm digging past someone's handiwork." ] },
	{ "id": "t_deep",   "trigger": { "depth": 985.0 }, "variants": [
		"The drill won't bite. Something down here was built to never be dug through. There's a door in the dark. Whatever I came for, it isn't my ship.",
		"Bedrock that isn't bedrock. There's a door down here. My ship was never the point.",
		"The drill just slides off it. There's a threshold in the dark, and it was made to last forever." ] },
	{ "id": "t_ruins",  "trigger": { "biome": "ruins" }, "variants": [
		"I'm inside it. Corridors. Bulkheads. Right angles that no cave ever made. This is a structure — and it's enormous.",
		"Through the vault. The walls are steel the drill can't touch. Someone built a cathedral under the crust and then sealed it.",
		"It's a silo. Human-made, human-old, impossibly deep. Whatever Earth doesn't know, it's down here in the dark with me." ] },
]

# Repeatable pilot filler (templated). Shown between story beats.
const AMBIENT_PILOT: Array = [
	"Depth {depth} metres. Drill's holding. Barely.",
	"{ore} units in the hopper. Mars doesn't give it up easy.",
	"Hull at {hull} percent. I've flown worse. I think.",
	"Every metre down, the rig fights me harder. Wrong gear, wrong world.",
	"Talking to myself again. The silence down here has weight to it.",
	"Readout says {depth} metres. The surface feels like a rumour.",
	"Something hums in the rock. Probably just my nerves.",
	"Heat, energy, hull — pick which one kills you, then keep digging.",
]

# Buried artifacts. Placed by world.gd within [min_depth, max_depth] metres.
const DATA_LOGS: Array = [
	{ "id": "log_1", "title": "TERRAFORMING LOG 01", "min_depth": 520.0, "max_depth": 680.0,
	  "text": "Project Red Bloom, year one. We seed the core with heat and the sky will follow. Mars will breathe again. The silo will outlive us all." },
	{ "id": "log_2", "title": "MAINTENANCE NOTICE", "min_depth": 600.0, "max_depth": 780.0,
	  "text": "Capsule bay sealed pending evac authorization. One seat. The committee has not decided who." },
	{ "id": "log_3", "title": "PERSONAL — A. VOSS", "min_depth": 720.0, "max_depth": 900.0,
	  "text": "We were never going to terraform a planet in our lifetimes. We knew. We built the silo so someone, someday, could leave. The drive only powers once." },
	{ "id": "log_4", "title": "FINAL ENTRY", "min_depth": 860.0, "max_depth": 1000.0,
	  "text": "Power's failing. We're sealing it for whoever comes next. If you're reading this, you dug a long way down. The capsule still works — it just needs a heart to give it. Don't waste it like we did." },
]

# Earth Relay — occasional contact at the surface, gated by progress.
# `requires` (all must hold): "depth": best_depth >= m / "logs": >= N data logs /
# "ship_complete": ship fully repaired. Shown in hub order, once each.
const EARTH_COMMS: Array = [
	{ "id": "e_1", "requires": {}, "variants": [
		"EARTH RELAY: Glad you walked away from that landing, Pilot. Salvage your ship, sit tight. Resupply is — optimistically — scheduled. Keep digging.",
		"EARTH RELAY: You're alive. That's already better than the odds. Patch the ship, dig for parts, and don't do anything heroic." ] },
	{ "id": "e_2", "requires": { "depth": 250.0 }, "variants": [
		"EARTH RELAY: Your depth logs came through. Two hundred metres? The orbital survey called bedrock at sixty. Recheck your instruments and confirm.",
		"EARTH RELAY: {deepest} metres on record. That's well past where the survey said you'd hit solid rock. Are your sensors lying, or is the survey?" ] },
	{ "id": "e_3", "requires": { "depth": 500.0 }, "variants": [
		"EARTH RELAY: We're seeing structure in your seismic feed. Regular geometry. Probably drill harmonics. ...Probably. Bag a sample if you can.",
		"EARTH RELAY: There are straight lines in your readings, Pilot. Rock doesn't do straight lines. Tell us we're imagining it." ] },
	{ "id": "e_4", "requires": { "logs": 1 }, "variants": [
		"EARTH RELAY: That artifact you flagged — its timestamp predates the first crewed Mars landing. That's impossible. Command says firmware glitch. Find us another.",
		"EARTH RELAY: We ran the artifact's date three times. It's older than the colony. Older than us being here at all. Keep recording everything." ] },
	{ "id": "e_5", "requires": { "logs": 2 }, "variants": [
		"EARTH RELAY: The linguistics team has gone quiet on us. Off the record, Pilot: who was down there before any of us? And how do they have our language?",
		"EARTH RELAY: They wrote in our words. Centuries before our words existed. Nobody up here will say it out loud, so I will: this scares me." ] },
	{ "id": "e_6", "requires": { "depth": 850.0 }, "variants": [
		"EARTH RELAY: We've stopped routing your feed to Command — they'd ground you on the spot. Whatever this is, keep it on our channel. We have to see where it goes.",
		"EARTH RELAY: Just us on this frequency now, Pilot. The brass can't know what you're finding. Don't surface. Go deeper." ] },
	{ "id": "e_7", "requires": { "logs": 4 }, "variants": [
		"EARTH RELAY: Pilot. If there is a vessel down there that can reach us, then the ship you're repairing doesn't matter. Do you understand what we're telling you? ...Earth out.",
		"EARTH RELAY: Forget the salvage. If what's buried down there can fly, that's your way home — not the wreck. Think hard about what that means. Earth out." ] },
	{ "id": "e_8", "requires": { "ship_complete": true }, "variants": [
		"EARTH RELAY: Your hull reads repaired — but the drive telemetry is wrong. Like it's reading two engines. Don't trust it. We think the way home is still beneath you.",
		"EARTH RELAY: Congratulations, the ship's whole again. So why is the drive reporting power it doesn't have? Don't launch on that. The answer's still underground." ] },
]

# Repeatable hub small-talk when there's no new gated comm (templated).
const AMBIENT_EARTH: Array = [
	"EARTH RELAY: Routine check. Deepest on record: {deepest} metres. Stay sharp, Pilot.",
	"EARTH RELAY: {alloy} alloy banked. Spend it wisely — we can't ship you spares.",
	"EARTH RELAY: Ship repairs at {shippct} percent. Home's a long way up, but it's up.",
	"EARTH RELAY: Quiet shift up here. We left the channel open in case you need a voice.",
	"EARTH RELAY: No new orders. Off the record — we're all rooting for you down there.",
]


## Pick a delivery line for a story beat: a random `variants` entry (or `text`),
## with templating tokens filled from ctx.
func line(entry: Dictionary, ctx: Dictionary = {}) -> String:
	var s := ""
	var v: Variant = entry.get("variants", null)
	if typeof(v) == TYPE_ARRAY and not (v as Array).is_empty():
		s = String((v as Array)[randi() % (v as Array).size()])
	else:
		s = String(entry.get("text", ""))
	return _fill(s, ctx)


## The canonical (stable) phrasing of a beat — variant 0, or `text`. Used by the
## hub archive so the record reads consistently regardless of in-run delivery.
func canonical(entry: Dictionary) -> String:
	var v: Variant = entry.get("variants", null)
	if typeof(v) == TYPE_ARRAY and not (v as Array).is_empty():
		return String((v as Array)[0])
	return String(entry.get("text", ""))


## Random repeatable line from a pool of plain strings, with templating.
func from_pool(pool: Array, ctx: Dictionary = {}) -> String:
	if pool.is_empty():
		return ""
	return _fill(String(pool[randi() % pool.size()]), ctx)


## Replace {token}s present in ctx; leaves unknown tokens untouched (so a line
## only references tokens valid for its channel).
func _fill(s: String, ctx: Dictionary) -> String:
	for k in ctx:
		s = s.replace("{" + String(k) + "}", str(ctx[k]))
	return s


func get_transmission(id: String) -> Dictionary:
	for t in TRANSMISSIONS:
		if t["id"] == id:
			return t
	return {}


func get_log(id: String) -> Dictionary:
	for l in DATA_LOGS:
		if l["id"] == id:
			return l
	return {}


## First unseen Earth-relay comm whose progress requirement is met, or {}.
func next_earth_comm() -> Dictionary:
	for c in EARTH_COMMS:
		if GameState.transmission_seen(c["id"]):
			continue
		if _requirement_met(c.get("requires", {})):
			return c
	return {}


func _requirement_met(req: Dictionary) -> bool:
	if req.has("depth") and GameState.best_depth < float(req["depth"]):
		return false
	if req.has("logs") and GameState.collected_logs.size() < int(req["logs"]):
		return false
	if req.has("ship_complete") and not GameState.ship_complete():
		return false
	return true


## Does this transmission's trigger fire given the current dive context?
## ctx keys: depth(float), biome(String), hazard(String), event(String).
func fires(t: Dictionary, ctx: Dictionary) -> bool:
	var trig: Dictionary = t.get("trigger", {})
	if trig.has("depth"):
		return float(ctx.get("depth", 0.0)) >= float(trig["depth"])
	if trig.has("biome"):
		return String(ctx.get("biome", "")) == String(trig["biome"])
	if trig.has("hazard"):
		return String(ctx.get("hazard", "")) == String(trig["hazard"])
	if trig.has("event"):
		return String(ctx.get("event", "")) == String(trig["event"])
	return false
