extends SceneTree
## The towns' scores:
##   quiet  - in a quiet Silencio only the snow (the ground of it) plays, come up
##            to full; its three layers are all loaded, looping, playing together.
##   unease - a gang on edge brings the unease layer in; it lingers after.
##   fight  - a man in a fight brings the fight in, and unease with it; once it's
##            over the fight lingers a while, then goes, unease after it.
##   lost   - when the stranger's dead the whole score fades, the ground too.
##   fort   - Cruz Verde asleep plays only the tension; the shooting
##            starts and the tension gives way to the battle, back once it's long over.
##   train  - Paso Esperanza's pieces: nothing till he rides in, then the build; the
##            first soldier on the map brings the call and the action; won, the win;
##            his death fades it all.
##   godot --headless --path . --fixed-fps 60 -s tests/test_music.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var town := "silencio"


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_captive", true)
	_ride("silencio")


func _ride(id: String) -> void:
	town = id
	Engine.set_meta("level", id)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	t = 0.0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 2 and town == "train":
		step = "train"
		check(game.music != null and game.music.piece == "" and not game.music.player.playing,
			"the train's music plays before he's ridden in")
	if frame == 3:
		game.begin()
	if frame <= 3:
		return false
	t += delta
	if t < 4.0:
		return false
	var m: Music = game.music
	step = town
	check(m != null, "%s has no score" % town)
	if m == null:
		quit(1)
		return true
	if town == "train":
		_train(m)
		print("music test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
		quit(failures)
		return true
	check(m.stream.stream_count == m.roles.size() and m.player.playing, "not playing all its layers")
	for i in m.roles.size():
		var o: AudioStreamOggVorbis = m.stream.get_sync_stream(i)
		check(o != null and o.loop, "layer %d doesn't loop" % i)
	if town == "silencio":
		step = "quiet"
		check(Array(m.roles) == ["always", "unease", "fight"], "Silencio's layers: %s" % [m.roles])
		check(m.level["always"] > 0.99 and m.level["unease"] == 0.0 and m.level["fight"] == 0.0,
			"the quiet town's not snow alone: %s" % m.level)
		check(m.sense() == [false, false], "trouble in a quiet town: %s" % [m.sense()])
		_layers(m)
		game.queue_free()
		_ride("cruz_verde")
		return false
	_fort(m)
	game.queue_free()
	_ride("train")
	return false


## The rules, fed by hand: what each layer heads for, and how long it stays.
func _layers(m: Music) -> void:
	step = "unease"
	var g: String = game.gangs.keys().filter(func(k): return k != "")[0]
	game.gangs[g]["alarm"] = game.UNEASY + 1.0
	check(m.sense()[0] and not m.sense()[1], "a gang on edge isn't uneasy: %s" % [m.sense()])
	game.gangs[g]["alarm"] = 0.0
	m.decide(0.25, true, false, "play")
	check(m.want["unease"] == 1.0 and m.want["fight"] == 0.0, "unease isn't coming: %s" % m.want)
	m.fade(2.0)
	check(m.level["unease"] > 0.4 and m.level["unease"] < 0.6, "unease came in at the wrong pace: %s" % m.level)
	m.decide(Music.LINGER["unease"] - 1.0, false, false, "play")
	check(m.want["unease"] == 1.0, "unease didn't linger")
	m.decide(2.0, false, false, "play")
	check(m.want["unease"] == 0.0, "unease never went")

	step = "fight"
	var e: Enemy = game.enemies[0]
	e.st = Enemy.St.COMBAT
	check(m.sense()[1], "a man in a fight isn't a fight")
	e.st = Enemy.St.PATROL
	m.decide(0.25, false, true, "play")
	check(m.want["fight"] == 1.0 and m.want["unease"] == 1.0, "the fight didn't bring both: %s" % m.want)
	m.fade(Music.RISE["fight"] + 0.1)
	check(m.level["fight"] == 1.0, "the fight didn't come up: %s" % m.level)
	m.decide(Music.LINGER["fight"] + 0.5, false, false, "play")
	check(m.want["fight"] == 0.0 and m.want["unease"] == 1.0, "the fight should go before the unease: %s" % m.want)

	step = "lost"
	m.decide(0.25, false, false, "lost")
	check(m.want.values().all(func(v): return v == 0.0), "the score plays on over his body: %s" % m.want)
	m.fade(10.0)
	check(m.level.values().all(func(v): return v == 0.0), "it didn't fade: %s" % m.level)
	m.decide(0.25, false, false, "won")
	check(m.want["always"] == 1.0 and m.want["fight"] == 0.0, "a won town isn't the ground alone: %s" % m.want)


func _fort(m: Music) -> void:
	step = "fort"
	check(Array(m.roles) == ["calm", "fight"], "Cruz Verde's layers: %s" % [m.roles])
	check(m.level["calm"] > 0.99 and m.level["fight"] == 0.0, "the sleeping fort isn't the tension alone: %s" % m.level)
	game.last_gunfire = game.clock
	check(m.sense()[1], "a shot fired isn't a fight")
	game.last_gunfire = game.clock - Music.SHOTS_HEARD - 1.0
	check(not m.sense()[1], "an old shot's still a fight")
	m.decide(0.25, false, true, "play")
	m.fade(Music.FALL["calm"] + 0.1)
	check(m.level["calm"] == 0.0 and m.level["fight"] == 1.0, "the shooting didn't bring the battle in: %s" % m.level)
	m.decide(Music.LINGER["fight"] + 0.5, false, false, "play")
	check(m.want["calm"] == 1.0 and m.want["fight"] == 0.0, "the tension isn't back after the fight: %s" % m.want)


func _train(m: Music) -> void:
	step = "train"
	var names := []
	for i in m.pieces.clip_count:
		names.append(String(m.pieces.get_clip_name(i)))
		var o: AudioStreamOggVorbis = m.pieces.get_clip_stream(i)
		check(o.loop == (names[i] in ["hold", "action"]), "%s loops wrong" % names[i])
		var beats_long := o.beat_count * 60.0 / o.bpm
		check(absf(o.get_length() - beats_long) < 0.01 if o.loop else o.get_length() >= beats_long - 0.01,
			"%s isn't its beats long: %.3f s" % [names[i], o.get_length()])
	check(names == ["build", "hold", "call", "action", "won"], "the pieces: %s" % [names])
	check(m.piece == "build" and m.player.playing, "the build isn't playing: %s" % m.piece)
	check(not m.army_in(), "the army's in already, %.1f s in" % t)
	m.step_pieces("play", true)
	check(m.piece == "action", "the army's in and no action: %s" % m.piece)
	m.step_pieces("won", true)
	check(m.piece == "won", "won, and no win: %s" % m.piece)
	m.piece = "action"
	m.step_pieces("lost", true)
	check(m.piece == "lost", "dead, and it plays on: %s" % m.piece)
