extends SceneTree
## Things gunfire marks that stop nothing (bandits out of town; real rounds):
##   sign    - a round through a hanging sign sets it swinging and it settles back;
##             the round flies on. The third parts a chain: it hangs askew.
##   washing - a round through the washing holes it (it flaps) and flies on; a
##             bandit's round does it just the same; the third tears it off the line.
##   holes   - a round into a building's front leaves a hole there for good; one
##             into a back wall (a face you never see) leaves none; no more than 150.
##   mended  - once it's quiet, the carpenter hangs the sign straight and a hen woman
##             pegs the washing out again.
##   godot --headless --path . --fixed-fps 60 -s tests/test_signs.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var sign: Dictionary
var cloth: Dictionary
var cloth2: Dictionary
var swung := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_reserve", true)
	seed(14)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _of(kind: String) -> Array:
	return game.fragile.filter(func(i): return i["kind"] == kind)


## A round from `from` (tiles) at `to` (screen), from the stranger or a bandit.
func _fire(from: Vector2, to: Vector2, by: Actor = null) -> void:
	var a := Iso.to_screen(from)
	game.spawn_bullet(a, (to - a).normalized() * 900.0, 600.0, 1, by if by else game.player, Iso.GUN_H, false)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.quiet_after = 2.0
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for c in game.civilians:
			if c.mayor:
				c._go_inside(false)
		_sign()
	if frame <= 3:
		return false
	t += delta
	if sign and sign["sprite"].frame != game.SIGN_REST and sign["state"] == 0:
		swung = true
	if queue.is_empty():
		print("stats: ", game.stats)
		print("signs test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _sign() -> void:
	step = "sign"
	var signs := _of("sign")
	check(signs.size() >= 8, "only %d hanging signs" % signs.size())
	for sg in signs:   # one with a clear line to it from the street
		var from := Iso.to_screen(Iso.to_grid(sg["at"]) + Vector2(0, 4))
		if game.ray(from, sg["at"], Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_FRAGILE | Iso.LAYER_HURT, [] as Array[RID], true).get("collider") == sg["body"]:
			sign = sg
			break
	var g := Iso.to_grid(sign["at"])
	var n0: int = game.stats.get("broken", 0)
	_fire(g + Vector2(0, 4), sign["at"])
	queue = [
		[0.6, func():
			check(swung and sign["hits"] == 1, "one round didn't set it swinging (hits %d)" % sign["hits"])
			check(sign["state"] == 0 and sign["body"] != null, "one round broke it")],
		[6.0, func():
			check(sign["sprite"].frame == game.SIGN_REST and not sign in game.swinging, "it never settled")
			_fire(g + Vector2(0, 4), sign["at"])],
		[0.4, func(): _fire(g + Vector2(0, 4), sign["at"])],
		[0.6, func():
			check(sign["state"] == 1 and sign["sprite"].frame == game.SIGN_REST + 4, "three rounds and it's still on both chains")
			check(sign["body"] == null and game.stats.get("broken", 0) > n0, "it should be done with")   # (the rounds fly on: a pane behind may go too)
			_washing()],
	]


func _washing() -> void:
	step = "washing"
	var lines := _of("laundry")
	check(lines.size() >= 16, "only %d pieces of washing" % lines.size())
	# two in the alley between the sheriff's and the hotel, line across it
	var alley := lines.filter(func(i): return absf(Iso.to_grid(i["at"]).y - 19.12) < 0.2)
	check(alley.size() == 2, "%d pieces across the alley" % alley.size())
	cloth = alley[0]
	cloth2 = alley[1]
	var g := Iso.to_grid(cloth["at"])
	_fire(g + Vector2(0, 5), cloth["at"])
	queue.append([0.4, func():
		check(cloth["state"] == 1 and cloth["hits"] == 1, "one round didn't hole it")
		check(cloth["sprite"].frame in [4, 5], "shot through, it isn't flapping (%d)" % cloth["sprite"].frame)
		var bandit: Enemy = game.enemies[0]
		_fire(Iso.to_grid(cloth2["at"]) + Vector2(0, 5), cloth2["at"], bandit)])
	queue.append([0.4, func():
		check(cloth2["state"] == 1, "a bandit's round went through the washing without a mark")
		_fire(g + Vector2(0, 5), cloth["at"])])
	queue.append([0.4, func(): _fire(g + Vector2(0.3, 5), cloth["at"])])
	queue.append([0.5, func():
		check(cloth["state"] == 2 and cloth["sprite"].frame == 6 and cloth["body"] == null, "three rounds and it's still on the line")
		_holes()])


func _holes() -> void:
	step = "holes"
	var hotel := Vector2(30.6, 27.95)   # the hotel's front, on main street
	for dx in [0.0, 1.3, 2.6, 3.4]:
		_fire(Vector2(hotel.x + dx, 31.0), Iso.to_screen(Vector2(hotel.x + dx, 27.0)))
	_fire(Vector2(31.0, 20.0), Iso.to_screen(Vector2(31.0, 24.0)))   # its back wall, from the yard behind
	queue.append([0.5, func():
		var spr: Sprite2D = null
		for c in game.world.get_children():
			if c is Sprite2D and c.get_node_or_null("Holes") and c.position.distance_to(Iso.to_screen(Vector2(31, 25))) < 120.0:
				spr = c
		check(spr != null, "no holes in the hotel")
		if spr:
			var h: Holes = spr.get_node("Holes")
			print("holes in the hotel's front: %d" % h.pts.size())
			check(h.pts.size() >= 2 and h.pts.size() <= 4, "%d holes from four rounds at its front" % h.pts.size())
			for p in h.pts:   # all on the street side, none round the back
				check(Iso.to_grid(spr.position + p + Vector2(0, 20)).y > 26.5, "a hole round the back")
			for i in 200:
				h.add(Vector2.ZERO)
			check(h.pts.size() == Holes.MAX, "%d holes kept" % h.pts.size())
		_mended()])


func _mended() -> void:
	step = "mended"
	queue.append([120.0, func():
		print("sign: state %d; washing: %d and %d; %s" % [sign["state"], cloth["state"], cloth2["state"],
			game.stats.get("repaired", 0)])
		check(sign["state"] == 0 and sign["sprite"].frame == game.SIGN_REST and sign["body"] != null,
			"the carpenter didn't hang the sign straight")
		check(cloth["state"] == 0 and cloth2["state"] == 0 and cloth["sprite"].frame in [0, 1, 2],
			"the washing wasn't pegged out again")
		check(cloth["body"] != null, "pegged out again, it can't be hit")])
