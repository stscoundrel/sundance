class_name Music
extends Node
## The level's score: one piece in layers that play together all the way round,
## the game turning each up or down as things go (tools/music.py writes them,
## Ogg Vorbis, imported to loop).
## The snow layer is always there, piano and strings under the wind. Unease comes
## in when a gang's on edge, a man's out searching or the gold's gone missing;
## the fight comes in while men are shooting, the stranger or each other. Every
## layer shares the same bars and chords, so a layer coming up mid-phrase still
## fits. Each one lingers a while after the trouble that brought it: a town
## doesn't settle the moment the last shot's fired. When he dies it all goes,
## and only the wind is left.

const LAYERS := ["snow", "unease", "fight"]
const RISE := {"snow": 3.0, "unease": 4.0, "fight": 1.5}    # s from silent to full
const FALL := {"snow": 5.0, "unease": 9.0, "fight": 7.0}    # s from full to silent
const LINGER := {"unease": 15.0, "fight": 10.0}             # game s it stays after the trouble
const LOUDNESS := -3.0                                       # dB: the whole score under the guns
const LOOK_EVERY := 0.25                                     # s between looks at the town

var game: Node
var player: AudioStreamPlayer
var stream: AudioStreamSynchronized
var level := {"snow": 0.0, "unease": 0.0, "fight": 0.0}   # where each layer is now, 0..1 of full
var want := {"snow": 1.0, "unease": 0.0, "fight": 0.0}    # where it's heading
var linger := {"unease": 0.0, "fight": 0.0}
var _look_t := 0.0


## The score a level names in levels.json ("music"), or null if it has none baked.
static func make(g: Node, name: String) -> Music:
	if name == "" or not g.meta.get("music", {}).has(name):
		return null
	var m := Music.new()
	m.game = g
	m.name = "Music"
	m.process_mode = Node.PROCESS_MODE_ALWAYS   # (it plays on under the menu)
	var paths: Dictionary = g.meta["music"][name]["layers"]
	m.stream = AudioStreamSynchronized.new()
	m.stream.stream_count = LAYERS.size()
	for i in LAYERS.size():
		var s: AudioStream = load(paths[LAYERS[i]])
		m.stream.set_sync_stream(i, s)
		m.stream.set_sync_stream_volume(i, -80.0)
	m.player = AudioStreamPlayer.new()
	m.player.stream = m.stream
	m.player.volume_db = LOUDNESS
	m.player.process_mode = Node.PROCESS_MODE_ALWAYS
	m.add_child(m.player)
	return m


func _ready() -> void:
	player.play()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)   # fades by the ear, not slowed with the game
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = LOOK_EVERY
		var trouble := sense()
		decide(LOOK_EVERY, trouble[0], trouble[1], game.state)
	fade(real)


## What's going on in town: [uneasy, fighting].
func sense() -> Array:
	var uneasy := false
	var fighting := false
	for gs in game.gangs.values():
		if gs["alarm"] >= game.UNEASY:
			uneasy = true
	var box: Strongbox = game.strongbox
	if box and (box.missed or box.holder == game.player):
		uneasy = true
	for e: Enemy in game.enemies:
		if not e.alive or e.downed:
			continue
		if e.st == Enemy.St.COMBAT or e.foe != null:
			fighting = true
			break
		if e.st == Enemy.St.INVESTIGATE or e.st == Enemy.St.SEARCH:
			uneasy = true
	return [uneasy, fighting]


## Sets where each layer is heading, from the trouble in town and how the level
## stands. dt is game time since the last look.
func decide(dt: float, uneasy: bool, fighting: bool, state: String) -> void:
	if fighting:
		linger["fight"] = LINGER["fight"]
	if uneasy or fighting:
		linger["unease"] = LINGER["unease"]
	for k in linger:
		linger[k] = maxf(0.0, linger[k] - dt)
	var playing := state == "play"
	want["snow"] = 0.0 if state == "lost" else 1.0
	want["unease"] = 1.0 if playing and linger["unease"] > 0.0 else 0.0
	want["fight"] = 1.0 if playing and linger["fight"] > 0.0 else 0.0


## Moves each layer toward where it's heading, at its own pace.
func fade(dt: float) -> void:
	for i in LAYERS.size():
		var k: String = LAYERS[i]
		var rate: float = 1.0 / (RISE[k] if want[k] > level[k] else FALL[k])
		level[k] = move_toward(level[k], want[k], rate * dt)
		if stream:
			stream.set_sync_stream_volume(i, linear_to_db(maxf(level[k], 0.0001)))
