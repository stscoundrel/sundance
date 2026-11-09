extends SceneTree
## A man at his post has his habits (Enemy._habits). In San Miguel, the rest of the
## gang held still:
##   smoke   - he lights up: ten seconds of patting pockets and a match, his sight
##             cut short and narrow; then he's smoking it, his eyes his own again.
##   nature  - he goes off to a wall a short way from his post, faces it, his sight
##             cut, for a quarter of a minute or so, then back to his post.
##   missed  - one who never comes back (the knife found him at the wall): his mate of
##             the post notices he's been gone too long and goes to look.
##   action  - in a fight's town nobody goes off for a call of nature.
##   godot --headless --path . --fixed-fps 60 -s tests/test_habits.gd

const SCENES := ["smoke", "nature", "missed", "action"]

var game: Node
var frame := 0
var failures := 0
var scene_i := -1
var t := 0.0
var man: Enemy
var mate: Enemy
var used: Array[Enemy] = []
var cut := 1.0
var lit := false
var at_wall := false
var posed := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(9)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [SCENES[scene_i], msg])


## A guard at his post with a mate of the post beside him (or just a guard).
func _pair(with_mate: bool) -> void:
	man = null
	mate = null
	for e in game.enemies:
		if e in used or not e.revealed or e.st != Enemy.St.GUARD or e.posted() or not e.has_anim(e._upper_key("smoke")):
			continue
		if not with_mate:
			man = e
			break
		for m in game.enemies:
			if m != e and not m in used and m.revealed and m.st == Enemy.St.GUARD and m.home.distance_to(e.home) < Enemy.PESO_MATES:
				man = e
				mate = m
				break
		if man:
			break
	check(man != null, "no guard to try it on")
	used.append(man)
	man.process_mode = Node.PROCESS_MODE_INHERIT
	if mate:
		used.append(mate)
		mate.process_mode = Node.PROCESS_MODE_INHERIT
		mate.smoke_at = INF
		mate.nature_at = INF


func _next() -> void:
	scene_i += 1
	t = 0.0
	cut = 1.0
	lit = false
	at_wall = false
	posed = false
	for e in used:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	if scene_i >= SCENES.size():
		print("habits: %s" % {"smokes": game.stats.get("smokes", 0), "calls": game.stats.get("calls of nature", 0)})
		print("habits test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return
	match SCENES[scene_i]:
		"smoke":
			_pair(false)
			man.smoke_at = game.clock
			man.nature_at = INF
		"nature":
			_pair(false)
			man.nature_at = game.clock
			man.smoke_at = INF
		"missed":
			_pair(true)
			man.nature_at = game.clock
			man.smoke_at = INF
		"action":
			_pair(false)
			game.level_entry["action"] = true
			man.nature_at = game.clock
			man.smoke_at = INF


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000
		game.player.global_position = Iso.to_screen(Vector2(1.0, 62.0))   # out of everyone's sight
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.smoke_at = INF
			e.nature_at = INF
	if frame <= 3:
		return false
	if scene_i < 0:
		if game.quiet_for() > 21.0:   # (a quiet town: the habits wait for it)
			_next()
		return false
	if scene_i >= SCENES.size():
		return false
	t += delta
	match SCENES[scene_i]:
		"smoke":
			if man.smoke_t >= 0.0:
				lit = true
				cut = minf(cut, man.view_range() / Enemy.VIEW)
				posed = posed or man.pose == "smoke"
			elif lit:
				check(cut < 0.4, "his sight was %.2f of itself, lighting up" % cut)
				check(posed, "not in the smoke pose")
				check(t >= Enemy.SMOKE_LIGHT - 0.1, "lit in %.1f s" % t)
				check(man.puff_until > game.clock and man.eyes() == Vector2.ONE, "not smoking it, eyes his own")
				_next()
			elif t > 3.0:
				check(false, "he never lit up")
				_next()
		"nature":
			if man.st == Enemy.St.ERRAND and man.errand == "nature" and man.errand_t > 0.0:
				at_wall = true
				cut = minf(cut, man.view_range() / Enemy.VIEW)
				posed = posed or man.pose == "relieve"
				var d := man.global_position.distance_to(man.home)
				check(d > Enemy.NATURE_FAR.x * 0.6 and d < Enemy.NATURE_FAR.y + 10.0, "%.0f px from his post" % d)
				check(man.facing.dot(man.errand_face) > 0.8, "not facing the wall")
				check(man.unaware(), "not unaware at it")
			elif at_wall and man.st == Enemy.St.GUARD and man.global_position.distance_to(man.home) < 8.0:
				check(cut < 0.35, "his sight was %.2f of itself at it" % cut)
				check(posed, "not in the pose")
				_next()
			elif t > 50.0:
				check(false, "no call of nature, and back (st %d, at the wall %s)" % [man.st, at_wall])
				_next()
		"missed":
			if man.alive and man.st == Enemy.St.ERRAND and man.errand_t > 0.0:
				check(mate.waiting_on == man, "his mate isn't keeping count")
				man.silent_death = true
				man.die(Vector2.RIGHT, game.player, "death_slump")   # (the knife's quiet takedown)
				man.killed_with = "knife"
				man.errand_since -= Enemy.NATURE_MISSED - 3.0   # (he's been gone a while already)
			elif not man.alive:
				if mate.st == Enemy.St.INVESTIGATE:
					check(mate.global_position.distance_to(mate.home) > 4.0 or mate.path.size() > 0, "he isn't going to look")
					_next()
				elif t > 30.0:
					check(false, "his mate never went to look (st %d)" % mate.st)
					_next()
			elif t > 30.0:
				check(false, "no call of nature to stage it (st %d, at ease %s, mate waiting %s)" % [man.st, man._at_ease(), mate.waiting_on])
				_next()
		"action":
			check(man.st != Enemy.St.ERRAND, "off for a call of nature in a fight's town")
			if t > 2.0:
				game.level_entry.erase("action")
				_next()
	return false
