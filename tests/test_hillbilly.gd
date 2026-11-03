extends SceneTree
## A hillbilly with his sawn-off: one bandit at a time in the open against an
## invulnerable hero. He has to close in to scattergun range and let fly; a cowboy,
## happy to trade shots from further out, is the yardstick. And a pistolero who
## drew the rare sawn-off from his loadouts fights at its range, not a Colt's:
##   godot --headless --path . --fixed-fps 60 -s tests/test_hillbilly.gd

const HERO := Vector2(26.0, 31.4)
const START := Vector2(36.0, 31.4)
const ROUND := 20.0
const KINDS := ["hillbilly", "cowboy"]

var game: Node
var frame := 0
var failures := 0
var who: Enemy
var round_i := -1
var round_t := 0.0
var results := {}
var r := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _start_round() -> void:
	round_i += 1
	round_t = 0.0
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	who = null
	for e in game.enemies:
		if e.kind == KINDS[round_i] and e.alive and who == null:
			who = e
	who.process_mode = Node.PROCESS_MODE_INHERIT
	who.global_position = Iso.to_screen(START)
	who.hp = 1000
	who.enter_combat(game.player.global_position, true, false)
	r = {"shots": 0, "closest": 1e9, "shot_from": 0.0}


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(HERO)
		game.player.hp = 1000000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		_sawn_off_pistolero()
		_start_round()
	if frame <= 3:
		return false
	round_t += delta
	var d: float = who.global_position.distance_to(game.player.global_position)
	if who.since_shot < delta * 0.5:
		r["shots"] += 1
		r["shot_from"] += d
	r["closest"] = minf(r["closest"], d)
	if round_t < ROUND:
		return false
	var mean: float = r["shot_from"] / maxf(r["shots"], 1)
	print("%-10s %-8s %d shots from %.0f px on average, closest %.0f px" % [who.kind, who.weapon.kind, r["shots"], mean, r["closest"]])
	results[who.kind] = {"shots": r["shots"], "mean": mean}
	if round_i + 1 < KINDS.size():
		_start_round()
		return false
	var h: Dictionary = results["hillbilly"]
	var c: Dictionary = results["cowboy"]
	check(h["shots"] >= 3, "the hillbilly hardly fired (%d)" % h["shots"])
	check(h["mean"] < Weapon.DATA["sawnoff"]["range"], "the hillbilly shot from beyond his sawn-off's reach (%.0f px)" % h["mean"])
	check(h["mean"] < c["mean"], "the hillbilly should fight closer than a cowboy (%.0f vs %.0f px)" % [h["mean"], c["mean"]])
	print("hillbilly test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


## The loadout option brings its own knobs: a pistolero with the sawn-off keeps a
## shotgun's distance.
func _sawn_off_pistolero() -> void:
	var p: Enemy = null
	for e in game.enemies:
		if e.kind == "pistolero" and p == null:
			p = e
	var colt_range: Array = game.enemy_type("pistolero")["range"]
	var options: Array = p.tdata["loadouts"]
	p.tdata["loadouts"] = options.filter(func(o): return o["guns"] == ["sawnoff"])
	var guns: Array = p._pick_loadout()
	check(guns == ["sawnoff"], "picked %s" % [guns])
	check(p.tdata["range"][1] < colt_range[1], "a sawn-off pistolero keeps a Colt's range (%s)" % [p.tdata["range"]])
	check(p.tdata["fires_on_move"], "a sawn-off pistolero should fire on the move")
