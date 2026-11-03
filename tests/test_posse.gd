extends SceneTree
## The last five bandits, scattered over town, band together and ride it as a
## group. The hero is kept well out of the way, except for a few seconds when he
## shows himself in front of them and vanishes again. Checks they gather in time,
## keep together on the move, cover most of the streets, and fall back in after
## the fight:
##   godot --headless --path . --fixed-fps 60 -s tests/test_posse.gd

const KEEP := [0, 6, 9, 12, 15, 17, 20, 23]   # placements left alive: spread over the map
const LENGTH := 300.0

var game: Node
var frame := 0
var failures := 0
var clock := 0.0
var gathered_at := -1.0
var samples := 0
var together := 0
var trail: Array = []   # the leader's route, for the record
const SHOW_AT := 90.0      # the hero shows himself for 3 s
var fought := false
var regrouped_at := -1.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_reserve", true)   # (the posse's own business: the saloon stays indoors)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 2)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))   # off the map, unseen
		game.player.hp = 1000000
		var keep: Array[Enemy] = []
		for i in game.enemies.size():
			if i in KEEP:
				keep.append(game.enemies[i])
			else:
				game.enemies[i].queue_free()
		game.enemies = keep
		# the eighth goes down, which leaves seven: that forms the posse
		keep[7].die(Vector2.RIGHT)
		check(game.posse != null and game.posse.members.size() == 7, "seven left should form a posse")
		if game.posse == null:
			quit(1)
			return true
		var spread := 0.0
		for e in game.posse.members:
			spread = max(spread, e.global_position.distance_to(game.posse.leader.global_position))
		print("posse of %d, %d route points, led by the %s, furthest man %.0f px off" % [
			game.posse.members.size(), game.posse.points.size(), game.posse.leader.kind, spread])
	if frame <= 3:
		return false
	clock += delta
	var p: Posse = game.posse
	if clock >= SHOW_AT and clock - delta < SHOW_AT:
		# in the open, in front of one of them, where he can see him
		var placed := false
		for r in [120.0, 100.0, 80.0, 60.0]:
			for e in p.members:
				var at: Vector2 = e.global_position + e.facing * r
				if not placed and game.is_free(at) and game.line_of_sight(e.global_position, at, false):
					game.player.global_position = at
					placed = true
	if clock >= SHOW_AT + 3.0 and clock - delta < SHOW_AT + 3.0:
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
	var all_posse := true
	for e in p.members:
		if e.alive:
			fought = fought or (e.st == Enemy.St.COMBAT and clock >= SHOW_AT)
			all_posse = all_posse and e.st == Enemy.St.POSSE
	if fought and all_posse and regrouped_at < 0.0:
		regrouped_at = clock
	if gathered_at < 0.0 and not p.gathering:
		gathered_at = clock
	var fighting := clock > SHOW_AT and regrouped_at < 0.0
	if not p.gathering and not fighting and int(clock * 2.0) != int((clock - delta) * 2.0):
		samples += 1
		var ok := true
		for e in p.members:
			if e.alive and e.global_position.distance_to(p.leader.global_position) > 140.0:
				ok = false
		together += 1 if ok else 0
		if int(clock) % 10 == 0 and int(clock * 2.0) % 2 == 0:
			trail.append(Iso.to_grid(p.leader.global_position).round())
	if clock < LENGTH:
		return false
	var states := {}
	for e in p.members:
		states[Enemy.St.keys()[e.st]] = states.get(Enemy.St.keys()[e.st], 0) + 1
	var share := float(p.visited.size()) / p.points.size()
	print("gathered after %.1f s; together %d%% of the time on the move; %d of %d route points seen (%.0f%%); states %s" % [
		gathered_at, 100 * together / maxi(samples, 1), p.visited.size(), p.points.size(), share * 100.0, states])
	print("fought: %s, all back in the posse %.1f s after he showed himself" % [fought, regrouped_at - SHOW_AT])
	print("leader's trail (every 10 s): ", trail)
	check(gathered_at > 0.0 and gathered_at <= 31.0, "posse never gathered (%.1f)" % gathered_at)
	check(together >= samples * 0.8, "posse strung out: together only %d of %d samples" % [together, samples])
	check(fought, "the posse never went for him when he showed himself")
	check(regrouped_at > 0.0, "the posse never re-formed after the fight")
	check(share >= 0.75, "posse saw only %.0f%% of the town" % (share * 100.0))
	print("posse test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
