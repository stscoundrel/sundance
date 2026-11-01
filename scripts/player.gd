class_name Player
extends Actor
## The gunslinger: WASD to move, mouse to aim. He rides in with the guns picked on
## the loadout screen and takes up any of the others a dead man drops by walking
## over it; cartridges go in his belt whether he has the gun for them yet or not.

const ORDER := ["colt", "coach", "rifle"]
const RESERVE := {"colt": 30, "coach": 10, "rifle": 26}   # what he rides in with, per gun
# The knife (E). Up close behind a man who isn't on to him, a silent takedown; a
# few paces off from one who is, a rush: he lunges, and it's decided as he gets
# there: if the man can shoot (gun loaded and ready, facing him, not reeling or
# reloading) he does, point-blank, and the stranger is left stunned in front of
# him; if not, the knife goes in, loudly.
const KNIFE_SILENT := 22.0   # px: in reach for a takedown from behind
const KNIFE_RUSH := 58.0     # px: a lunge away
const LUNGE := 150.0         # px/s
const LUNGE_MAX := 0.5       # s: if he hasn't reached him by then, he's missed
const KNIFE_CD := 0.7        # s before the next
const RUSH_DMG := 3          # a rush's cut: enough for most, not El Jefe
# Bandaging (B): down on one knee for a long while, patching himself up: two bars
# back, the limp and the bleeding stopped. Moving, shooting, reloading, the knife
# or a hit breaks it off (he keeps the bandage, not the time spent).
const BANDAGE_T := 10.0
const BANDAGE_HEAL := 2
const WALK := 46.0
# Dragging the dead (hold E by a body): out of sight round a corner before his
# friends find him. Slow, both hands on the collar (the guns put away): letting go
# of E, shooting, crouching, bandaging or a change of gun drops him. He leaves a
# smear the bandits can follow, and his pool stays where he fell.
const DRAG_REACH := 20.0
const DRAG_GRAB := 0.35     # s of holding E before he takes hold (a tap is the knife)
const DRAG_SPEED := 0.4
const DRAG_SMEAR := 9.0     # px between smears
const CROUCH_WALK := 22.0

var weapons := {}
var owned: Array[String] = []   # the guns he has, in ORDER
var current := "colt"
var switch_t := 0.0
var step_t := 0.0
var bloom := 0.0
var aim_dist := 0.0
var aim_target: Enemy = null
var _spur := false
var knife_cand: Enemy = null   # who the knife would go for now, if anyone
var knife_silent := false      # and whether that would be a quiet takedown
var knife_target: Enemy = null
var knife_quiet := false
var knife_t := -1.0            # time into the lunge; < 0 when not lunging
var knife_cd := 0.0
var dragging: Enemy = null
var grab_t := 0.0
var smear_at := Vector2.ZERO
var exposed_t := 0.0           # he's just fired: up over his cover, flash and smoke
var bandages := 1
var bandage_t := -1.0          # time into bandaging; < 0 when not at it


func setup(g: Node, pos: Vector2) -> void:
	setup_body(g, pos)
	is_player = true
	hp = 6
	max_hp = 6
	for k in ORDER:
		weapons[k] = Weapon.new(k, self)
	arm(ORDER)
	set_character(g.enemy_data["player"]["template"], g.enemy_data["player"]["palette"])
	facing = Vector2(1, -0.3).normalized()


func _physics_process(delta: float) -> void:
	if not alive:
		if dying():
			update_anim(delta)
		return
	var playing: bool = game.state == "play"
	knife_cd = maxf(0.0, knife_cd - delta)
	exposed_t = maxf(0.0, exposed_t - delta)
	if knife_t >= 0.0:
		_lunge(delta)
		update_anim(delta)
		return
	var input := Vector2.ZERO
	if playing and not is_staggered():
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * (CROUCH_WALK if crouched else WALK) * limp_factor()
	if dragging:
		velocity = input * WALK * DRAG_SPEED * limp_factor()
	if bandage_t >= 0.0:
		_bandage(delta, input)
	move_and_slide()
	_find_knife_target()
	if dragging:
		_drag(delta, input)

	var m := get_global_mouse_position()
	aim_target = game.enemy_under(m)
	var target := m + Vector2(0, gun_height())
	if aim_target:
		target = aim_target.aim_point()
	var to := target - global_position
	if to.length() > 3.0 and playing and not dragging:
		facing = to.normalized()
	aim_dist = to.length()

	bloom = max(0.0, bloom - delta * 2.0)
	weapon.update(delta)
	if switch_t > 0.0:
		switch_t -= delta
	if playing:
		if game._args.has("bot"):
			_bot(delta)
		else:
			_handle_actions()

	if input != Vector2.ZERO and not crouched:
		step_t -= delta
		if step_t <= 0.0:
			step_t = 0.36
			game.make_noise(global_position, 55.0, "step", self)
			game.sfx("step", null, -9.0, 0.2)
			_spur = not _spur
			if _spur:
				game.sfx("spur", null, -12.0, 0.1)
	update_anim(delta)


func _handle_actions() -> void:
	if dragging:
		for a in ["fire", "alt", "crouch", "bandage", "weapon_1", "weapon_2", "weapon_3"]:
			if Input.is_action_just_pressed(a):
				drop_body()
				return
		if not Input.is_action_pressed("knife"):
			drop_body()
		return
	if Input.is_action_pressed("knife") and knife_t < 0.0 and bandage_t < 0.0:
		grab_t += get_physics_process_delta_time()
		if grab_t >= DRAG_GRAB:
			grab_t = 0.0
			var b: Enemy = game.body_to_drag(global_position, DRAG_REACH)
			if b:
				take_body(b)
				return
	else:
		grab_t = 0.0
	if bandage_t >= 0.0:
		for a in ["fire", "alt", "reload", "knife", "crouch", "weapon_1", "weapon_2", "weapon_3"]:
			if Input.is_action_just_pressed(a):
				stop_bandage()
				break
	if Input.is_action_just_pressed("bandage"):
		start_bandage()
	if Input.is_action_just_pressed("crouch"):
		crouched = not crouched
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
	if Input.is_action_just_pressed("knife"):
		knife()
	for i in 3:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_to(ORDER[i])
	if switch_t > 0.0:
		return
	if Input.is_action_just_pressed("fire"):
		weapon.trigger()
	if weapon.kind == "colt":
		weapon.fanning = Input.is_action_pressed("alt")
	elif Input.is_action_just_pressed("alt"):
		weapon.alt_trigger()


## The guns he rides in with (at least one), each with its belt of cartridges.
func arm(guns: Array) -> void:
	owned.clear()
	for k in ORDER:
		weapons[k] = Weapon.new(k, self)
		if k in guns:
			owned.append(k)
			weapons[k].reserve = RESERVE[k]
	current = owned[0]
	weapon = weapons[current]


## A dead man's gun, picked up off the ground with whatever he left in it.
func take_up(k: String) -> void:
	var w := Weapon.new(k, self)
	w.reserve = weapons[k].reserve   # cartridges he picked up before he had the gun
	w.part_spent()
	weapons[k] = w
	owned.append(k)
	owned.sort_custom(func(a, b): return ORDER.find(a) < ORDER.find(b))
	game.sfx("pickup", null, 0.0)
	game.sfx("close", null, -6.0)


# ------------------------------------------------------------------ the dead

## By the collar: the guns go away and he hauls the body along behind him.
func take_body(b: Enemy) -> void:
	dragging = b
	b.set_meta("dragged", true)
	crouched = false
	pose = "haul"
	smear_at = b.global_position
	game.sfx("tear", global_position, -14.0, 0.1)
	game.stats["bodies dragged"] = game.stats.get("bodies dragged", 0) + 1


func drop_body() -> void:
	if dragging and is_instance_valid(dragging):
		dragging.remove_meta("dragged")
	dragging = null
	if pose == "haul":
		pose = ""


func _drag(delta: float, input: Vector2) -> void:
	var b := dragging
	if not is_instance_valid(b) or b.has_meta("buried"):
		drop_body()
		return
	if input != Vector2.ZERO:
		facing = input.normalized()   # walking away with it, the body behind him
		var behind := global_position - facing * 14.0
		b.global_position = b.global_position.move_toward(behind, maxf(velocity.length(), 20.0) * delta * 1.5)
	if b.global_position.distance_to(smear_at) > DRAG_SMEAR:
		smear_at = b.global_position
		game.decals.add(smear_at, randf_range(1.2, 2.2), Color(0.38, 0.06, 0.04, 0.5))
		game.trails.append({"at": smear_at, "t": game.clock, "player": true})   # (the bandits read it like his own blood)


# ------------------------------------------------------------------ bandages

## Worth it (he's hurt, limping or bleeding) and he has one: down he gets.
func start_bandage() -> bool:
	if bandage_t >= 0.0 or not alive or knife_t >= 0.0:
		return false
	if bandages <= 0:
		game.hud.toast("No bandages left")
		return false
	if hp >= max_hp and limp_t <= 0.0 and not bleeding:
		return false
	crouched = true
	weapon.abort()
	bandage_t = 0.0
	pose = "bandage"
	game.sfx("tear", global_position, -6.0, 0.1)
	game.make_noise(global_position, 45.0, "step", self)   # the tearing cloth, close by
	return true


func _bandage(delta: float, input: Vector2) -> void:
	if input != Vector2.ZERO or not crouched:
		stop_bandage()
		return
	velocity = Vector2.ZERO
	pose = "bandage"
	bandage_t += delta
	if bandage_t >= BANDAGE_T:
		hp = mini(max_hp, hp + BANDAGE_HEAL)
		limp_t = 0.0
		bleeding = false
		bandages -= 1
		bandage_t = -1.0
		pose = ""
		game.hud.toast("Bandaged")
		game.stats["bandaged"] = game.stats.get("bandaged", 0) + 1


func stop_bandage() -> void:
	if bandage_t < 0.0:
		return
	bandage_t = -1.0
	pose = ""
	game.hud.toast("Bandaging broken off")
	game.stats["bandaging broken off"] = game.stats.get("bandaging broken off", 0) + 1


# ------------------------------------------------------------------ the knife

## The man under the cursor if the knife can reach him, else the nearest it can.
func _find_knife_target() -> void:
	knife_cand = null
	if knife_cd > 0.0 or is_staggered() or game.state != "play":
		return
	var best_d := INF
	for e in game.enemies:
		if not e.alive and not e.downed:
			continue
		var d := global_position.distance_to(e.global_position)
		if d > KNIFE_RUSH or not game.line_of_sight(global_position, e.global_position, false):
			continue
		if e == aim_target:
			d = -1.0
		if d < best_d:
			best_d = d
			knife_cand = e
	if knife_cand:
		knife_silent = (knife_cand.downed or knife_cand.unaware()) and global_position.distance_to(knife_cand.global_position) <= KNIFE_SILENT


## E: go for him.
func knife() -> bool:
	if knife_cand == null or knife_t >= 0.0 or not alive:
		return false
	knife_target = knife_cand
	knife_quiet = knife_silent
	knife_t = 0.0
	weapon.abort()
	return true


func _lunge(delta: float) -> void:
	var e := knife_target
	knife_t += delta
	if e == null or not (e.alive or e.downed) or knife_t > LUNGE_MAX:
		_knife_done(KNIFE_CD)   # missed him
		game.stats["knife misses"] = game.stats.get("knife misses", 0) + 1
		return
	var to := e.global_position - global_position
	facing = to.normalized()
	if to.length() < 11.0:
		velocity = Vector2.ZERO
		_strike(e)
		return
	velocity = facing * (LUNGE * 0.7 if knife_quiet else LUNGE)
	move_and_slide()


func _strike(e: Enemy) -> void:
	var dir := facing
	play_action("stab")
	if e.downed:
		# a wounded man in the dirt: quickly, quietly
		e.finish(self)
		game.make_noise(global_position, 40.0, "struggle", self)
		_knife_done(KNIFE_CD)
		return
	if knife_quiet and e.unaware():
		# a hand over his mouth, the blade, and he's let down quietly
		e.die(dir, self, "death_slump")
		game.sfx("hit", global_position, -14.0)
		game.make_noise(global_position, 40.0, "struggle", self)
		game.stats["takedowns"] = game.stats.get("takedowns", 0) + 1
		_knife_done(KNIFE_CD)
		return
	if e.can_fire_at(self):
		e.point_blank(self)   # he was ready for him
		stagger_t = 0.8
		game.stats["rushes shot"] = game.stats.get("rushes shot", 0) + 1
		_knife_done(KNIFE_CD + 0.5)
		return
	game.sfx("hit", global_position, -4.0)
	game.make_noise(global_position, 160.0, "struggle", self)   # he yells as it goes in
	if e.hp <= RUSH_DMG:
		e.die(dir, self, "death_knees")
	else:
		e.take_hit(RUSH_DMG, dir, self)   # a hard man: he takes it and reels
		e.stagger_t = 0.8
	game.stats["rushes"] = game.stats.get("rushes", 0) + 1
	_knife_done(KNIFE_CD)


func _knife_done(cd: float) -> void:
	knife_t = -1.0
	knife_target = null
	knife_cd = cd
	velocity = Vector2.ZERO


func cycle_weapon(step: int) -> void:
	switch_to(owned[posmod(owned.find(current) + step, owned.size())])


func switch_to(k: String) -> void:
	if k == current or not alive or not k in owned:
		return
	weapon.abort()
	current = k
	weapon = weapons[k]
	switch_t = 0.4
	game.sfx("close", null, -8.0)


func accuracy_mult() -> float:
	var m := 1.0
	if velocity.length() > 5.0:
		m *= 2.0
	if crouched:
		m *= 0.55
	return m + bloom


## Spread ring radius at the aim distance, for the crosshair.
func spread_radius() -> float:
	var deg: float = weapon.d["spread"] * accuracy_mult()
	if weapon.kind == "colt" and weapon.fanning:
		deg += 11.0
	return tan(deg_to_rad(deg)) * aim_dist


## Crouched behind something and not shooting from it: hard to make out. A man who
## fires rises over his cover for a moment, and the flash gives him away.
func low_profile() -> bool:
	return crouched and exposed_t <= 0.0


func on_fired(shake: float) -> void:
	exposed_t = 1.0
	bloom += 0.7 if weapon.kind != "rifle" else 0.4
	game.add_shake(shake)


func take_hit(dmg: int, from_dir: Vector2, shooter: Actor) -> void:
	stop_bandage()
	drop_body()   # (a round in him: he lets go)
	super(dmg, from_dir, shooter)
	if alive:
		game.on_player_hurt()


## Debug autopilot (--bot): shoots the nearest bandit it can see, reloads, cycles guns.
var _bot_t := 0.0
func _bot(delta: float) -> void:
	_bot_t -= delta
	var best: Enemy = null
	var near: Array = game.enemies.filter(func(e): return e.alive)
	near.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	for e in near:   # the nearest one in sight
		if game.line_of_sight(global_position, e.global_position, false):
			best = e
			break
	if best:
		facing = (best.global_position - global_position).normalized()
		if game._args["bot"] == "miss":
			facing = facing.rotated(0.14)   # --bot=miss: shoot past them to rattle them
	if weapon.needs_reload() and not weapon.is_reloading():
		if not weapon.start_reload():
			cycle_weapon(1)
	elif best and _bot_t <= 0.0 and switch_t <= 0.0:
		_bot_t = 0.35
		weapon.trigger()
