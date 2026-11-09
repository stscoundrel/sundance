extends SceneTree
## The Sharps 1874 for the stranger, and its round through a wall (the test yard,
## its gang parked out of the way, a stretch of mud-brick wall and a boxcar set
## down in it):
##   card    - on the rifle card at 4 points, a point dearer than the other single
##             shots, on the Rolling Blocks' .50s.
##   walls   - through a mud-brick wall (a tile, square on or at a slant, but not
##             along it) and a boxcar's planks (two), out the far side a point of
##             damage the less; through the corner of a house,
##             never across one; and only the one wall. Another gun's round stops in
##             the same wall.
##   fright  - a bandit past the wall it cracks by is shaken, as by a near miss.
##   two men - on through the first man into the one behind him, a point the weaker,
##             and no further; another gun's round stops in the first.
##   (anyone's Sharps does it: these are the poacher's rounds, at the stranger, and
##   the fright the stranger's own.)
##   godot --headless --path . --fixed-fps 60 -s tests/test_sharps.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var poacher: Enemy
var hp0 := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		var p: Player = game.player
		p.hp = 100000
		p.process_mode = Node.PROCESS_MODE_DISABLED   # (stood where he's put)
		for e in game.enemies:   # (out of the way, alive: or the yard's won)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Iso.to_screen(Vector2(1.5, 22.5))
		game._place_object("wall_x4", Vector2(8, 19))      # x 8-12, y 19-20: mud brick, a tile thick
		game._place_object("boxcar_a_0", Vector2(16, 18))  # x 16-18.4, y 18-20: planks, two tiles
		game._place_object("wall_x4", Vector2(8, 22))      # and another behind the first, y 22-23
		_card()
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("sharps test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


func _card() -> void:
	step = "card"
	var sh: Dictionary = Weapon.DATA["sharps"]
	check("sharps" in Player.choices("rifle"), "not on the rifle card (%s)" % [Player.choices("rifle")])
	check(sh["points"] == 4, "it costs %d" % sh["points"])
	for k in ["remington", "springfield", "rollingblock"]:
		check(sh["points"] == Weapon.DATA[k]["points"] + 1 or sh["points"] > Weapon.DATA[k]["points"] + 1,
			"not a point dearer than the %s" % k)
	check(sh["points"] == Weapon.DATA["remington"]["points"] + 1, "not a point over the Remington")
	check(Weapon.new("sharps", null).ammo() == "sharps" and Weapon.new("rollingblock", null).ammo() == "sharps",
		"not on the Rolling Blocks' rounds")
	check(Hud.BLURB.has("sharps"), "no line for the card")


## A poacher at `from` with `gun` in hand, the stranger (plenty of blood in him) at
## `to`, and a round from one at the other. (A bandit stood out of the way with his
## processing off is out of the physics too: nothing to hit. The stranger isn't.)
func _shoot(gun: String, from: Vector2, to: Vector2) -> void:
	var p: Player = game.player
	poacher.weapon = Weapon.new(gun, poacher)
	poacher.global_position = Iso.to_screen(from)
	p.global_position = Iso.to_screen(to)
	hp0 = p.hp
	var w: Weapon = poacher.weapon
	var dir := (p.global_position - poacher.global_position).normalized()
	game.spawn_bullet(poacher.global_position, dir * w.d["speed"], w.d["range"], w.d["damage"], poacher,
		poacher.gun_height(), false, int(w.d.get("pierce", 0)))


## What the round took off him.
func _took() -> int:
	return hp0 - game.player.hp


func _plan() -> void:
	var p: Player = game.player
	p.process_mode = Node.PROCESS_MODE_INHERIT
	poacher = game._add_enemy("poacher", Iso.to_screen(Vector2(20, 12)), PackedVector2Array(), 0.0, {})
	poacher.process_mode = Node.PROCESS_MODE_DISABLED
	check(poacher.weapon.kind == "sharps", "the poacher's no Sharps (%s)" % poacher.weapon.kind)
	queue = [
		[0.1, func():
			step = "adobe"
			_shoot("sharps", Vector2(10, 17.5), Vector2(10, 21.2))],
		[0.6, func():
			check(_took() == 2, "through the mud brick it took %d off him (2 wanted)" % _took())
			_shoot("remington", Vector2(10, 17.5), Vector2(10, 21.2))],
		[0.6, func():
			check(_took() == 0, "the Remington's round went through the wall (%d)" % _took())
			# along the wall, steeply: three tiles of it on the way
			_shoot("sharps", Vector2(7.5, 18.6), Vector2(12.5, 20.4))],
		[0.6, func():
			check(_took() == 0, "the round went through the wall along its length (%d)" % _took())
			step = "wood"
			_shoot("sharps", Vector2(17, 16.5), Vector2(17, 21.2))],
		[0.6, func():
			check(_took() == 2, "through the boxcar it took %d off him (2 wanted)" % _took())
			step = "house"
			# straight at the mud-brick house (x 14-18, y 5-9): four tiles of it
			_shoot("sharps", Vector2(16, 10.6), Vector2(16, 3.2))],
		[0.6, func():
			check(_took() == 0, "the round went right through a house (%d)" % _took())
			# across its corner: under a tile of it on the way
			_shoot("sharps", Vector2(19.6, 6.9), Vector2(15.9, 10.6))],
		[0.6, func():
			check(_took() == 2, "through the house's corner it took %d off him (2 wanted)" % _took())
			step = "one wall"
			# the wall, then the second behind it: through the first, stopped by the second
			_shoot("sharps", Vector2(10, 17.5), Vector2(10, 23.5))],
		[0.8, func():
			check(_took() == 0, "it went through two walls (%d)" % _took())
			step = "fright"
			# the stranger's own Sharps, through the wall and past a bandit behind it
			poacher.global_position = Iso.to_screen(Vector2(1.5, 21.5))
			p.arm(["sharps"])
			p.switch_to("rifle")
			p.switch_t = 0.0
			p.global_position = Iso.to_screen(Vector2(10, 17.5))
			var by: Enemy = game.enemies[1]
			by.global_position = Iso.to_screen(Vector2(9.6, 20.9))
			by.pinned_t = 0.0
			var dir := (Iso.to_screen(Vector2(9.0, 21.3)) - p.global_position).normalized()
			game.spawn_bullet(p.global_position, dir * 1100.0, 820.0, 3, p, p.gun_height(), false, 2)],
		[0.6, func():
			check(game.enemies[1].pinned_t > 0.0, "the man past the wall it cracked by wasn't shaken")
			step = "two men"
			_line_up("sharps")],
		[0.6, func():
			check(_lost() == [3, 2, 0], "three men in a line took %s off them ([3, 2, 0] wanted)" % [_lost()])
			_line_up("remington")],
		[0.6, func():
			check(_lost() == [3, 0, 0], "the Remington's round took %s off three men in a line" % [_lost()])],
	]


var _men: Array[Enemy] = []


## Three of them in a line out in the open, the stranger with `gun` at the head of
## it, and a round down the line. (Stood still, but there to be hit: their hurtboxes
## kept in the physics.)
func _line_up(gun: String) -> void:
	var p: Player = game.player
	p.arm([gun])
	p.switch_to("rifle")
	p.switch_t = 0.0
	p.global_position = Iso.to_screen(Vector2(21, 9))
	_men.clear()
	for i in 3:
		var e: Enemy = game.enemies[i]
		e.hurtbox.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		e.process_mode = Node.PROCESS_MODE_INHERIT
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.global_position = Iso.to_screen(Vector2(21, 11.5 + i * 1.5))
		e.hp = 100
		e.max_hp = 100
		_men.append(e)
	var w: Weapon = p.weapon
	var dir := (_men[0].global_position - p.global_position).normalized()
	game.spawn_bullet(p.global_position, dir * w.d["speed"], w.d["range"], w.d["damage"], p, p.gun_height(),
		false, int(w.d.get("pierce", 0)))


func _lost() -> Array:
	return _men.map(func(e): return 100 - e.hp)
