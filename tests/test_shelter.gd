extends SceneTree
## In from the squall (Enemy._think_shelter), in Silencio with the gangs at their
## posts and no war:
##   squall  - one comes down: each man makes up his own mind, and some (not all)
##             go in at the nearest door: gone from the street, unseen, no prints;
##             a fire lit in that house (Hearth: smoke out of a cabin's chimney).
##   warm    - one done by the stove comes out again and goes back to his post (or rounds).
##   shot    - shooting brings another out, not at once (5-10 s) but in the end, and
##             he heads for it.
##   breath  - everyone puffs in the cold (Breath on the stranger and the gang).
##   godot --headless --path . --fixed-fps 60 -s tests/test_shelter.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "squall"
var eligible := 0
var inside: Array[Enemy] = []
var warm_one: Enemy
var shot_one: Enemy
var shot_at := 0.0
var hearth_lit := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_alarm", true)
	seed(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _done() -> void:
	print("shelter: %s" % {"in": game.stats.get("shelters", 0), "of": eligible})
	print("shelter test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)


func _hearths() -> Array:
	var out := []
	for n in game.world.get_children():
		for c in n.get_children():
			if c is Hearth:
				out.append(c)
	return out


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000
		game.player.global_position = Iso.to_screen(Vector2(1.0, 62.0))   # (out of everyone's way)
		var sq: Array[Vector2] = [Vector2(game.clock + 1.0, game.clock + 1.0 + Snowfall.RISE + 40.0)]
		game.snowfall.squalls.assign(sq)
		for e in game.enemies:
			if e.can_be_lured():
				eligible += 1
	if frame <= 3:
		return false
	t += delta
	match step:
		"squall":
			for e in game.enemies:
				if e.indoors and not e in inside:
					inside.append(e)
					check(not e.visible and not e.cone.visible, "a man inside still shows")
					check(e.shelter_house["in"] > 0, "nobody in the house he went into")
			if t > 12.0:
				check(inside.size() > 0, "nobody went in out of the squall")
				check(inside.size() < eligible, "everyone went in (%d of %d)" % [inside.size(), eligible])
				var share := float(inside.size()) / eligible
				check(share > 0.15 and share < 0.75, "%d of %d went in" % [inside.size(), eligible])
				for h in _hearths():
					if h.warm >= 1.0 and h.house["chimney"] != Vector3.INF:
						hearth_lit = true
				check(hearth_lit, "no cabin with a fire going and smoke up the chimney")
				check(inside.size() >= 2, "need two inside to go on (%d)" % inside.size())
				if inside.size() < 2:
					_done()
					return false
				warm_one = inside[0]
				shot_one = inside[inside.size() - 1]
				warm_one.shelter_until = game.clock + 1.0   # (warm enough already)
				step = "warm"
				t = 0.0
		"warm":
			check(shot_one.indoors, "the other one came out with him")
			if not warm_one.indoors and (warm_one.st == Enemy.St.PATROL \
					or (warm_one.st == Enemy.St.GUARD and warm_one.global_position.distance_to(warm_one.home) < 8.0)):
				step = "shot"
				t = 0.0
				game.make_noise(shot_one.global_position + Vector2(120, 0), 900.0, "shot", game.player)
				shot_at = game.clock
			elif t > 40.0:
				check(false, "he never came back out to his post (indoors %s, st %d)" % [warm_one.indoors, warm_one.st])
				_done()
		"shot":
			if shot_one.indoors:
				if t > 11.0:
					check(false, "the shooting never brought him out")
					_done()
				return false
			var took: float = game.clock - shot_at
			check(took >= Enemy.SHELTER_OUT.x - 0.1 and took <= Enemy.SHELTER_OUT.y + 0.1, "out %.1f s after the shot" % took)
			check(shot_one.st in [Enemy.St.INVESTIGATE, Enemy.St.COMBAT], "not off to the shooting (st %d)" % shot_one.st)
			check(shot_one.visible and shot_one.cone.visible, "out but still unseen")
			step = "breath"
			t = 0.0
		"breath":
			var n := 0
			for a in [game.player, shot_one, warm_one]:
				for c in a.get_children():
					if c is Breath:
						n += 1
			check(n == 3, "%d of three breathing" % n)
			_done()
	return false
