extends SceneTree
## The federal army at Paso Esperanza:
##   bodies   - every federal type's body is baked holding its guns, the regulars'
##              with the colours (and the Navy that goes with them) as well.
##   gun      - the Remington Rolling Block: a full-length single shot on the
##              Sharps' rounds, and the stranger can take one up (slot 3).
##   waves    - after the first (by the clock), they come with the loading: none till
##              six loads are in, and then the next company, its teniente and its
##              colours with it; the count names them FEDERALES.
##   colours  - the bearer carries them; shot, they go down in the dirt, the levas
##              about lose heart, and the nearest regular runs to raise them; shot
##              in his turn, they stay down.
##   capitán  - his death shakes every man on the field, but the companies still to
##              come haven't heard (nobody's leaderless).
##   godot --headless --path . --fixed-fps 60 -s tests/test_federales.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := "waves"
var mark := 0.0
var bearer: Enemy
var raiser: Enemy
var leva: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "train")
	Engine.set_meta("no_civilians", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _bodies() -> void:
	step = "bodies"
	for k in ["leva", "soldado", "cabo", "rural", "abanderado", "teniente", "capitan"]:
		var td: Dictionary = game.enemy_type(k)
		var anims: Dictionary = game.meta["chars"][td["template"]]["anims"]
		var guns: Array = td["loadout"].duplicate()
		for o in td.get("loadouts", []):
			guns.append_array(o["guns"])
		if td.get("flag", "") != "":
			guns.append_array(["banner", "navy"])
		for g in guns:
			check(anims.has("upper/%s/aim" % g) and anims.has("upper/%s/fire" % g), "%s's body has no %s" % [k, g])


func _gun() -> void:
	step = "gun"
	var d: Dictionary = Weapon.DATA["remington"]
	check(d["name"] == "REMINGTON ROLLING BLOCK" and d["ammo"] == "sharps" and d["range"] > Weapon.DATA["rollingblock"]["range"],
		"the Remington: %s" % [d])
	check(Player.SLOT.get("remington", "") == "rifle", "he can't take one up")
	check(game.meta["guns"].has("remington") and game.meta["ui"]["guns"].has("remington"), "no dropped or card art")


func _spawn(k: String, g: Vector2) -> Enemy:
	return game._add_enemy(k, Iso.to_screen(g), PackedVector2Array(), 90.0, {})


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_bodies()
		_gun()
		game.begin()
		game.player.hp = 100000
		game.player.global_position = Iso.to_screen(Vector2(8.0, 50.0))   # (out of everyone's way)
	if frame <= 3:
		return false
	t += delta
	var d: Director = game.director
	match phase:
		"waves":
			step = "waves"
			if t < 2.0:
				check(game.hud != null and game.level.get("foe_count", "") == "FEDERALES", "not counted as federales")
				return false
			if d.next == 0:
				if t > 40.0:
					check(false, "the first wave never came")
					phase = "colours"
				return false
			if mark == 0.0:   # the first's in: the next waits on the loading
				mark = t
				check(d.next_in() < 0.0, "a countdown to a wave that comes with the loading")
				return false
			if t - mark < 20.0:
				if d.next > 1:
					check(false, "the second came with nothing loaded")
					phase = "colours"
				return false
			game.cargo.loaded = 6
			if t - mark > 21.0:
				check(d.next == 2, "six loaded and no second wave (%d)" % d.next)
				var kinds: Array = d.queue.map(func(q): return q[1])
				for e in game.enemies:
					kinds.append(e.kind)
				check("teniente" in kinds and "abanderado" in kinds, "the company came without its officer or colours: %s" % [kinds])
				phase = "colours"
				mark = t
		"colours":
			step = "colours"
			if bearer == null:
				bearer = _spawn("abanderado", Vector2(50.0, 54.0))
				leva = _spawn("leva", Vector2(52.0, 55.0))
				raiser = _spawn("soldado", Vector2(53.0, 52.0))
				check(bearer.carries_flag() and bearer.weapon.kind == "navy", "the bearer without his colours")
				return false
			if bearer.alive:
				bearer.die(Vector2.RIGHT, game.player)
				check(game.flags.size() == 1, "the colours didn't go down")
				check(leva.shaken > 0.5 or leva.reaction == "flee", "the leva took it in his stride")
				var who: Enemy = null
				for e in game.enemies:
					if e.alive and e.flag_at != Vector2.INF:
						who = e
				check(who != null and who.tdata.get("flag", "") == "raise", "nobody ran for the colours")
				raiser = who
				mark = t
				return false
			if raiser == null:
				phase = "capitan"
				return false
			if raiser.carries_flag():
				check(raiser.weapon.kind == "navy" and game.flags.is_empty(), "raised, but %s and %d flags down" % [raiser.weapon.kind, game.flags.size()])
				raiser.die(Vector2.RIGHT, game.player)
				check(game.flags.size() == 1, "down again: not in the dirt")
				for e in game.enemies:
					check(not (e.alive and e.flag_at != Vector2.INF), "a second man ran for them")
				phase = "capitan"
			elif t - mark > 20.0:
				check(false, "never raised (%s, flag_at %s, reaction %s, st %s, %.0f px off)" % ["alive" if raiser.alive else "dead", raiser.flag_at, raiser.reaction, Enemy.St.keys()[raiser.st], raiser.global_position.distance_to(game.flags[0]["at"]) if game.flags.size() > 0 else -1.0])
				phase = "capitan"
		"capitan":
			step = "capitán"
			var cap := _spawn("capitan", Vector2(56.0, 46.0))
			var men := [_spawn("soldado", Vector2(57.0, 47.0)), _spawn("leva", Vector2(55.0, 48.0))]
			cap.die(Vector2.RIGHT, game.player)
			for m in men:
				check(m.shaken >= 1.0, "a man on the field unshaken by his capitán's death")
			check(not game.leaderless, "the companies still to come are leaderless too")
			print("federales test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
			quit(failures)
			return true
	return false
