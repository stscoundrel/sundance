extends SceneTree
## Silencio's score:
##   quiet  - in a quiet town only the snow layer plays, and it's come up to full;
##            the score's three layers are all loaded and playing together.
##   unease - a gang on edge brings the unease layer in; it lingers after.
##   fight  - a man in a fight brings the fight in, and unease with it; once it's
##            over the fight lingers a while, then goes, unease after it.
##   lost   - when the stranger's dead the whole score fades, the snow too.
##   godot --headless --path . --fixed-fps 60 -s tests/test_music.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_civilians", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
	if frame <= 3:
		return false
	t += delta
	if t < 4.0:
		return false
	var m: Music = game.music
	step = "quiet"
	check(m != null, "Silencio has no score")
	if m == null:
		quit(1)
		return true
	check(m.stream.stream_count == 3 and m.player.playing, "not playing all three layers")
	for i in 3:
		var o: AudioStreamOggVorbis = m.stream.get_sync_stream(i)
		check(o != null and o.loop, "layer %d doesn't loop" % i)
	check(m.level["snow"] > 0.99 and m.level["unease"] == 0.0 and m.level["fight"] == 0.0,
		"the quiet town's not snow alone: %s" % m.level)
	check(m.sense() == [false, false], "trouble in a quiet town: %s" % [m.sense()])
	_layers(m)
	print("music test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true


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
	check(m.want["snow"] == 1.0 and m.want["fight"] == 0.0, "a won town isn't snow alone: %s" % m.want)
