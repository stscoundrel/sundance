extends SceneTree
## Paso Esperanza's cargo (scripts/cargo.gd, the carriers in civilian.gd):
##   setup    - six carriers and their comandante; 40 loads to go, two replacements
##              waiting; three wagons, each with its team and its wagon; more in the
##              piles of each kind than the level asks for.
##   trips    - they carry, and the count goes up; the comandante shot, it goes on
##              rising just the same.
##   fright   - a shot close by sends a carrier to cover, and he's back at it soon
##              after; a shot further off doesn't trouble him.
##   drop     - a carrier shot with a load in his arms drops it where he falls (a pile
##              of one for the next man), and a replacement comes up from the wagons.
##   wagons   - a full wagon drives off, out of everyone's way.
##   away     - every load in: the carriers climb on the last wagon, and the stranger
##              getting to it wins the level.
##   lost     - every carrier dead, the replacements too: nobody left to carry them.
##   godot --headless --path . --fixed-fps 60 -s tests/test_cargo.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := "trips"
var mark := 0.0
var frightened: Civilian
var calm: Civilian
var dropped_at := Vector2.INF
var loaded_at_leader := 0
var round2 := false
var killed := 0


func _initialize() -> void:
	_start()


func _start() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "train")
	Engine.set_meta("no_waves", true)   # (the army's test_federales')
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	t = 0.0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _setup() -> void:
	step = "setup"
	var c: Cargo = game.cargo
	check(c != null, "no cargo")
	check(c.carriers.size() == 6 and c.leader != null, "%d carriers, leader %s" % [c.carriers.size(), c.leader])
	check(c.goal == 40 and c.spare == 2, "goal %d, spare %d" % [c.goal, c.spare])
	check(c.wagons.size() == 3, "%d wagons" % c.wagons.size())
	for w in c.wagons:
		check(w["recs"].size() == 2, "a wagon with %d pieces" % w["recs"].size())
	var caps := 0
	for w in c.wagons:
		caps += w["cap"]
	check(caps == 40, "the wagons hold %d" % caps)
	var have := {"case": 0, "rifles": 0, "mg": 0}
	for s in c.sources:
		have[s["kind"]] += s["count"]
	check(have["case"] >= 40 and have["rifles"] >= 16, "in the piles: %s" % [have])


func _working(cv: Civilian) -> bool:
	return cv.alive and cv.visible and cv.st in [Civilian.St.TO_LOAD, Civilian.St.LOAD, Civilian.St.TO_WAGON,
		Civilian.St.STOW, Civilian.St.IDLE]


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		if not round2:
			_setup()
		game.begin()
		game.player.hp = 100000
	if frame <= 3:
		return false
	t += delta
	if round2:
		return _lost()
	var c: Cargo = game.cargo
	match phase:
		"trips":
			step = "trips"
			if c.loaded >= 3:
				c.leader.die(Vector2.RIGHT, game.player)
				loaded_at_leader = c.loaded
				mark = t
				phase = "after leader"
			elif t > 90.0:
				check(false, "only %d loaded in 90 s" % c.loaded)
				return _finish()
		"after leader":
			if c.loaded >= loaded_at_leader + 3:
				phase = "fright"
				mark = t
			elif t - mark > 60.0:
				check(false, "the work stopped with the comandante dead (%d)" % c.loaded)
				return _finish()
		"fright":
			step = "fright"
			if frightened == null:
				for a in c.carriers:
					for b in c.carriers:
						if a != b and _working(a) and _working(b) and a.global_position.distance_to(b.global_position) > 220.0:
							frightened = a
							calm = b
				if frightened == null:
					return false
				game.make_noise(frightened.global_position + Vector2(30, 0), 600.0, "shot", game.player)
				mark = t
				return false
			if t - mark < 0.2:
				check(frightened.st in [Civilian.St.FLEE, Civilian.St.COWER], "not frightened: %s" % Civilian.St.keys()[frightened.st])
				check(_working(calm), "frightened from 220 px off: %s" % Civilian.St.keys()[calm.st])
				return false
			if _working(frightened) and frightened.st != Civilian.St.IDLE:
				phase = "drop"
				mark = t
			elif t - mark > 25.0:
				check(false, "never back at work: %s" % Civilian.St.keys()[frightened.st])
				phase = "drop"
		"drop":
			step = "drop"
			if dropped_at == Vector2.INF:
				for cv in c.carriers:
					if cv.alive and cv.visible and cv.load_kind != "" and cv.st == Civilian.St.TO_WAGON:
						var n := c.sources.size()
						dropped_at = cv.global_position
						cv.die(Vector2.RIGHT, null)
						check(c.sources.size() == n + 1 and c.sources[-1]["count"] == 1 and not c.sources[-1]["rec"].is_empty(),
							"nothing dropped where he fell")
						mark = t
						break
				return false
			if t - mark > 10.0:
				check(c.carriers_alive() == 6 and c.spare == 1 and c.carriers.size() == 7,
					"replaced? %d alive, %d spare, %d in all" % [c.carriers_alive(), c.spare, c.carriers.size()])
				phase = "wagons"
		"wagons":
			step = "wagons"
			if c.wagons[0]["gone"]:
				for rec in c.wagons[0]["recs"]:
					check(rec["body"] == null and not game.placed.has(rec), "a wagon gone, still in the way")
				phase = "away"
			elif t > 400.0:
				check(false, "the first wagon never left (%d loaded)" % c.loaded)
				return _finish()
		"away":
			step = "away"
			if c.done:
				if mark >= 0.0:
					mark = -t
				var aboard := 0
				for cv in c.carriers:
					if cv.alive and cv.boarded:
						aboard += 1
				if (aboard == c.carriers_alive() or t + mark > 60.0) and game.player.global_position.distance_to(c.wagon_at()) > 10.0:
					check(aboard == c.carriers_alive(), "%d of %d aboard" % [aboard, c.carriers_alive()])
					game.player.global_position = c.wagon_at()
				if game.state != "play":
					check(game.state == "won", "it ended %s" % game.state)
					check(c.loaded == 40 and not game.player.visible, "%d loaded, him visible %s" % [c.loaded, game.player.visible])
					round2 = true
					game.queue_free()
					_start()
			elif t > 600.0:
				check(false, "never all loaded (%d)" % c.loaded)
				return _finish()
	return false


func _lost() -> bool:
	step = "lost"
	var c: Cargo = game.cargo
	if t < 3.0:
		return false
	for cv in c.carriers:
		if cv.alive and cv.visible:
			cv.die(Vector2.RIGHT, null)
			killed += 1
	if game.state != "play":
		check(game.state == "lost" and killed == 8, "it ended %s after %d dead" % [game.state, killed])
		return _finish()
	if t > 60.0:
		check(false, "still %s with %d carriers dead" % [game.state, killed])
		return _finish()
	return false


func _finish() -> bool:
	print("cargo test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
