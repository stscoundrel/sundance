extends SceneTree
## The gang's alarm. A fight at the east end of town (the stranger off the map; the
## shots and the deaths staged by hand); the men at the west end can't see or hear
## it close, and answer it by stages:
##   news     - a man running from the fight goes to his comrades, not just away,
##              and when he gets there they know.
##   quiet    - a few shots far off: nobody stirs.
##   uneasy   - a long fight: the far men stop their rounds and stand on edge.
##   scouts   - longer: each post sends a pair to look (a man alone stays put);
##              they head for the fight. A scout cut down raises it further.
##   fallback - a third of the gang down: the far men fall back to the holdout
##              furthest from the fight and dig in there.
##   godot --headless --path . --fixed-fps 60 -s tests/test_alarm.gd

const FIGHT := Vector2(57.0, 31.0)   # east end of main street

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var far: Array = []
var patrollers: Array = []
var scouts: Array = []
var fleer: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("no_downed", true)
	seed(12)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _shots(n: int) -> void:
	for i in n:
		game.make_noise(Iso.to_screen(FIGHT), 380.0, "shot", game.player)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.alerted_once = true
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		var at := Iso.to_screen(FIGHT)
		far = game.enemies.filter(func(e): return e.revealed and e.global_position.distance_to(at) > 600.0)
		patrollers = far.filter(func(e): return e.patrol.size() > 1)
		print("%d far men (%d on rounds), %d near the fight" % [far.size(), patrollers.size(), game.enemies.size() - far.size()])
		_news()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("alarm test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _news() -> void:
	step = "news"
	# a bandit off on his own between the fight and the others, running from it
	var west: Array = far.filter(func(e): return e.global_position.x < Iso.to_screen(Vector2(20, 31)).x)
	fleer = far.filter(func(e): return not e in west)[0]
	var group: Enemy = west[0]
	fleer.global_position = group.global_position + Vector2(260, 0)
	if not game.is_free(fleer.global_position):
		fleer.global_position = game.free_point_near(fleer.global_position, 40.0)
	fleer.enter_combat(fleer.global_position + Vector2(200, 0), false, false)
	fleer.threat = fleer.global_position + Vector2(200, 0)
	fleer.reaction = ""
	fleer.start_reaction("flee")
	check(fleer.bearing_news, "he didn't run to his comrades")
	queue = [[25.0, func():
		check(game.stats.get("news brought", 0) == 1, "the news never got there")
		check(game.enemies.any(func(e): return e.alarm_role == "uneasy"), "the men he ran to didn't take it in")
		print("news: alarm %.0f" % game.alarm)
		# start the rest from a clean slate
		game.alarm = 0.0
		for e in game.enemies:
			e.alarm_role = ""
		far.erase(fleer)
		far.erase(group)
		_quiet()]]


func _quiet() -> void:
	step = "quiet"
	_shots(5)
	queue.append([2.0, func():
		check(far.all(func(e): return e.alarm_role == ""), "a few far shots stirred the far side")
		_uneasy()])


func _uneasy() -> void:
	step = "uneasy"
	_shots(10)
	queue.append([2.0, func():
		var uneasy: int = far.filter(func(e): return e.alarm_role == "uneasy").size()
		print("uneasy: %d of %d far men (alarm %.0f)" % [uneasy, far.size(), game.alarm])
		check(uneasy >= far.size() - 2, "the far side should be on edge (%d of %d)" % [uneasy, far.size()])
		check(patrollers.all(func(e): return e.patrol.size() <= 1), "someone's still on his rounds")
		_scouts()])


func _scouts() -> void:
	step = "scouts"
	_shots(25)
	queue.append([2.0, func():
		scouts = game.enemies.filter(func(e): return e.alarm_role == "scout")
		print("scouts sent: %s" % [scouts.map(func(e): return e.kind)])
		check(scouts.size() >= 2 and scouts.size() % 2 == 0 or scouts.size() >= 3, "no pairs sent (%d)" % scouts.size())
		for s in scouts:
			s.set_meta("d0", s.global_position.distance_to(Iso.to_screen(FIGHT)))])
	queue.append([10.0, func():
		for s in scouts:
			check(s.global_position.distance_to(Iso.to_screen(FIGHT)) < s.get_meta("d0") - 60.0, "a scout isn't heading for the fight")
		var before: float = game.alarm
		scouts[0].die(Vector2.RIGHT, game.player)
		check(game.alarm >= before + 14.0, "a lost scout should raise it (%.0f -> %.0f)" % [before, game.alarm])
		_fallback()])


func _fallback() -> void:
	step = "fallback"
	var at := Iso.to_screen(FIGHT)
	var near: Array = game.enemies.filter(func(e): return e.alive and not e in far and not e in scouts)
	near.sort_custom(func(a, b): return a.global_position.distance_to(at) < b.global_position.distance_to(at))
	for e in near.slice(0, 8):
		e.die(Vector2.RIGHT, game.player)
	queue.append([1.0, func():
		print("holdout: %s" % game.holdout.get("name", "-"))
		check(game.holdout.get("name", "") == "cantina", "they should fall back to the cantina, furthest from the fight (%s)" %
			game.holdout.get("name", "-"))
		check(game.stats.get("falls back", 0) >= 3, "too few fell back (%d)" % game.stats.get("falls back", 0))])
	queue.append([45.0, func():
		var back: Array = game.enemies.filter(func(e): return e.alive and e.alarm_role == "fortified")
		var there: int = back.filter(func(e): return e.global_position.distance_to(game.holdout["at"]) < 170.0).size()
		print("at the holdout: %d of %d who fell back" % [there, back.size()])
		check(back.all(func(e): return e.home.distance_to(game.holdout["at"]) < 170.0), "someone fell back somewhere else")
		# (the latest to fall back are still on their way)
		check(there >= back.size() * 0.7, "too few got there (%d of %d)" % [there, back.size()])])
