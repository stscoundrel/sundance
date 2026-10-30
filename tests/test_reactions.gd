extends SceneTree
## Rattles every bandit with near misses and checks that their reactions are held
## long enough to be seen:  godot --headless --path . -s tests/test_reactions.gd

const MIN_HOLD := {"point": 1.5, "flinch": 1.0, "cower": 2.0}

var game: Node
var frame := 0
var current := {}     # enemy -> [reaction, start time]
var held := {}        # reaction -> shortest hold seen
var counts := {}
var cower_then_hide := 0
var failures := 0
var now := 0.0


func _initialize() -> void:
	seed(7)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(delta: float) -> bool:
	frame += 1
	now += delta
	if frame == 3:
		game.begin()
	if frame in [5, 300, 600]:
		for e in game.enemies:
			e.fear_cd = 0.0
			e.near_miss(e.global_position + Vector2(40, 10))
	for e in game.enemies:
		var r: String = e.reaction
		var prev: Array = current.get(e, ["", 0.0])
		if r != prev[0]:
			if prev[0] != "":
				var d: float = now - prev[1]
				held[prev[0]] = min(held.get(prev[0], 99.0), d)
				if prev[0] == "cower" and r == "hide":
					cower_then_hide += 1
			if r != "":
				counts[r] = counts.get(r, 0) + 1
			current[e] = [r, now]
	if frame < 1100:
		return false
	print("reactions: ", counts)
	print("shortest holds: ", held)
	for k in MIN_HOLD:
		if held.has(k) and held[k] < MIN_HOLD[k] - 0.05:
			failures += 1
			print("FAIL: %s held only %.2fs" % [k, held[k]])
	if counts.size() < 3:
		failures += 1
		print("FAIL: expected a mix of reactions")
	if counts.has("cower") and cower_then_hide == 0:
		failures += 1
		print("FAIL: cowering bandits never went for cover")
	print("reactions test: ", "OK" if failures == 0 else "%d failures" % failures)
	Engine.time_scale = 1.0
	return true
