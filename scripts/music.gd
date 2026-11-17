class_name Music
extends Node
## The level's score: one piece in layers that play together all the way round,
## the game turning each up or down as things go (tools/music.py writes them,
## Ogg Vorbis, imported to loop). Every layer shares the same bars and chords, so
## a layer coming up mid-phrase still fits. Each layer has a part to play:
##   always - the ground of it, there the whole time (Silencio's snow, Cruz
##            Verde's picked guitar and tolling string);
##   calm   - only while there's no fight on: the fort asleep, the stranger
##            creeping in, the ticking and the whistle from the walls;
##   unease - when a gang's on edge, a man's out searching or the gold's missing;
##   fight  - while men are shooting, at the stranger or at each other.
## Unease and the fight linger a while after the trouble that brought them: a
## town doesn't settle the moment the last shot's fired. When he dies it all
## goes, and only the wind is left; when the job's done it's the ground alone.

const RISE := {"always": 3.0, "calm": 3.0, "unease": 4.0, "fight": 1.5}   # s from silent to full
const FALL := {"always": 5.0, "calm": 2.0, "unease": 9.0, "fight": 7.0}   # s from full to silent
const LINGER := {"unease": 15.0, "fight": 10.0}   # game s it stays after the trouble
const LOUDNESS := -3.0                             # dB: the whole score under the guns
const LOOK_EVERY := 0.25                           # s between looks at the town
const SHOTS_HEARD := 3.0                           # game s a shot anywhere counts as a fight on

var game: Node
var player: AudioStreamPlayer
var stream: AudioStreamSynchronized
var roles: Array[String] = []   # each layer's part, in the stream's order
var level := {"always": 0.0, "calm": 0.0, "unease": 0.0, "fight": 0.0}   # where each part is now, 0..1 of full
var want := {"always": 1.0, "calm": 1.0, "unease": 0.0, "fight": 0.0}    # where it's heading
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
	var layers: Array = g.meta["music"][name]["layers"]
	m.stream = AudioStreamSynchronized.new()
	m.stream.stream_count = layers.size()
	for i in layers.size():
		var s: AudioStream = load(layers[i]["path"])
		m.stream.set_sync_stream(i, s)
		m.stream.set_sync_stream_volume(i, -80.0)
		m.roles.append(layers[i]["role"])
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
	var fighting: bool = game.clock - game.last_gunfire < SHOTS_HEARD   # (the first shot brings it at once)
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


## Sets where each part is heading, from the trouble in town and how the level
## stands. dt is game time since the last look.
func decide(dt: float, uneasy: bool, fighting: bool, state: String) -> void:
	if fighting:
		linger["fight"] = LINGER["fight"]
	if uneasy or fighting:
		linger["unease"] = LINGER["unease"]
	for k in linger:
		linger[k] = maxf(0.0, linger[k] - dt)
	var playing := state == "play"
	var over := state == "won" or state == "lost"
	want["always"] = 0.0 if state == "lost" else 1.0
	want["calm"] = 0.0 if over or linger["fight"] > 0.0 else 1.0
	want["unease"] = 1.0 if playing and linger["unease"] > 0.0 else 0.0
	want["fight"] = 1.0 if playing and linger["fight"] > 0.0 else 0.0


## Moves each part toward where it's heading, at its own pace.
func fade(dt: float) -> void:
	for k in level:
		var rate: float = 1.0 / (RISE[k] if want[k] > level[k] else FALL[k])
		level[k] = move_toward(level[k], want[k], rate * dt)
	if stream:
		for i in roles.size():
			stream.set_sync_stream_volume(i, linear_to_db(maxf(level[roles[i]], 0.0001)))
