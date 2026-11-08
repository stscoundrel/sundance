extends SceneTree
## Mourners. Two bandits are buried on boot hill at once (the rest held still, the
## hero off the map). Nobody in black is about until then; once the town is quiet
## they come out, stand at the fresh graves, and go home and in again. A shot while
## one of them is weeping sends her running and frees her grave for another visit;
## in the end every fresh grave is mourned:
##   godot --headless --path . --fixed-fps 60 -s tests/test_mourners.gd

const QUIET := 5.0
const LIMIT := 300.0

var game: Node
var frame := 0
var failures := 0
var clock := 0.0
var mourners: Array[Civilian] = []
var stages := {}
var scared: Civilian


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3)
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
		game.quiet_after = QUIET
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		game.player.hp = 1000000
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		for c in game.civilians:
			if c.mourner:
				mourners.append(c)
			elif c.undertaker:
				c.process_mode = Node.PROCESS_MODE_DISABLED   # we do the burying here
		check(mourners.size() >= 2, "the town needs mourners (%d)" % mourners.size())
	if frame <= 3:
		return false
	clock += delta
	# before anyone is buried, nobody comes out in black, quiet or not
	if clock > QUIET + 3.0 and clock - delta <= QUIET + 3.0:
		for m in mourners:
			check(m.gone() and not m.visible, "a mourner came out with nobody to mourn")
		for i in 2:
			var e: Enemy = game.enemies[i]
			e.process_mode = Node.PROCESS_MODE_INHERIT
			e.die(Vector2.RIGHT)
			game.bury(e, game.grave_spot())
		for e in game.enemies:
			if e.alive:
				e.st = Enemy.St.GUARD   # whoever saw it keeps it to himself
		stages["buried"] = clock
	if not stages.has("buried"):
		return false
	for m in mourners:
		if m.st == Civilian.St.MOURN:
			if not stages.has("mourning"):
				stages["mourning"] = clock
				var near := INF
				for g in game.to_mourn:
					near = minf(near, g["at"].distance_to(m.global_position))
				check(near < 30.0, "she mourns %.0f px from the nearest grave" % near)
			# a few seconds in, gunfire nearby
			if scared == null and clock - stages["mourning"] > 3.0:
				scared = m
				game.make_noise(m.global_position + Vector2(60, 0), 380.0, "enemy_shot", null)
	if scared and not stages.has("fled"):
		if scared.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE]:
			stages["fled"] = clock
			check(scared.mourning.is_empty(), "she ran but kept her claim on the grave")
	var done := 0
	for g in game.to_mourn:
		done += 1 if g["done"] else 0
	var home := true
	for m in mourners:
		home = home and m.gone()
	if (done < game.to_mourn.size() or not home) and clock < LIMIT:
		return false
	print("after %.0f s: %d of %d graves mourned; stages %s; %s" % [clock, done, game.to_mourn.size(), stages, game.stats])
	check(stages.has("mourning") and stages["mourning"] > stages["buried"] + QUIET * 0.8, "she came out before the town was quiet")
	check(stages.has("fled"), "the shot didn't send her running")
	check(done == game.to_mourn.size(), "every fresh grave should be mourned")
	check(home, "the mourners should all go home in the end")
	print("mourners test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
