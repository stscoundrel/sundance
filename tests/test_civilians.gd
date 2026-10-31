extends SceneTree
## Townsfolk, in three fresh towns:
##  1. A shot on main street. Townsfolk close to it or in view of it panic and get
##     indoors (or off the edge of town); those far off and out of sight carry on.
##  2. A snitch stares at the stranger (the tell), then runs to tell a bandit, who
##     joins the fight. The armed saloon girl and the gambler pass as townsfolk
##     (no cone, no gun in hand) until something's up. Shooting a townsman counts
##     as an innocent.
##  3. An honest townsman glances at the stranger and looks away. The armed saloon
##     girl lets him stand in plain view a few paces off, and only draws when he
##     walks right up to her.
##   godot --headless --path . --fixed-fps 60 -s tests/test_civilians.gd


var game: Node
var scene := 0
var frame := 0
var clock := 0.0
var failures := 0
var near: Array[Civilian] = []   # townsfolk who should take fright at the first shot
var far: Array[Civilian] = []    # and those who shouldn't
var snitch: Civilian
var fired := false
var checked := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	seed(4)
	_new_town()


func _new_town() -> void:
	if game:
		game.queue_free()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	clock = 0.0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000000
		if scene == 0:
			_start_shot()
		elif scene == 1:
			_start_snitch()
		else:
			_start_honest()
	if frame <= 3:
		return false
	clock += delta
	if scene == 0:
		return _shot(delta)
	if scene == 1:
		return _snitch()
	return _honest()


# ------------------------------------------------------------------ 1. a shot

func _start_shot() -> void:
	# a street corner out of the bandits' sight, with townsfolk about
	game.player.crouched = true
	var hero := Vector2.INF
	var most := 0
	for p in Posse.new(game).points:
		var hidden := true
		for e in game.enemies:
			hidden = hidden and e.global_position.distance_to(p) > 120.0 and e.visibility_of(p, true, false) <= 0.0
		var folk := 0
		for c in game.civilians:
			folk += 1 if c.global_position.distance_to(p) < 250.0 else 0
		if hidden and folk > most:
			most = folk
			hero = p
	check(hero != Vector2.INF, "no hidden street corner to shoot from")
	game.player.global_position = hero
	print("the stranger shoots from %s" % Iso.to_grid(hero).round())
	for c in game.civilians:
		if c.gone():
			continue   # indoors already (the mourners, until there's a grave)
		var d: float = c.global_position.distance_to(hero)
		if d < Civilian.CLOSE or (d < Civilian.HEAR and game.line_of_sight(c.global_position, hero, false)):
			near.append(c)
		elif d > 300.0 and not game.line_of_sight(c.global_position, hero, false):
			far.append(c)
	print("townsfolk %d: %d near the shot, %d far off" % [game.civilians.size(), near.size(), far.size()])


func _shot(_delta: float) -> bool:
	if clock >= 1.0 and not fired:
		fired = true
		# into the nearest wall
		var best := 1e9
		for a in 16:
			var d := Vector2.from_angle(a * TAU / 16.0)
			var hit: Dictionary = game.ray(game.player.global_position, game.player.global_position + d * 200.0, Iso.LAYER_WALL)
			if not hit.is_empty() and game.player.global_position.distance_to(hit["position"]) < best:
				best = game.player.global_position.distance_to(hit["position"])
				game.player.facing = d
		game.player.weapon.trigger()
	if clock >= 1.3 and not checked:   # just after the shot, before the bandits answer it
		checked = true
		for c in near:
			check(c.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE] or not c.alive,
				"%s near the shot didn't react (%s)" % [c.kind, Civilian.St.keys()[c.st]])
		for c in far:
			check(c.st in [Civilian.St.IDLE, Civilian.St.WALK], "%s far off took fright (%s)" % [c.kind, Civilian.St.keys()[c.st]])
		return false
	if clock < 20.0:
		return false
	var inside := 0
	for c in near:
		inside += 1 if (c.gone() or not c.alive) else 0
	print("after 20 s: %d of %d near townsfolk indoors or gone (%s)" % [inside, near.size(), game.stats])
	check(inside * 10 >= near.size() * 7, "only %d of %d made it indoors" % [inside, near.size()])
	scene = 1
	_new_town()
	return false


# ------------------------------------------------------------------ helpers

## Put the stranger in front of someone, at about distance r, out of the other
## bandits' way. Returns false if there's no such spot.
func _face_to_face(who: Actor, radii: Array, keep_clear := true) -> bool:
	for r in radii:
		for a in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var p: Vector2 = who.global_position + who.facing.rotated(a) * r
			var clear: bool = game.is_free(p) and game.line_of_sight(who.global_position, p, false)
			if keep_clear:
				for e in game.enemies:
					clear = clear and (e == who or e.global_position.distance_to(p) > 110.0)
			if clear:
				game.player.global_position = p
				return true
	return false


func _pick_townsman() -> Civilian:
	for c in game.civilians:
		var near_bandit := false
		for e in game.enemies:
			near_bandit = near_bandit or c.global_position.distance_to(e.global_position) < 420.0
		if near_bandit and _face_to_face(c, [90.0, 70.0, 110.0, 130.0]):
			return c
	return null


func _facing_him(who: Actor) -> float:
	return abs(who.facing.angle_to(game.player.global_position - who.global_position))


# ------------------------------------------------------------------ 2. a snitch

var stared := false


func _start_snitch() -> void:
	# a townsman the stranger can creep up in front of, out of the bandits' sight
	game.player.crouched = true
	snitch = _pick_townsman()
	check(snitch != null, "nowhere to put the hero in a townsman's view")
	snitch.snitch = true
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED   # stand still: this is about the tip-off
	print("snitch: the %s at %s" % [snitch.kind, Iso.to_grid(snitch.global_position).round()])
	for e in game.enemies:
		if e.tdata["concealed"]:
			check(not e.revealed and not e.cone.visible and e.anim_gun == "unarmed",
				"%s should pass as townsfolk at the start" % e.kind)


func _snitch() -> bool:
	if clock >= 1.8 and not stared:
		# the tell: still staring, not yet off to tell
		stared = true
		check(snitch.st != Civilian.St.SNITCH and snitch.st != Civilian.St.FLEE, "the snitch ran off before you could read him")
		check(_facing_him(snitch) < 0.5, "the snitch isn't staring at the stranger (%.2f rad off)" % _facing_him(snitch))
	if clock < 15.0:
		return false
	var told := snitch.tell
	print("snitch: %s, told %s (%s)" % [Civilian.St.keys()[snitch.st], told.kind if told else "nobody",
		Enemy.St.keys()[told.st] if told else "-"])
	check(game.stats.get("snitch tells", 0) >= 1, "the snitch never told anyone")
	check(told != null and told.st == Enemy.St.COMBAT, "the bandit he told isn't after the stranger")
	# the act ends when something's up
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_INHERIT
		if e.tdata["concealed"] and e.alive:
			e.enter_combat(game.player.global_position, false, false)
			check(e.revealed and e.cone.visible and e.anim_gun == "", "%s should drop the act in a fight" % e.kind)
	# and gunning down a townsman is noticed
	var victim: Civilian = null
	for c in game.civilians:
		if c.alive and not c.gone():
			victim = c
	victim.take_hit(5, Vector2.RIGHT, game.player)
	check(game.innocents == 1 and game.innocent_t > 0.0, "shooting a townsman should count as an innocent")
	scene = 2
	_new_town()
	return false


# ------------------------------------------------------------------ 3. honest folk, and a lady

var honest: Civilian
var lady: Enemy
var phase := 0


func _start_honest() -> void:
	game.player.crouched = true
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	for c in game.civilians:
		c.snitch = false   # nobody runs to tell her: she has to find out for herself
	honest = _pick_townsman()
	check(honest != null, "nowhere to put the hero in a townsman's view")


func _honest() -> bool:
	if phase == 0 and clock >= 3.0:
		phase = 1
		print("honest %s looks %.2f rad away from the stranger" % [honest.kind, _facing_him(honest)])
		check(_facing_him(honest) > 1.0, "an honest townsman should glance and look away")
		check(honest.st in [Civilian.St.IDLE, Civilian.St.WALK], "an honest townsman went off (%s)" % Civilian.St.keys()[honest.st])
		# now the armed saloon girl: the stranger stands in plain view a few paces off
		for e in game.enemies:
			if e.kind == "saloon_girl":
				lady = e
		lady.process_mode = Node.PROCESS_MODE_INHERIT
		game.player.crouched = false
		check(_face_to_face(lady, [100.0, 90.0, 120.0], false), "nowhere to stand in front of the saloon girl")
	if phase == 1 and clock >= 7.0:
		phase = 2
		check(not lady.revealed and lady.st != Enemy.St.COMBAT, "the saloon girl gave herself away first (%s)" % Enemy.St.keys()[lady.st])
		check(_face_to_face(lady, [28.0, 22.0, 34.0], false), "no room to walk up to the saloon girl")
	if phase == 2 and clock >= 7.6:
		check(lady.revealed and lady.st == Enemy.St.COMBAT, "walking right up to her should make her draw")
		print("civilians test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	return false
