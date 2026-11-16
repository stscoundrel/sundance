extends SceneTree
## Why he lost, on the end screen (game.why_dead, hints.json), staged a death at a
## time in a quiet San Miguel:
##   rifle    - a rifleman's round from across town: "Shot by a rifleman, from long
##              range.", and the rifles' tip.
##   many     - three of them on him at the end: shot down with several firing, and the
##              tip about too many at once.
##   own      - his own stick at his feet: caught in his own blast.
##   bled     - down in his last stand and left there: bled out, and B binds a wound.
##   names    - a man's named as you'd say it: "a rifleman", "an old timer", "El Jefe".
##   godot --headless --path . --fixed-fps 60 -s tests/test_defeat.gd

const CASES := ["rifle", "many", "own", "bled"]

var game: Node
var frame := 0
var failures := 0
var step := ""
var at := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("level", "san_miguel")
	_load()


func _load() -> void:
	if game:
		game.queue_free()
	if CASES[at] == "bled":
		Engine.remove_meta("no_last_stand")
	else:
		Engine.set_meta("no_last_stand", true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	frame = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _tip(how: String) -> String:
	for r in game.hints["death"]:
		if r.get("how", "") == how and not r.has("guns"):
			return r["tip"]
	return ""


func _man(kind: String) -> Enemy:
	for e in game.enemies:
		if e.alive and e.kind == kind:
			return e
	return null


## The end screen's two lines, and that the HUD has them.
func _says(cause: String, tip: String) -> void:
	check(game.state == "lost", "he should be dead (%s)" % game.state)
	var w: PackedStringArray = game.hud.why
	check(w.size() == 2 and w[0] == cause, "the cause: '%s', not '%s'" % [w[0] if w.size() > 0 else "", cause])
	check(w.size() == 2 and w[1] == tip, "the tip: '%s', not '%s'" % [w[1] if w.size() > 1 else "", tip])


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		game.begin()
		return false
	var p: Player = game.player
	step = CASES[at]
	match step:
		"rifle":
			if frame == 5:
				var r := _man("rifleman")
				r.global_position = p.global_position + Vector2(600, 0)
				p.take_hit(99, Vector2.LEFT, r)
				var tip := ""
				for rule in game.hints["death"]:
					if "rifle" in rule.get("guns", []):
						tip = rule["tip"]
				_says("Shot by a rifleman, from long range.", tip)
				step = "names"
				check(game._who(r) == "a rifleman", "a rifleman: '%s'" % game._who(r))
				check(game._who(_man("jefe")) == "El Jefe", "El Jefe: '%s'" % game._who(_man("jefe")))
				check(game._who(_man("oldtimer")) == "an old timer", "an old timer: '%s'" % game._who(_man("oldtimer")))
				return _next()
		"many":
			if frame == 5:
				var them: Array = game.enemies.filter(func(e): return e.alive).slice(0, 3)
				for e in them:
					e.global_position = p.global_position + Vector2(200, 0)
				p.take_hit(1, Vector2.LEFT, them[0])
				p.take_hit(1, Vector2.LEFT, them[1])
				p.take_hit(99, Vector2.LEFT, them[2])
				var many := ""
				for rule in game.hints["death"]:
					if rule.get("many", false):
						many = rule["tip"]
				_says("Shot down with several of them firing on you.", many)
				return _next()
		"own":
			if frame == 5:
				game.blast(p.global_position, p)
				_says("Caught in your own blast.", _tip("own_blast"))
				return _next()
		"bled":
			if frame == 5:
				p.take_hit(99, Vector2.LEFT, _man("cowboy"))
				check(p.down, "the last stand should have put him down")
				p.down_t = Player.STAND_BLEED - 0.3   # (staged near the end of it: a test keeps it short)
				return false
			if game.state == "lost":
				_says("Bled out.", _tip("bled"))
				return _next()
			if frame > 120:
				check(false, "he never bled out (down_t %.1f)" % p.down_t)
				return _next()
	return false


func _next() -> bool:
	at += 1
	if at < CASES.size():
		_load()
		return false
	print("defeat test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
