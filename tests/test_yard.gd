extends SceneTree
## A bare map (no streets, townsfolk, reserve, boot hill or holdouts), shuffled to
## five: it loads, the gang is dealt, the posse rides on guard posts for want of
## streets, and the autopilot fights it out to a win with nothing missing.
##   godot --headless --path . --fixed-fps 60 -s tests/test_yard.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var posse_seen := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard_5")
	seed(16)
	game = load("res://scenes/main.tscn").instantiate()
	game._args["bot"] = "1"
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		check(game.level["name"] == "Test yard" and game.size == 24, "the yard didn't load")
		check(game.enemies.size() == 5, "%d bandits for five" % game.enemies.size())
		check(game.civilians.is_empty() and not game.den.has("sprite"), "townsfolk or a reserve in the yard")
		game.begin()
		game.player.hp = 100000
	if frame <= 3:
		return false
	t += delta
	if game.posse:
		posse_seen = true
		check(game.posse.points.size() >= 5, "the posse has nowhere to ride (%d points)" % game.posse.points.size())
	if game.state == "won" or t > 180.0:
		print("after %.0f s: %s, %d left; posse %s; stats %s" % [t, game.state, game.alive_enemies(), posse_seen, game.stats])
		check(game.state == "won", "the autopilot didn't win the yard")
		check(posse_seen, "no posse formed")
		print("yard test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	return false
