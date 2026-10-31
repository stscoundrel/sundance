class_name Player
extends Actor
## The gunslinger: WASD to move, mouse to aim. He rides in with the guns picked on
## the loadout screen and takes up any of the others a dead man drops by walking
## over it; cartridges go in his belt whether he has the gun for them yet or not.

const ORDER := ["colt", "coach", "rifle"]
const RESERVE := {"colt": 30, "coach": 10, "rifle": 26}   # what he rides in with, per gun
const WALK := 46.0
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
	var input := Vector2.ZERO
	if playing:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * (CROUCH_WALK if crouched else WALK) * limp_factor()
	move_and_slide()

	var m := get_global_mouse_position()
	aim_target = game.enemy_under(m)
	var target := m + Vector2(0, gun_height())
	if aim_target:
		target = aim_target.global_position
	var to := target - global_position
	if to.length() > 3.0 and playing:
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
	if Input.is_action_just_pressed("crouch"):
		crouched = not crouched
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
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


func on_fired(shake: float) -> void:
	bloom += 0.7 if weapon.kind != "rifle" else 0.4
	game.add_shake(shake)


func take_hit(dmg: int, from_dir: Vector2, shooter: Actor) -> void:
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
