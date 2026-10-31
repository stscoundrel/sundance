extends SceneTree
## The gunsmith. Seven bandits nearest his shop go down (the rest held still, the
## undertakers too, the hero off the map); five are buried at once, two are left
## lying, and one empty rifle lies where a living man threw it down. Once the town
## is quiet the gunsmith gathers up the guns he may have (never one under a body
## still waiting on the undertaker), up to five a trip, and the cartridges lying
## with them go too. On his second trip he's shot: his armful spills round him,
## cartridges and all:
##   godot --headless --path . --fixed-fps 60 -s tests/test_gunsmith.gd

const QUIET := 5.0
const LIMIT := 240.0

var game: Node
var frame := 0
var failures := 0
var clock := 0.0
var smith: Civilian
var unburied: Array[Enemy] = []
var fair: Array[Dictionary] = []     # the guns he may have
var kept: Array[Dictionary] = []     # the ones under unburied men
var most := 0
var first_out := -1.0
var trips := 0
var was_carrying := 0
var spilled := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
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
		_set_up()
	if frame <= 3:
		return false
	clock += delta
	if smith.st == Civilian.St.TO_GUN and first_out < 0.0:
		first_out = clock
	most = maxi(most, smith.carried.size())
	if smith.carried.is_empty() and was_carrying > 0:
		trips += 1
	was_carrying = smith.carried.size()
	for g in kept:
		check(game.loose_guns.has(g), "he took a gun from under a man still lying there")
	# on his second trip home, he's shot
	if trips == 1 and smith.st == Civilian.St.HAUL and not spilled and smith.carried.size() > 0:
		spilled = true
		var n := smith.carried.size()
		var with_ammo := smith.carried.filter(func(c): return c["ammo_kind"] != "").size()
		var at := smith.global_position
		var before: int = game.loose_guns.size()
		smith.die(Vector2.RIGHT)
		check(game.loose_guns.size() == before + n, "he carried %d but %d fell" % [n, game.loose_guns.size() - before])
		var near := 0
		for g in game.loose_guns:
			near += 1 if g["at"].distance_to(at) < 24.0 else 0
		check(near >= n, "his guns should spill round him (%d of %d)" % [near, n])
		var ammo := 0
		for g in game.loose_guns:
			ammo += 1 if g["ammo"] != null and g["at"].distance_to(at) < 24.0 else 0
		check(ammo == with_ammo, "the cartridges he carried should spill too (%d of %d)" % [ammo, with_ammo])
		print("shot carrying %d guns (%d with cartridges)" % [n, with_ammo])
	if not spilled and clock < LIMIT:
		return false
	print("after %.0f s: first out at %.0f s, at most %d in his arms, %d trips; %s" % [clock, first_out, most, trips, game.stats])
	check(first_out >= QUIET, "he went out before the town was quiet")
	check(most >= 2 and most <= 5, "he should carry a few, and never more than five a trip (%d)" % most)
	check(game.stats.get("guns stored", 0) >= 2, "his first armful should reach the shop")
	check(spilled, "he never set out on a second trip")
	for g in fair:
		check(not g["ammo"] or not is_instance_valid(g["ammo"]) or game.loose_guns.has(g),
			"cartridges left lying by a gun he took")
	print("gunsmith test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


func _set_up() -> void:
	game.begin()
	game.quiet_after = QUIET
	game.player.global_position = Iso.to_screen(Vector2(-40, -40))
	game.player.hp = 1000000
	for c in game.civilians:
		if c.gunsmith:
			smith = c
		elif c.undertaker:
			c.process_mode = Node.PROCESS_MODE_DISABLED   # we bury them here
	var near: Array = []
	for e in game.enemies:
		near.append([e.global_position.distance_to(smith.global_position), e])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in 7:
		var e: Enemy = near[i][1]
		e.process_mode = Node.PROCESS_MODE_INHERIT
		e.die(Vector2.RIGHT)
		if i < 2:
			unburied.append(e)
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED if e.alive else e.process_mode
		if e.alive:
			e.st = Enemy.St.GUARD   # nobody makes a fuss
	await process_frame   # the cartridges go down a frame later
	for i in range(2, 7):
		game.bury(near[i][1], game.grave_spot())
	var thrown: Dictionary = game._place_gun("rifle", Iso.to_screen(Vector2(40.0, 31.0)), 0.0)
	for g in game.loose_guns:
		if g["under"] in unburied:
			kept.append(g)
		else:
			fair.append(g)
	print("%d guns he may have, %d under unburied men (thrown rifle at %s)" % [fair.size(), kept.size(), Iso.to_grid(thrown["at"])])
