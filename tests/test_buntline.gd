extends SceneTree
## The Colt Buntline, and Silencio's two gangs' types (the test yard, its gang parked
## out of the way):
##   gun      - six on the Colt's rounds, loaded the same way; tighter, further and
##              faster than the Colt, but slower to cock.
##   loadout  - his only off the dead: not on the loadout screen, but it goes in his
##              sidearm slot when he takes it up.
##   fanning  - the Colt fans; the Buntline doesn't.
##   gangs    - every hunter and outlaw type says which side it's on, its body is
##              baked holding every gun it may carry, and the Buntline man carries
##              the Buntline (never a Schofield in its place); none of them says
##              the stock lines' Spanish (San Miguel's gang still does).
##   stranger - a dead Buntline man's gun swaps (F) for his Colt, off the same rounds.
##   godot --headless --path . --fixed-fps 60 -s tests/test_buntline.gd

class MockGame:
	extends Node
	var shots := 0
	func sfx(_n: String, _p = null, _v := 0.0, _pv := 0.0) -> void: pass
	func spawn_bullet(_o, _v, _r, _d, _s, _h, _p, _pi := 0) -> void: shots += 1
	func muzzle_flash(_h, _d) -> void: pass
	func make_noise(_p, _r, _k, _s) -> void: pass

const HUNTERS := ["manhunter", "sharpshooter", "buntline", "hunter_boss"]
const OUTLAWS := ["trapper", "trappeur", "mountainman", "woodsman", "outlaw_chief"]

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var gun: Dictionary = {}


func _initialize() -> void:
	_gun()
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(43)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _time(w: Weapon, until: Callable, limit := 30.0) -> float:
	var s := 0.0
	while not until.call() and s < limit:
		w.update(0.02)
		s += 0.02
	return s


func _gun() -> void:
	step = "gun"
	var b: Dictionary = Weapon.DATA["buntline"]
	var c: Dictionary = Weapon.DATA["colt"]
	check(b["spread"] < c["spread"] * 0.6, "throws %.1f to the Colt's %.1f" % [b["spread"], c["spread"]])
	check(b["range"] > c["range"] * 1.15 and b["speed"] > c["speed"], "reaches no further than the Colt")
	check(b["cycle"] > c["cycle"] * 1.3, "cocks as quick as the Colt")
	check(b["damage"] == c["damage"], "not the Colt's round")
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new("buntline", a)
	w.reserve = 30
	check(w.ammo() == "colt", "takes %s, not the Colt's cartridges" % w.ammo())
	var n := 0
	while w.can_fire() and n < 12:
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
		n += 1
	check(n == 6 and g.shots == 6, "fired %d before it was empty" % n)
	w.start_reload()
	_time(w, func(): return w.state == Weapon.S.READY)
	check(w.loaded() == 6, "loaded back to %d" % w.loaded())
	a.free()
	g.free()
	step = "loadout"
	check(Player.SLOT.get("buntline", "") == "colt", "not a sidearm")
	check(not "buntline" in Player.choices("colt"), "on the loadout screen")
	check("colt" in Player.choices("colt") and "schofield" in Player.choices("colt"), "the other sidearms gone from the loadout")


func _gangs() -> void:
	step = "gangs"
	var types: Dictionary = game.enemy_data["types"]
	for k in HUNTERS + OUTLAWS:
		var td: Dictionary = types[k]
		check(td.get("gang", "") == ("hunters" if k in HUNTERS else "outlaws"), "%s is on side '%s'" % [k, td.get("gang", "")])
		var body: Dictionary = game.meta["chars"].get(td["template"], {})
		check(not body.is_empty(), "%s's body (%s) isn't baked" % [k, td["template"]])
		var guns: Array = []
		for o in td.get("loadouts", [{"guns": td["loadout"]}]):
			guns += o["guns"]
		for gk in guns:
			check(gk in body.get("guns", []), "%s's body isn't baked holding a %s" % [k, gk])
	var bosses := (HUNTERS + OUTLAWS).filter(func(k): return types[k].get("coordinator", false))
	check(bosses == ["hunter_boss", "outlaw_chief"], "the leaders: %s" % [bosses])
	var at := Iso.to_screen(Vector2(3.5, 20.5))
	# no Spanish from either side (bar what's their own: the trappeurs' French)
	for k in HUNTERS + OUTLAWS + ["rifleman"]:
		var e: Enemy = game._add_enemy(k, at, PackedVector2Array(), 0.0)
		var said: Array = []
		for stock in [Enemy.SPOT_LINES, Enemy.FLEE_LINES, Enemy.DOWN_LINES, Enemy.RESCUE_LINES, Enemy.GASP_LINES]:
			said += e._tongue(stock)
		var spanish := said.filter(func(l): return l.contains("¡") or l.contains("gringo"))
		if k == "rifleman":
			check(not spanish.is_empty(), "San Miguel's gang lost its Spanish")
		else:
			check(spanish.is_empty() and not said.is_empty(), "a %s says %s" % [k, spanish])
		game.enemies.erase(e)
		e.cone.free()
		e.free()
	for i in 30:
		var e: Enemy = game._add_enemy("buntline", at, PackedVector2Array(), 0.0)
		check(e.loadout == ["buntline"] and e.weapon.kind == "buntline", "a Buntline man with %s" % [e.loadout])
		game.enemies.erase(e)
		e.cone.free()
		e.free()


## A dead man of this kind, a little off from the stranger: and the gun he dropped.
func _dead_man(kind: String, off := Vector2(60, 20)) -> Dictionary:
	var p: Player = game.player
	var at: Vector2 = p.global_position + off
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e.die(Vector2.RIGHT, p)
	for g in game.loose_guns:
		if g["under"] == e:
			return g
	return {}


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		var p: Player = game.player
		p.hp = 100000
		p.global_position = Iso.to_screen(Vector2(12, 12))
		for e in game.enemies:   # (out of the way, alive: or the yard's won)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Iso.to_screen(Vector2(1.5, 22.5))
		_gangs()
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		Input.action_release("alt")
		print("buntline test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "fanning"
			p.arm(["colt"])
			p.switch_to("colt")
			Input.action_press("alt")],
		[0.2, func():
			check(p.weapon.kind == "colt" and p.weapon.fanning, "the Colt won't fan")
			Input.action_release("alt")
			p.arm(["buntline"])
			p.switch_to("colt")
			Input.action_press("alt")],
		[0.2, func():
			check(p.weapon.kind == "buntline" and not p.weapon.fanning, "the Buntline fans")
			Input.action_release("alt")
			step = "stranger"
			p.arm(["colt", "coach"])
			check(p.weapons["colt"].reserve == p.belt.get("colt", -1), "his Colt's not off his belt")
			gun = _dead_man("buntline")
			check(not gun.is_empty() and gun["kind"] == "buntline", "no Buntline lying there")],
		[0.3, func():
			p.process_mode = Node.PROCESS_MODE_DISABLED   # (stood where he's put)
			p.global_position = gun["at"]],
		[0.3, func():
			check(p.weapons["colt"].kind == "colt", "walked over the Buntline and it swapped without F")
			game.swap_gun()
			check(p.weapons["colt"].kind == "buntline", "the Buntline's not in his sidearm slot (%s)" % p.weapons["colt"].kind)
			check(p.weapons["colt"].reserve == p.belt.get("colt", -1), "not off the same rounds")
			var left: Array = game.loose_guns.filter(func(g): return g.get("his", false))
			check(left.size() == 1 and left[0]["kind"] == "colt", "his Colt isn't lying there")],
	]
