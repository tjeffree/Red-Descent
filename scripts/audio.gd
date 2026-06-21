extends Node
## Red Descent — Audio manager (autoload singleton "Audio")
##
## The single owner of all sound. Game code calls semantic helpers and never
## touches an AudioStreamPlayer directly:
##   Audio.sfx("dig_break")          one-shot world/gameplay sound
##   Audio.ui("confirm")             one-shot menu/HUD sound (UI bus)
##   Audio.music("dive")             switch the background track (cross-faded)
##   Audio.dive_loops(player)        drive the continuous dive loops each frame
##   Audio.stop_loops()             silence every loop (run end / scene change)
##
## Design notes
## - One-shots draw from a round-robin pool. Each fire picks a RANDOM variant
##   from the event's set and jitters the pitch a little, so repeated digs and
##   clicks never sound mechanical (the Kenney packs ship in fives for exactly
##   this).
## - Loops (drill, thruster, ascent, hazard ambience) get dedicated persistent
##   players, started/stopped on state edges so re-triggering is free.
## - Music is one streaming player, quickly cross-faded on change.
## - Buses: Master -> Music / SFX / UI (default_bus_layout.tres). Per-bus
##   volume is persisted in GameState and applied on _ready.

# --- Asset folders ---
const IFACE := "res://assets/kenney_interface_sounds/Audio/"
const SCIFI := "res://assets/kenney_scifi_sounds/Audio/"
const IMPACT := "res://assets/kenney_impact_sounds/Audio/"
const MUSIC := "res://assets/srg774_dark_scifi/"
const AMB := "res://assets/oga_dungeon_ambience/"

const SFX_POOL := 12          # concurrent one-shot voices
const MUSIC_FADE := 0.7       # seconds to cross-fade tracks

# One-shot sound sets. Each entry: { dir, files:[names], bus, db, pitch }.
# `pitch` is the +/- jitter applied around 1.0 on each play.
const SFX_DEF := {
	# --- gameplay (SFX bus) ---
	"dig_break":  { "dir": IMPACT, "files": ["impactMining_000","impactMining_001","impactMining_002","impactMining_003","impactMining_004"], "db": -6.0, "pitch": 0.12 },
	"ore":        { "dir": IFACE,  "files": ["pluck_001","pluck_002"], "db": -2.0, "pitch": 0.08 },
	"jump":       { "dir": SCIFI,  "files": ["spaceEngineSmall_000","spaceEngineSmall_002","spaceEngineSmall_004"], "db": -10.0, "pitch": 0.1 },
	"dash":       { "dir": SCIFI,  "files": ["forceField_000","forceField_002","forceField_004"], "db": -7.0, "pitch": 0.1 },
	"hull_hit":   { "dir": SCIFI,  "files": ["impactMetal_000","impactMetal_001","impactMetal_002","impactMetal_003","impactMetal_004"], "db": -3.0, "pitch": 0.1 },
	"debris_hit": { "dir": IMPACT, "files": ["impactPlate_heavy_000","impactPlate_heavy_001","impactPlate_heavy_002","impactPlate_heavy_003","impactPlate_heavy_004"], "db": -5.0, "pitch": 0.12 },
	"cavein":     { "dir": SCIFI,  "files": ["explosionCrunch_000","explosionCrunch_001","explosionCrunch_002","explosionCrunch_003","explosionCrunch_004"], "db": -3.0, "pitch": 0.08 },
	"death":      { "dir": SCIFI,  "files": ["lowFrequency_explosion_000","lowFrequency_explosion_001"], "db": 0.0, "pitch": 0.05 },
	"biome":      { "dir": SCIFI,  "files": ["doorOpen_000","doorOpen_001","doorOpen_002"], "db": -4.0, "pitch": 0.06 },
	"transmission": { "dir": IFACE, "files": ["glitch_001","glitch_002","glitch_003","glitch_004"], "db": -9.0, "pitch": 0.1 },
	"datalog":    { "dir": IFACE,  "files": ["bong_001"], "db": -3.0, "pitch": 0.06 },
	"powerup":    { "dir": IFACE,  "files": ["pluck_001","pluck_002"], "db": -1.0, "pitch": 0.12 },
	"low_energy": { "dir": IFACE,  "files": ["glass_001","glass_003","glass_005"], "db": -3.0, "pitch": 0.05 },
	"crush":      { "dir": SCIFI,  "files": ["lowFrequency_explosion_000","lowFrequency_explosion_001"], "db": 1.0, "pitch": 0.04 },

	# --- interface (UI bus) ---
	"focus":      { "dir": IFACE, "bus": "UI", "files": ["select_001","select_002","select_003","select_004","select_005","select_006"], "db": -8.0, "pitch": 0.06 },
	"click":      { "dir": IFACE, "bus": "UI", "files": ["click_001","click_002","click_003","click_004","click_005"], "db": -5.0, "pitch": 0.06 },
	"confirm":    { "dir": IFACE, "bus": "UI", "files": ["confirmation_001","confirmation_002","confirmation_003"], "db": -3.0, "pitch": 0.05 },
	"buy":        { "dir": IFACE, "bus": "UI", "files": ["confirmation_002","confirmation_004"], "db": -2.0, "pitch": 0.05 },
	"deny":       { "dir": IFACE, "bus": "UI", "files": ["error_003","error_004","error_006"], "db": -5.0, "pitch": 0.05 },
	"open":       { "dir": IFACE, "bus": "UI", "files": ["open_001","open_002","open_003","open_004"], "db": -4.0, "pitch": 0.05 },
	"close":      { "dir": IFACE, "bus": "UI", "files": ["back_001","back_002","back_003","back_004"], "db": -4.0, "pitch": 0.05 },
	"launch":     { "dir": IFACE, "bus": "UI", "files": ["confirmation_004"], "db": 0.0, "pitch": 0.03 },
	"tick":       { "dir": IFACE, "bus": "UI", "files": ["tick_001","tick_002","tick_004"], "db": -4.0, "pitch": 0.04 },
}

# Continuous loops. Each entry: { dir, file, bus, db }. The stream's `loop`
# flag is forced on at load so the .ogg repeats seamlessly.
const LOOP_DEF := {
	"drill":     { "dir": SCIFI, "file": "engineCircular_000", "db": -8.0 },
	"thruster":  { "dir": SCIFI, "file": "thrusterFire_000", "db": -9.0 },
	"ascent":    { "dir": SCIFI, "file": "spaceEngineLarge_000", "db": -4.0 },
	"lava":      { "dir": SCIFI, "file": "spaceEngineLow_000", "db": -8.0 },
	"gas":       { "dir": SCIFI, "file": "slime_000", "db": -9.0 },
	"radiation": { "dir": SCIFI, "file": "forceField_000", "db": -12.0 },
}

# Music tracks (Music bus). Looped streaming playback.
const MUSIC_DEF := {
	"menu":    MUSIC + "title.mp3",
	"hub":     MUSIC + "airy.mp3",
	"dive":    AMB + "dungeon_ambient.ogg",
	"reveal":  MUSIC + "sector.mp3",
	"lockdown": MUSIC + "urgent.mp3",
	"launch":  MUSIC + "victory.mp3",
}

# --- runtime state ---
var _streams := {}            # event name -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _loops := {}              # loop key -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_key := ""
var _music_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# One-shot voice pool.
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	# Music player.
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	# Pre-load every one-shot set (skipping any file that failed to import).
	for key in SFX_DEF:
		var arr: Array[AudioStream] = []
		var def: Dictionary = SFX_DEF[key]
		for fname in def["files"]:
			var s := _load_stream(def["dir"] + fname + ".ogg")
			if s != null:
				arr.append(s)
		_streams[key] = arr
	# Build the loop players.
	for key in LOOP_DEF:
		var def: Dictionary = LOOP_DEF[key]
		var s := _load_stream(def["dir"] + def["file"] + ".ogg")
		if s == null:
			continue
		_set_loopable(s, true)
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "SFX"
		p.volume_db = def["db"]
		add_child(p)
		_loops[key] = p
	apply_volumes()


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Audio: missing stream " + path)
		return null
	return load(path) as AudioStream


## Force a stream to loop (Ogg Vorbis and MP3 expose a `loop` property in 4.x).
func _set_loopable(s: AudioStream, on: bool) -> void:
	if s == null:
		return
	if "loop" in s:
		s.set("loop", on)


# --- one-shots ----------------------------------------------------------------

## Play a one-shot gameplay sound (SFX bus) by event name.
func sfx(key: String) -> void:
	_play_oneshot(key)


## Play a one-shot interface sound (UI bus) by event name.
func ui(key: String) -> void:
	_play_oneshot(key)


func _play_oneshot(key: String) -> void:
	var arr: Array = _streams.get(key, [])
	if arr.is_empty():
		return
	var def: Dictionary = SFX_DEF[key]
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = arr[_rng.randi_range(0, arr.size() - 1)]
	p.bus = def.get("bus", "SFX")
	p.volume_db = def.get("db", 0.0)
	var j: float = def.get("pitch", 0.0)
	p.pitch_scale = 1.0 + _rng.randf_range(-j, j)
	p.play()


# --- loops --------------------------------------------------------------------

func _loop_set(key: String, on: bool) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null:
		return
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


## Drive the continuous dive loops from the rig's live flags. Called every
## frame by the dive controller; transitions are edge-cheap (start/stop only).
func dive_loops(player: Node) -> void:
	if player == null:
		return
	var ascending: bool = player.get("_ascending")
	_loop_set("ascent", ascending)
	if ascending:
		# During the recall ascent only the rocket plays.
		_loop_set("drill", false)
		_loop_set("thruster", false)
		_loop_set("lava", false)
		_loop_set("gas", false)
		_loop_set("radiation", false)
		return
	_loop_set("drill", player.get("is_drilling"))
	_loop_set("thruster", player.get("is_thrusting"))
	var hz: String = String(player.get("active_hazard"))
	_loop_set("lava", hz == "lava")
	_loop_set("gas", hz == "gas")
	_loop_set("radiation", bool(player.get("in_radiation")))


## Stop every loop (run end, death, scene change).
func stop_loops() -> void:
	for key in _loops:
		_loop_set(key, false)


## Cut every in-flight one-shot voice. Call on scene changes so a long sound (or
## a burst like the low-energy alarm) never bleeds into the next scene.
func stop_oneshots() -> void:
	for p in _pool:
		p.stop()


## Silence everything but music — loops + one-shots. Used when entering a scene
## that should start from a clean audio slate.
func stop_all_sfx() -> void:
	stop_loops()
	stop_oneshots()


# --- music --------------------------------------------------------------------

## Switch the background track (cross-faded). Pass "" to fade to silence.
func music(key: String) -> void:
	if key == _music_key:
		return
	_music_key = key
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	# Fade the current track out, swap, fade the new one in.
	_music_tween.tween_property(_music, "volume_db", -40.0, MUSIC_FADE * 0.5)
	_music_tween.tween_callback(func() -> void: _swap_music(key))
	if key != "":
		_music_tween.tween_property(_music, "volume_db", 0.0, MUSIC_FADE)


func _swap_music(key: String) -> void:
	_music.stop()
	if key == "" or not MUSIC_DEF.has(key):
		return
	var s := _load_stream(MUSIC_DEF[key])
	if s == null:
		return
	_set_loopable(s, true)
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()


# --- bus volumes (persisted in GameState) ------------------------------------

## Apply the persisted per-bus volumes (0..1 linear) to the audio buses.
func apply_volumes() -> void:
	for bus_name in ["Master", "Music", "SFX", "UI"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var lin: float = clampf(_get_volume(bus_name), 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(lin) if lin > 0.0 else -80.0)
		AudioServer.set_bus_mute(idx, lin <= 0.0)


## Read a saved linear volume for a bus, defaulting sensibly.
func _get_volume(bus_name: String) -> float:
	var defaults := { "Master": 0.9, "Music": 0.7, "SFX": 0.9, "UI": 0.8 }
	return float(GameState.volumes.get(bus_name, defaults.get(bus_name, 1.0)))


## Set a bus volume (0..1), apply it live, and persist.
func set_volume(bus_name: String, linear: float) -> void:
	GameState.volumes[bus_name] = clampf(linear, 0.0, 1.0)
	apply_volumes()
	GameState.save_game()
