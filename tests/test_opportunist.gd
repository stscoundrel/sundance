extends SceneTree
## A saloon girl is an opportunist: she shoots while the stranger's attention is
## elsewhere, and wavers (backs off, ducks, flinches) when he turns his gun her
## way. One bandit at a time in the open, the hero held still and invulnerable:
## first aiming straight at her, then looking away (wavers when she's come right up
## to him don't count: that's nerve too). A cowboy is the yardstick: he never wavers
## just for being aimed at:
##   godot --headless --path . --fixed-fps 60 -s tests/test_opportunist.gd

const HERO := Vector2(26.0, 31.4)
const START := Vector2(33.0, 31.4)
const PHASE := 40.0   # (long enough that the difference shows over the noise)
const KINDS := ["saloon_girl", "cowboy"]

var game: Node
var frame := 0
var failures := 0
var who: Enemy
var kind_i := -1
var t := 0.0
var r := {}
var results := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1)   # (6 of 8 seeds show it; 3 and 6 too close to call)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _next() -> void:
	kind_i += 1
	t = 0.0
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	who = null
	for e in game.enemies:
		if e.kind == KINDS[kind_i] and e.alive and who == null:
			who = e
	who.process_mode = Node.PROCESS_MODE_INHERIT
	who.global_position = Iso.to_screen(START)
	who.hp = 1000
	who.enter_combat(game.player.global_position, true, false)
	r = {"aimed": {"shots": 0, "wavers": 0}, "away": {"shots": 0, "wavers": 0}, "close": 0}
	who.game.stats.erase("wavers")


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(HERO)
		game.player.hp = 1000000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED   # stands where he is, looks where we say
		_next()
	if frame <= 3:
		return false
	t += delta
	var phase := "aimed" if t < PHASE else "away"
	var to: Vector2 = (who.global_position - game.player.global_position).normalized()
	game.player.facing = to if phase == "aimed" else -to
	if who.since_shot < delta * 0.5:
		r[phase]["shots"] += 1
	var w: int = game.stats.get("wavers", 0)
	if w > r["aimed"]["wavers"] + r["away"]["wavers"] + r["close"]:
		if phase == "away" and who.global_position.distance_to(game.player.global_position) < 70.0:
			r["close"] += 1   # (come up close to him, she loses her nerve whichever way he's looking)
		else:
			r[phase]["wavers"] += 1
	if t < PHASE * 2.0:
		return false
	results[who.kind] = r
	print("%-11s %-10s aimed at: %d shots, %d wavers | looked away: %d shots, %d wavers" % [who.kind, who.weapon.kind,
		r["aimed"]["shots"], r["aimed"]["wavers"], r["away"]["shots"], r["away"]["wavers"]])
	if kind_i + 1 < KINDS.size():
		_next()
		return false
	var g: Dictionary = results["saloon_girl"]
	var c: Dictionary = results["cowboy"]
	check(g["aimed"]["wavers"] >= 2, "she should waver when he aims at her (%d)" % g["aimed"]["wavers"])
	check(g["away"]["wavers"] == 0, "she wavered with his back turned (%d)" % g["away"]["wavers"])
	check(g["away"]["shots"] > g["aimed"]["shots"], "she should shoot more when he isn't looking (%d vs %d)" % [g["away"]["shots"], g["aimed"]["shots"]])
	check(c["aimed"]["wavers"] == 0, "the cowboy is no opportunist (%d wavers)" % c["aimed"]["wavers"])
	print("opportunist test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
