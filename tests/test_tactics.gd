extends SceneTree
## A standing firefight against an invulnerable hero. Checks the bandits shoot back
## when nothing stops them, call for cover, take leaders' orders to lay down
## covering fire, and loose panic shots when they run. Then the hero vanishes, and
## the shooting must die down: little more than a harassing shot every few seconds
## once nobody has seen him for a while, and silence after that:
##   godot --headless --path . --fixed-fps 60 -s tests/test_tactics.gd

const QUIET_LIMIT := 4.5   # longest a free, sighted, armed bandit may hold fire

var game: Node
var frame := 0
var quiet := {}       # enemy -> seconds free to shoot without shooting
var worst := 0.0
var worst_who := ""
var shots := 0
var blocked_time := 0.0
const FIGHT := 25.0
const HIDE_AT := Vector2(1.0, 62.5)   # the far corner, out of everyone's sight
var resighted := 0
var hidden_shots := [0, 0, 0]          # shots 0-5 s, 5-12 s and 12-20 s after he vanished
var failures := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)   # bandit tactics only; townsfolk have their own test
	seed(11)
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
		game.player.global_position = Iso.to_screen(Vector2(26.0, 31.4))
		game.player.hp = 1000000
		for e in game.enemies:
			e.enter_combat(game.player.global_position, true, false)
	if frame == 60 * 8:
		# two of them break and run
		var n := 0
		for e in game.enemies:
			if e.alive and e.rank == 0 and n < 2:
				e.threat = game.player.global_position
				e.start_reaction("flee")
				n += 1
	var t: float = frame / 60.0
	if frame == int(FIGHT * 60):
		game.player.global_position = Iso.to_screen(HIDE_AT)
	if t > FIGHT:
		for e in game.enemies:
			if e.alive and e.since_shot < delta * 0.5:
				var after := t - FIGHT
				var w := 0 if after < 5.0 else (1 if after < 12.0 else 2)
				if after >= 5.0 and game.staleness() < game.FRESH:
					resighted += 1   # someone found him again: fair game
				else:
					hidden_shots[w] += 1
		if frame < int((FIGHT + 20.0) * 60):
			return false
		print("blind shots after he vanished: %d in 0-5 s, %d in 5-12 s, %d in 12-20 s (harassing shots %d, after a re-sighting %d)" % [
			hidden_shots[0], hidden_shots[1], hidden_shots[2], game.stats.get("harassing shot", 0), resighted])
		check(hidden_shots[0] <= 25, "%d shots in the first 5 s after he vanished: still a wall of fire" % hidden_shots[0])
		check(hidden_shots[1] <= 4, "%d shots 5-12 s after anyone saw him (expected the odd harassing shot)" % hidden_shots[1])
		check(hidden_shots[2] == 0, "%d shots more than 12 s after anyone saw him" % hidden_shots[2])
		print("tactics test: ", "OK" if failures == 0 else "%d failures" % failures)
		return true
	for e in game.enemies:
		if not e.alive:
			continue
		if e.since_shot < delta * 0.5:
			shots += 1
		# a deliberate move under comrades' covering fire is not idling
		var free: bool = e.st == Enemy.St.COMBAT and e.sees_player and e.reaction == "" and e.pending == "" and e.covered_t <= 0.0 \
			and e.pinned_t <= 0.0 and e.weapon.can_fire() and e.action_t <= 0.0 \
			and e.global_position.distance_to(game.player.global_position) < e.weapon.d["range"] * 0.8
		# a comrade in his line of fire is a good reason not to shoot
		var target: Vector2 = game.player.global_position if e.suppress_t <= 0.0 else e.suppress_at
		var blocked: bool = game.ally_in_line(e, e.global_position, target)
		if blocked:
			blocked_time += delta
		if free and not blocked:
			quiet[e] = quiet.get(e, 0.0) + delta
			if quiet[e] > worst:
				worst = quiet[e]
				worst_who = "%s #%d, speed %.0f, suppressing %s, covered %s, shot_cd %.1f, aim %.2f" % [e.kind,
					game.enemies.find(e), e.velocity.length(), e.suppress_t > 0.0, e.covered_t > 0.0, e.shot_cd, e.aim_t]
		if not free or e.since_shot < delta * 0.5:
			quiet[e] = 0.0
	if frame < int(FIGHT * 60) - 1:
		return false
	print("AI events: ", game.stats)
	print("bandit-seconds spent with a comrade in the line of fire: %.1f" % blocked_time)
	print("longest a free bandit held fire: %.1fs (%s)" % [worst, worst_who])
	check(worst <= QUIET_LIMIT, "a bandit free to shoot held fire for %.1fs" % worst)
	check(game.stats.get("calls for cover", 0) > 0, "nobody called for cover")
	check(game.stats.get("orders covering fire", 0) > 0, "no leader ordered covering fire")
	check(game.stats.get("panic shot", 0) > 0, "no panic shots from running bandits")
	return false
