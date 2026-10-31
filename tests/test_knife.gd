extends SceneTree
## The knife. One bandit at a time in the open (the rest held still), the hero
## placed by hand:
##   silent   - crouched right behind a guard: a quiet takedown; a bandit round the
##              corner hears nothing.
##   seen     - the same in front of another bandit: he sees it.
##   ready    - a rush at a man with a loaded gun facing him: shot point-blank, and
##              left reeling.
##   reloading- a rush at a man mid-reload: the knife goes in.
##   jefe     - a rush at El Jefe (4 HP), his gun empty: he takes the cut and reels.
##   far      - too far for a lunge: nothing to go for.
##   godot --headless --path . --fixed-fps 60 -s tests/test_knife.gd

const SPOT := Vector2(26.0, 31.4)   # open main street
const SCENES := ["silent", "seen", "ready", "reloading", "jefe", "far"]

var game: Node
var frame := 0
var failures := 0
var scene_i := -1
var t := 0.0
var victim: Enemy
var other: Enemy
var hp0 := 0
var used: Array[Enemy] = []


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(2)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [SCENES[scene_i], msg])


func _take(kind: String) -> Enemy:
	for e in game.enemies:
		if e.alive and not e in used and (kind == "" or e.kind == kind) and e.tdata["concealed"] == false:
			used.append(e)
			return e
	return null


## A bandit stood at `at` facing `facing`, still, everyone else well away.
func _stand(e: Enemy, at: Vector2, facing: Vector2, aware: bool) -> void:
	e.global_position = at
	e.facing = facing
	e.desired = facing
	e.st = Enemy.St.COMBAT if aware else Enemy.St.GUARD
	e.sees_player = aware
	e.process_mode = Node.PROCESS_MODE_DISABLED


func _next() -> void:
	scene_i += 1
	t = 0.0
	other = null
	var p: Player = game.player
	p.knife_cd = 0.0
	p.stagger_t = 0.0
	p.action_t = 0.0   # done reeling from the last scene
	for e in used:
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.global_position += Vector2(0, -2000)
	p.crouched = false
	hp0 = p.hp
	var at := Iso.to_screen(SPOT + Vector2(scene_i * 6.0, 0))   # a fresh bit of street each time
	var east := Vector2.RIGHT
	match SCENES[scene_i]:
		"silent", "seen":
			victim = _take("pistolero")
			_stand(victim, at, east, false)
			p.crouched = true
			p.global_position = at - east * 16.0   # right behind him
			if SCENES[scene_i] == "seen":
				other = _take("cowboy")
				_stand(other, at + east * 70.0, -east, false)   # looking straight at it
				other.process_mode = Node.PROCESS_MODE_INHERIT
		"ready":
			victim = _take("cowboy")
			_stand(victim, at, -east, true)
			p.global_position = at - east * 45.0
		"reloading":
			victim = _take("bandido")
			_stand(victim, at, -east, true)
			victim.weapon.chambers.fill(2)
			victim.weapon.start_reload()
			p.global_position = at - east * 45.0
		"jefe":
			victim = _take("jefe")
			_stand(victim, at, east, true)   # turned away
			victim.weapon.barrels.fill(2)
			victim.weapon.reserve = 0
			p.global_position = at - east * 45.0
		"far":
			victim = _take("")
			_stand(victim, at, -east, true)
			p.global_position = at - east * 90.0
	p.facing = (victim.global_position - p.global_position).normalized()


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -2000)   # out of the way
		game.player.hp = 1000
		_next()
	if frame <= 3:
		return false
	t += delta
	var p: Player = game.player
	if t > 0.05 and t - delta <= 0.05:   # a frame for the knife to find him
		var name: String = SCENES[scene_i]
		if name == "far":
			check(p.knife_cand == null, "a knife target %.0f px away" % p.global_position.distance_to(victim.global_position))
		else:
			check(p.knife_cand == victim, "the knife doesn't see the %s" % victim.kind)
			check(p.knife_silent == (name in ["silent", "seen"]), "takedown/rush mixed up (quiet %s)" % p.knife_silent)
			check(p.knife(), "the knife didn't go")
			if name == "ready":
				victim.process_mode = Node.PROCESS_MODE_INHERIT   # his gun has to go off
	if t < 1.5:
		return false
	match SCENES[scene_i]:
		"silent":
			check(not victim.alive and victim._death == "death_slump", "the guard should be let down quietly (%s)" % victim._death)
			check(game.stats.get("takedowns", 0) == 1, "no takedown counted")
			check(p.hp == hp0, "a takedown cost him blood")
		"seen":
			check(not victim.alive, "the takedown failed")
			check(other.st == Enemy.St.COMBAT or other.reaction != "" or other.pending != "",
				"the bandit watching it didn't react (%s)" % Enemy.St.keys()[other.st])
		"ready":
			check(victim.alive, "he knifed a man with a ready gun")
			check(p.hp < hp0, "the ready man didn't shoot him")
			check(game.stats.get("rushes shot", 0) == 1, "no point-blank shot counted")
		"reloading":
			check(not victim.alive and victim._death == "death_knees", "the knife should get a man mid-reload")
			check(p.hp == hp0, "a man mid-reload hurt him")
		"jefe":
			check(victim.alive and victim.hp == victim.max_hp - Player.RUSH_DMG, "El Jefe should take the cut and live (hp %d)" % victim.hp)
			check(p.hp == hp0, "El Jefe with an empty gun hurt him")
		"far":
			pass
	print("%-9s ok: hp %d -> %d, %s" % [SCENES[scene_i], hp0, p.hp, "dead" if not victim.alive else "alive"])
	if scene_i + 1 < SCENES.size():
		_next()
		return false
	print("stats: ", game.stats)
	print("knife test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
