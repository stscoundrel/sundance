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
##
## A score can instead be pieces played in turn ("pieces"), where the game knows
## when things come. It says where it starts, which piece runs into which ("next"),
## which happening in the game brings which piece, and from which ("on"), and how
## each switch waits: the next beat, the next bar, or now ("moves"). Played through
## an AudioStreamInteractive. Paso Esperanza's: a build from the moment he's in
## town, a hold that swells round and round, however long the army takes, till
## the first of them sets foot on the map (army); then the call and the action,
## looping to the end; the win on the next bar once it's won. The funeral's: the
## march under the sermon, till his first blow on a nailed lid (blow) brings the
## suspense and the brink; the lid flying off (burst) the rise and the fight;
## the earth in over him (buried) the last tolling; and the win.

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
var pieces: AudioStreamInteractive = null   # a score played in turn, if it's that kind
var piece := ""        # where it's got to: "" (not begun), the last piece it switched to (what runs on from it
                       # included: the train's "build" is the hold too), or "lost"
var spec := {}         # a score in pieces: its "start", "on" and "keep_on_lost" (see _make_pieces)
var gain := 1.0        # 0..1: the whole of a score in pieces, faded out over his body


## The score a level names in levels.json ("music"), or null if it has none baked.
static func make(g: Node, name: String) -> Music:
	if name == "" or not g.meta.get("music", {}).has(name):
		return null
	var m := Music.new()
	m.game = g
	m.name = "Music"
	m.process_mode = Node.PROCESS_MODE_ALWAYS   # (it plays on under the menu)
	var score: Dictionary = g.meta["music"][name]
	m.player = AudioStreamPlayer.new()
	if score.has("pieces"):
		m._make_pieces(score)
		m.player.stream = m.pieces
	else:
		var layers: Array = score["layers"]
		m.stream = AudioStreamSynchronized.new()
		m.stream.stream_count = layers.size()
		for i in layers.size():
			var s: AudioStream = load(layers[i]["path"])
			m.stream.set_sync_stream(i, s)
			m.stream.set_sync_stream_volume(i, -80.0)
			m.roles.append(layers[i]["role"])
		m.player.stream = m.stream
	m.player.volume_db = LOUDNESS
	m.player.process_mode = Node.PROCESS_MODE_ALWAYS
	m.add_child(m.player)
	return m


## The pieces, each told its tempo and length so a switch can wait for a beat,
## and the score's own way through them.
func _make_pieces(score: Dictionary) -> void:
	spec = score
	var list: Array = score["pieces"]
	pieces = AudioStreamInteractive.new()
	pieces.clip_count = list.size()
	var at := {}
	for i in list.size():
		var p: Dictionary = list[i]
		var s: AudioStreamOggVorbis = load(p["path"])
		s.bpm = float(p["bpm"])
		s.beat_count = int(p["beats"])
		s.bar_beats = 4
		s.loop = bool(p["loops"])
		pieces.set_clip_name(i, p["name"])
		pieces.set_clip_stream(i, s)
		at[p["name"]] = i
	pieces.initial_clip = at[score["start"]]
	for from in score["next"]:
		pieces.set_clip_auto_advance(at[from], AudioStreamInteractive.AUTO_ADVANCE_ENABLED)
		pieces.set_clip_auto_advance_next_clip(at[from], at[score["next"][from]])
	var when := {"beat": AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BEAT,
		"bar": AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR,
		"now": AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE}
	for mv in score["moves"]:
		var from: int = AudioStreamInteractive.CLIP_ANY if mv[0] == "*" else at[mv[0]]
		pieces.add_transition(from, at[mv[1]], when[mv[2]], AudioStreamInteractive.TRANSITION_TO_TIME_START,
			AudioStreamInteractive.FADE_OUT, 1.0 if mv[2] != "now" else 0.5)


func _ready() -> void:
	if pieces == null:
		player.play()   # (a score in pieces waits for him to ride in)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)   # fades by the ear, not slowed with the game
	if pieces:
		step_pieces(game.state, happenings())
		gain = move_toward(gain, 0.0 if piece == "lost" else 1.0, real / FALL["always"])
		player.volume_db = LOUDNESS + linear_to_db(maxf(gain, 0.0001))
		return
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


## Has the first of the army set foot on the map?
func army_in() -> bool:
	return game.director != null and game.director.arrived > 0


## What's happened that a score in pieces moves on for.
func happenings() -> Dictionary:
	var box: Coffin = game.coffin
	var fun: Funeral = game.funeral
	return {
		"army": army_in(),
		"won": game.state == "won",
		"blow": box != null and (box.blows > 0 or game.stats.get("blows on a lid that won't give", 0) > 0),
		"burst": box != null and not box.inside and game.state == "play",
		"buried": fun != null and fun.phase == "buried",
	}


## Moves a score in pieces on, by how the level stands and what's happened: the
## first happening in the score's list that's come about, and may interrupt the
## piece that's playing, brings its own.
func step_pieces(state: String, now: Dictionary) -> void:
	if piece == "" and state == "play":
		piece = spec["start"]
		player.play()
	if piece == "" or piece == "lost":
		return
	for rule in spec["on"]:
		if now.get(rule[0], false) and piece in rule[2]:
			piece = rule[1]
			_switch(rule[1])
			break
	if state == "lost" and not piece in spec.get("keep_on_lost", []):
		piece = "lost"


func _switch(clip: String) -> void:
	var pb := player.get_stream_playback() as AudioStreamPlaybackInteractive
	if pb:
		pb.switch_to_clip_by_name(clip)
