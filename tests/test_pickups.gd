extends SceneTree
## Taking up the dead's guns (the test yard, its gang parked out of the way):
##   empty    - a dead man's Spencer, his rifle slot empty: walked over, it's his,
##              loaded as the dead man left it, and the rounds lying by it with it.
##   swap     - his Colt run dry, a dead man's loaded Navy at his feet: not taken by
##              walking over it, but named for him (F); F, and the Navy's in his hand
##              and firing, his empty Colt lying where it was. F again: his Colt
##              back, the Navy left as he fired it.
##   belt     - the Navy and a horse pistol take the same powder and ball off his belt.
##   schofield - some of the gang's Colts are Schofields; one taken up loads from his
##              Colt rounds.
##   godot --headless --path . --fixed-fps 60 -s tests/test_pickups.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var gun: Dictionary = {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(61)
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
		p.global_position = Iso.to_screen(Vector2(12, 12))
		for e in game.enemies:   # (out of the way, alive: or the yard's won)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Iso.to_screen(Vector2(1.5, 22.5))
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("pickups test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


## A dead man with this gun, a little off from the stranger: and the gun he dropped.
func _dead_man(kind: String, loaded: int) -> Dictionary:
	var p: Player = game.player
	var at: Vector2 = p.global_position + Vector2(60, 20)
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var e: Enemy = game._add_enemy("revolucionario", at, PackedVector2Array(), 0.0, {"loadouts": [{"guns": [kind], "weight": 1}]})
	e.process_mode = Node.PROCESS_MODE_DISABLED
	var w := e.weapon
	match w.action:
		"revolver":
			for i in w.chambers.size():
				w.chambers[i] = 1 if i < loaded else 2
			w.cur = 0
		"lever":
			w.chambered = loaded > 0
			w.tube = maxi(0, loaded - 1)
		_:
			for i in w.barrels.size():
				w.barrels[i] = 1 if i < loaded else 2
	e.die(Vector2.RIGHT, p)
	for g in game.loose_guns:
		if g["under"] == e:
			return g
	return {}


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "empty"
			p.arm(["colt", "coach"])
			gun = _dead_man("spencer", 4)
			check(not gun.is_empty() and gun.has("weapon"), "no Spencer lying there, or no telling how it's loaded")],
		[0.3, func():
			check(gun["ammo"] != null, "no rounds dropped by the Spencer man")
			p.global_position = gun["at"]],
		[0.3, func():
			check("rifle" in p.owned and p.weapons["rifle"].kind == "spencer", "didn't take up the Spencer (%s)" % [p.owned])
			check(p.weapons["rifle"].loaded() == 4, "the Spencer's got %d in it, not the dead man's 4" % p.weapons["rifle"].loaded())
			check(p.belt.get("spencer", 0) >= Pickup.AMOUNT["spencer"], "no Spencer rounds on his belt (%s)" % p.belt)
			check(p.current == "colt", "picking up a gun for an empty slot shouldn't change the one in his hand")
			step = "swap"
			p.global_position += Vector2(0, -40)
			p.switch_to("colt")
			p.switch_t = 0.0
			for i in 6:
				p.weapon.chambers[i] = 2
			p.belt["colt"] = 0
			gun = _dead_man("navy", 6)],
		[0.3, func():
			p.global_position = gun["at"]],
		[0.3, func():
			check(p.weapons["colt"].kind == "colt", "walked over the Navy and it swapped without F")
			check(game.at_feet == gun, "the Navy at his feet isn't the one he'd take up")
			game.hud.toast_t = 0.0
			game.swap_gun()
			check(p.weapon.kind == "navy" and p.current == "colt" and p.weapon.loaded() == 6, "the loaded Navy isn't in his hand (%s, %d)" % [
				p.weapon.kind, p.weapon.loaded()])
			var left: Array = game.loose_guns.filter(func(g): return g.get("his", false))
			check(left.size() == 1 and left[0]["kind"] == "colt" and left[0]["weapon"].loaded() == 0, "his empty Colt isn't lying there")
			check(game.stats.get("guns swapped", 0) == 1, "not counted")],
		[0.4, func():
			p.weapon.trigger()
			check(p.weapon.loaded() == 5, "the Navy didn't fire")],
		[0.6, func():
			check(not game.at_feet.is_empty() and game.at_feet["kind"] == "colt", "his own Colt isn't his to take back")
			game.swap_gun()
			check(p.weapon.kind == "colt" and p.weapon.loaded() == 0, "his Colt's not back in his hand, empty")
			var navy: Array = game.loose_guns.filter(func(g): return g["kind"] == "navy")
			check(navy.size() == 1 and navy[0]["weapon"].loaded() == 5, "the Navy isn't lying there as he fired it")
			step = "belt"
			p.belt["powder"] = 9
			var a := Weapon.new("navy", p)
			var b := Weapon.new("pistola", p)
			check(a.ammo() == "powder" and a.reserve == 9 and b.reserve == 9, "the Navy and pistol don't share his powder")
			b.reserve -= 2
			check(a.reserve == 7 and p.belt["powder"] == 7, "the belt's not one belt")
			step = "schofield"
			var n := 0
			for i in 40:
				var e: Enemy = game._add_enemy("pistolero", Iso.to_screen(Vector2(2, 2)) + Vector2(i * 4, 0), PackedVector2Array(), 0.0)
				e.process_mode = Node.PROCESS_MODE_DISABLED
				if e.weapon.kind == "schofield":
					n += 1
				game.enemies.erase(e)
				e.queue_free()
			print("  %d of 40 pistoleros came with a Schofield" % n)
			check(n >= 5 and n <= 22, "%d of 40 with a Schofield" % n)
			p.belt["colt"] = 12
			gun = _dead_man("schofield", 6)],
		[0.3, func():
			p.global_position = gun["at"]],
		[0.3, func():
			game.swap_gun()
			check(p.weapon.kind == "schofield" and p.weapon.reserve == 12 + Pickup.AMOUNT["colt"],
				"a Schofield should take his Colt rounds (%s, %d)" % [p.weapon.kind, p.weapon.reserve])],
	]
