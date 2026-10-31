extends SceneTree
## Fear and covering fire should stay local. The invulnerable hero stands on main
## street shooting whoever he can see (the --bot autopilot). Bandits out of sight
## of the shooting must not cower, dive for cover or blaze away at walls; the ones
## coming from further off should get there instead of being stopped by every shot:
##   godot --headless --path . --fixed-fps 60 -s tests/test_locality.gd

const HERO := Vector2(26.0, 31.4)
const LENGTH := 40.0
const FAR := 250.0   # bandits further than this when the fight finds them are "coming from afar"

var game: Node
var frame := 0
var failures := 0
var clock := 0.0
var joined := {}    # enemy -> [time he joined the fight, distance then]
var arrived := {}   # enemy -> seconds from joining to first seeing the hero
var shots := 0
var wall_shots := 0  # bandit shots with a wall right in front of the muzzle


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
		game.begin()
		game.player.global_position = Iso.to_screen(HERO)
		game.player.hp = 1000000
		game.player.weapons["colt"].reserve = 1000
		game._args["bot"] = "1"
	if frame <= 3:
		return false
	clock += delta
	for e in game.enemies:
		if not e.alive:
			continue
		if e.st == Enemy.St.COMBAT and not joined.has(e):
			joined[e] = [clock, e.global_position.distance_to(game.player.global_position)]
		if e.since_shot < delta * 0.5:
			shots += 1
			if not game.ray(e.global_position, e.global_position + e.facing * 40.0, Iso.LAYER_WALL).is_empty():
				wall_shots += 1
		if joined.has(e) and e.sees_player and not arrived.has(e):
			arrived[e] = clock - joined[e][0]
	if clock < LENGTH:
		return false
	var far := 0
	var far_arrived: Array[float] = []
	for e in joined:
		if joined[e][1] > FAR:
			far += 1
			if arrived.has(e):
				far_arrived.append(arrived[e])
	far_arrived.sort()
	var median: float = far_arrived[far_arrived.size() / 2] if not far_arrived.is_empty() else -1.0
	var s: Dictionary = game.stats
	var dead := 0
	for e in game.enemies:
		dead += 0 if e.alive else 1
	print("joined %d (%d from afar, %d of them reached the fight, median %.1f s), %d dead" % [
		joined.size(), far, far_arrived.size(), median, dead])
	print("frights out of sight: %d, bandit shots into walls: %d of %d (AI events %s)" % [
		s.get("reacts out of sight", 0), wall_shots, shots, s])
	check(s.get("reacts out of sight", 0) <= 2, "%d bandits took fright at a fight they couldn't see" % s.get("reacts out of sight", 0))
	check(wall_shots <= 3, "%d shots into walls" % wall_shots)
	check(far == 0 or far_arrived.size() * 2 >= far, "only %d of %d distant bandits reached the fight" % [far_arrived.size(), far])
	print("locality test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
