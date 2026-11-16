extends SceneTree
## The lines under the count (hud.status_lines), where a town's goal stands:
##   fort     - Cruz Verde counts REVOLUTIONARIES; before the first shot his partner's
##              at the well; after it, the guard's count and the next band, with how
##              many bands are left.
##   gold     - Silencio's truce and gold on one line: the truce holding, the gold in
##              the livery; in his arms, to the horse; set down, lying in the snow;
##              the truce broken.
##   funeral  - the funeral counts MOURNERS; a runner for help has an arrow on him, and
##              once he's home, the help's countdown.
##   godot --headless --path . --fixed-fps 60 -s tests/test_goals.gd

const LEVELS := ["cruz_verde", "silencio", "funeral"]

var game: Node
var frame := 0
var failures := 0
var step := ""
var at := 0
var shot_at := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_coffin", true)
	_load()


func _load() -> void:
	if game:
		game.queue_free()
	Engine.set_meta("level", LEVELS[at])
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	frame = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _lines() -> Array:
	return game.hud.status_lines().map(func(l): return l[0])


func _has(part: String) -> bool:
	return _lines().any(func(l): return part in l)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		game.begin()
		return false
	match LEVELS[at]:
		"cruz_verde":
			step = "fort"
			if frame == 5:
				check(game.level.get("foe_count", "") == "REVOLUTIONARIES", "the fort should count revolutionaries")
				check(_has("YOUR PARTNER IS AT THE WELL"), "before the first shot, his partner: %s" % [_lines()])
				game.last_gunfire = game.clock   # (staged: the first shot)
				shot_at = frame
			if frame == shot_at + 4 and shot_at > 0:
				check(not _has("YOUR PARTNER IS AT THE WELL"), "the partner line should give way to the count: %s" % [_lines()])
				check(_has("¡ALTO O LO MATO!"), "the guard should be counting: %s" % [_lines()])
				var n: int = game.director.waves.size()
				check(_has("MORE COMING") and _has("%d BANDS LEFT" % n), "the next band, and %d left: %s" % [n, _lines()])
				return _next()
		"silencio":
			step = "gold"
			if frame == 5:
				var sb: Strongbox = game.strongbox
				check(_has("THE TRUCE HOLDS") and _has("THE GOLD: IN THE OUTLAWS' LIVERY"), "the truce and the gold at home: %s" % [_lines()])
				sb.take(game.player)
				check(_has("GET THE GOLD TO YOUR HORSE"), "the gold in his arms: %s" % [_lines()])
				sb.holder = null   # (staged: set down out in the snow, well away from home)
				sb.global_position = sb.horse
				check(_has("THE GOLD: LYING IN THE SNOW"), "the gold set down: %s" % [_lines()])
				game.start_war("(staged)")
				check(_has("THE TRUCE IS BROKEN"), "the truce broken: %s" % [_lines()])
				return _next()
		"funeral":
			step = "funeral"
			if frame == 5:
				check(game.level.get("foe_count", "") == "MOURNERS", "the funeral should count mourners")
				var d: Director = game.director
				var g: String = d.camps.keys()[0]
				d._send_runner(g, d.camps[g])
				var r: Array = d.runners()
				check(r.size() == 1 and r[0][1] == "RUNNER: %s" % g.to_upper(), "an arrow on the runner: %s" % [r])
				check(d.help_coming().is_empty(), "no help coming before he's home: %s" % [d.help_coming()])
				d.runner_home(d.camps[g]["runner"])
				check(d.runners().is_empty(), "home, he's no one to stop")
				check(_has("HELP FOR THE %s" % g.to_upper()), "the help's countdown: %s" % [_lines()])
				return _next()
	return false


func _next() -> bool:
	at += 1
	if at < LEVELS.size():
		_load()
		return false
	print("goals test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
