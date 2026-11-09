class_name Player
extends Actor
## The gunslinger: WASD to move, mouse to aim. Three slots, one gun in each: a
## revolver or pistol (1), a shotgun (2), a rifle (3), each slot named for the gun
## he can ride in with. He rides in with the guns picked on the loadout screen; a
## dead man's gun for an empty slot is his for walking over it, and one for a slot
## he's filled is a swap (F), his own left lying in its place, as loaded as it was.
## Cartridges go in his belt whether he has the gun for them yet or not.

const ORDER := ["colt", "coach", "rifle"]
const SLOT := {"colts": "colt", "colt": "colt", "schofield": "colt", "buntline": "colt", "navy": "colt", "howdah": "colt", "derringer": "colt", "pistola": "colt",
	"coach": "coach", "spencer82": "coach", "sawnoff": "coach", "champion": "coach", "escopeta": "coach",
	"rifle": "rifle", "henry": "rifle", "spencer": "rifle", "springfield": "rifle", "rollingblock": "rifle", "remington": "rifle"}   # the guns he can take up, by slot
const RESERVE := {"colts": 36, "colt": 30, "schofield": 30, "buntline": 30, "navy": 24, "howdah": 10, "derringer": 12, "pistola": 12,
	"coach": 10, "spencer82": 10, "sawnoff": 10, "champion": 10, "escopeta": 8,
	"rifle": 26, "henry": 26, "spencer": 21, "springfield": 12, "rollingblock": 10, "remington": 12}   # what he rides in with, per gun (to his belt)
const TROPHIES := ["buntline"]   # his only off the dead: not on the loadout screen
const KIT := {"bandage": 1, "dynamite": 2}   # what kit costs on the loadout screen (one of each at most)
const REACH := 13.0   # px: a gun at his feet
# The knife (E). At a man who isn't on to him, anywhere in reach, a silent
# takedown: the last few steps quick and quiet, a hand over his mouth. At one who
# is, a rush: he lunges, and it's decided as he gets there: if the man can shoot
# (gun loaded and ready, facing him, not reeling or reloading) he does,
# point-blank, and the stranger is left stunned in front of him; if not, the knife
# goes in, loudly. One who turns and sees him coming mid-lunge gets the rush.
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
# Silencio's strongbox (see Strongbox): in both arms, heavy. Slower than he walks,
# quicker than he drags a man; crouched, slower again and quiet.
const BOX_SPEED := 0.65
const BOX_CROUCH := 0.4
# The last stand: once a level, the shot that would have killed him puts him down in
# the dirt instead, propped on an elbow with a revolver (his Colt, or one from his
# boot), unable to move but for dragging himself round on the elbow. A bandage gets
# him up, and so does dropping three of them from the dirt; otherwise he shoots till
# he bleeds out or they finish him, and if the last of them falls first, he's won.
const STAND_BLEED := 25.0     # s before he bleeds out
const STAND_BANDAGE_T := 5.0  # s to bind it lying there, gun down
const STAND_TURN := 2.5       # rad/s he can swing round: a man behind him takes over a second to face
const STAND_RISE := 3         # men dropped from the dirt, and he's up on nerve alone
const STAND_SLOW := 1.5       # one-handed, flat on his back: everything takes this much longer
const STAND_GUN_H := 6.0      # px: the gun's height off the dirt
const BOOT_GUNS := ["colt", "schofield", "navy"]
# Dynamite of his own: lit, a wind-up, and lobbed at the cursor. A shorter fuse than
# the gang's: he cuts his own.
const STICK_FUSE := 3.2      # s from lighting to the bang
const STICK_MIN := 40.0      # px: never at his own feet
const STICK_MAX := 230.0
const STICK_FUMBLE := 0.25   # chance a hit in the wind-up makes him drop it at his feet

var weapons := {}               # slot -> the gun in it (or the one he'd ride in with, if empty)
var owned: Array[String] = []   # the slots he has a gun in, in ORDER
var belt := {}                  # spare rounds, by Weapon.ammo()
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
var box: Strongbox = null      # the outlaws' gold in his arms
var lift_t := -1.0             # time bent to it, taking it up; < 0 when not
var grab_t := 0.0
var smear_at := Vector2.ZERO
var exposed_t := 0.0           # he's just fired: up over his cover, flash and smoke
var bandages := 1
var bandage_t := -1.0          # time into bandaging; < 0 when not at it
var down := false              # in his last stand
var medic: Civilian            # the barber-surgeon binding him up, while he keeps still
var stand_used := false        # (once a level)
var down_t := 0.0              # bleeding out
var lie_facing := Vector2.RIGHT   # the way his boots point, lying there
var dirt_drops := 0            # men he's dropped this last stand
var held_before := ""          # the gun he had in hand when he fell
var boot: Weapon = null        # the revolver from his boot, if he had no Colt (or his pair's right gun)
var _bot_down_t := 0.0
var sticks := 0                # dynamite he carries
var stick: Dynamite = null     # lit, in his hand
var throw_t := 0.0             # the wind-up left
var gun: MGun = null           # the machine gun he's on, if he is
var shout := ""                # a line he says, over his head a moment (he hasn't much to say)
var shout_t := 0.0


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
	shout_t = maxf(0.0, shout_t - delta)
	if not alive:
		if dying():
			update_anim(delta)
		return
	if down:
		_down_tick(delta)
		update_anim(delta)
		return
	var playing: bool = game.state == "play"
	knife_cd = maxf(0.0, knife_cd - delta)
	exposed_t = maxf(0.0, exposed_t - delta)
	if knife_t >= 0.0:
		_lunge(delta)
		update_anim(delta)
		return
	if gun:
		_at_gun(delta, playing)
		update_anim(delta)
		return
	var input := Vector2.ZERO
	if playing and not is_staggered():
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * (CROUCH_WALK if crouched else WALK) * limp_factor()
	if dragging:
		velocity = input * WALK * DRAG_SPEED * limp_factor()
	if box:
		velocity = input * WALK * (BOX_CROUCH if crouched else BOX_SPEED) * limp_factor()
		if input != Vector2.ZERO:
			facing = input.normalized()   # (both arms full: he looks where he's going)
	if lift_t >= 0.0:
		velocity = Vector2.ZERO
		lift_t += delta
		if lift_t >= Strongbox.LIFT_T:
			_lifted()
	if bandage_t >= 0.0:
		_bandage(delta, input)
	if stick:
		velocity *= 0.5   # (winding up)
		throw_t -= delta
		if throw_t <= 0.0:
			_let_go()
	move_and_slide()
	_find_knife_target()
	if dragging:
		_drag(delta, input)

	var m := get_global_mouse_position()
	aim_target = game.enemy_under(m)
	var to := aim_ground(m) - global_position
	if to.length() > 3.0 and playing and not dragging and box == null and lift_t < 0.0:
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
	if lift_t >= 0.0:
		return   # (bent to the strongbox)
	if box:
		if Input.is_action_just_pressed("crouch"):
			crouched = not crouched
		for a in ["knife", "fire", "alt", "bandage", "throw", "weapon_1", "weapon_2", "weapon_3"]:
			if Input.is_action_just_pressed(a):
				set_box_down()   # (E to set it down; to shoot, or anything else, he lets it fall)
				return
		return
	if dragging:
		for a in ["fire", "alt", "crouch", "bandage", "weapon_1", "weapon_2", "weapon_3"]:
			if Input.is_action_just_pressed(a):
				drop_body()
				return
		if not Input.is_action_pressed("knife"):
			drop_body()
		return
	var tied: Node = game.rescue()
	if Input.is_action_pressed("knife") and knife_t < 0.0 and bandage_t < 0.0 \
			and tied and tied.can_cut(global_position):
		tied.cutting(get_physics_process_delta_time())   # (the knife at the ropes, not at anyone)
		return
	elif tied:
		tied.cut_t = 0.0
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
	if Input.is_action_just_pressed("throw"):
		light_stick()
	if stick:
		return   # (both hands busy)
	if Input.is_action_just_pressed("take") and not dragging:
		game.swap_gun()
	if Input.is_action_just_pressed("crouch"):
		crouched = not crouched
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
	if Input.is_action_just_pressed("knife") and game.strongbox and game.strongbox.can_take(global_position):
		_lift()
		return
	if Input.is_action_just_pressed("knife") and game.mgun and game.mgun.can_man(global_position):
		get_on(game.mgun)
		return
	if Input.is_action_just_pressed("knife") and game.minefield and game.minefield.can_push(global_position):
		game.minefield.push(self)
		return
	if Input.is_action_just_pressed("knife"):
		knife()
	for i in 3:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_to(ORDER[i])
	if switch_t > 0.0:
		return
	if Input.is_action_just_pressed("fire"):
		weapon.trigger()
	if weapon.kind == "colt":   # (fanning: the Colt's alone)
		weapon.fanning = Input.is_action_pressed("alt")
	elif Input.is_action_just_pressed("alt"):
		weapon.alt_trigger()


## A line from him, over his head for `t` seconds.
func say(s: String, t := 3.5) -> void:
	shout = s
	shout_t = t


## On the machine gun: down behind it, his hands on the grips.
func get_on(g: MGun) -> void:
	gun = g
	g.man(self)
	velocity = Vector2.ZERO
	crouched = true
	anim_gun = "mgun"


func get_off() -> void:
	if gun:
		gun.leave()
	gun = null
	anim_gun = ""
	crouched = false


## A frame on the gun: it goes where the cursor is, as far and as fast as it can
## swing; the trigger held, it fires. E, or a step any way, and he's off it.
func _at_gun(delta: float, playing: bool) -> void:
	velocity = Vector2.ZERO
	crouched = true
	exposed_t = maxf(0.0, exposed_t - delta)
	weapon.update(delta)
	var firing := false
	if playing and not game._args.has("bot"):
		if Input.is_action_just_pressed("knife") or Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
			get_off()
			return
		firing = Input.is_action_pressed("fire")
	var want := aim_ground(get_global_mouse_position()) - gun.global_position
	gun.drive(delta, want.normalized() if playing else Vector2.ZERO, firing)
	facing = gun.aim
	if firing and gun.belt > 0 and action != "fire":
		play_action("fire")   # (the gun shaking in his hands)


## What a loadout costs: its guns' points and its kit's.
static func cost(guns: Array, kit: Array = []) -> int:
	var n := 0
	for k in guns:
		n += int(Weapon.DATA[k].get("points", 0))
	for k in kit:
		n += int(KIT.get(k, 0))
	return n


## The guns that go in each slot, in the order the loadout screen offers them: the
## dearest first, so the best of a slot heads its card (equal prices as SLOT has them).
static func choices(slot: String) -> Array:
	var keys := SLOT.keys()
	var out := keys.filter(func(k): return SLOT[k] == slot and not k in TROPHIES)
	out.sort_custom(func(a, b):
		var pa := int(Weapon.DATA[a].get("points", 0))
		var pb := int(Weapon.DATA[b].get("points", 0))
		return pa > pb if pa != pb else keys.find(a) < keys.find(b))
	return out


## The guns he rides in with (at least one, one a slot), each with its cartridges.
func arm(guns: Array) -> void:
	owned.clear()
	belt.clear()
	for slot in ORDER:
		var mine: Array = guns.filter(func(k): return SLOT.get(k, "") == slot)
		weapons[slot] = Weapon.new(slot if mine.is_empty() else mine[0], self)
		if not mine.is_empty():
			owned.append(slot)
			weapons[slot].reserve += RESERVE[mine[0]]
	current = owned[0]
	weapon = weapons[current]


## A gun off the ground into its slot, loaded as it lies (`w`: how it was left, or
## null for a dead man's, some of it fired off). Whatever was in the slot goes down
## at his feet in its place; returns it, or null if the slot was empty.
func take_up(k: String, w: Weapon = null) -> Weapon:
	var slot: String = SLOT[k]
	var gun := Weapon.new(k, self)
	if w:
		gun.copy_load(w)
	else:
		gun.part_spent()
	var old: Weapon = weapons[slot] if slot in owned else null
	if old:
		old.abort()
		old.fanning = false
	weapons[slot] = gun
	if not slot in owned:
		owned.append(slot)
		owned.sort_custom(func(a, b): return ORDER.find(a) < ORDER.find(b))
	if slot == current or old:
		current = slot   # (a swap: it's the one in his hand now)
		weapon = gun
		switch_t = 0.3
	game.sfx("pickup", null, 0.0)
	game.sfx("close", null, -6.0)
	return old


## The gun lying at his feet he could take up (F), or {}: the one nearest, of those
## he can carry, his own last-dropped aside if there's another.
func gun_at_feet() -> Dictionary:
	var best: Dictionary = {}
	var best_d := REACH
	for g in game.loose_guns:
		if not SLOT.has(g["kind"]):
			continue
		var dd: float = global_position.distance_to(g["at"])
		if g.get("his", false):
			dd += 4.0
		if dd < best_d:
			best_d = dd
			best = g
	return best


# ------------------------------------------------------------------ the dead

## Where a shot at the cursor goes, on the ground plane rounds fly over: at a bandit
## under it, his middle; at the man on the gallows (or the rope he hangs from), drawn
## well up off the dirt, the trap they're over; else the dirt at gun height below it.
func aim_ground(m: Vector2) -> Vector2:
	var e: Enemy = game.enemy_under(m)
	if e:
		return e.aim_point()
	if game.hanging and game.hanging.under(m):
		return game.hanging.trap
	return m + Vector2(0, gun_height())


## Bent to the strongbox, the gun put away: up with it in a second.
func _lift() -> void:
	weapon.abort()
	weapon.fanning = false
	lift_t = 0.0
	anim_gun = "strongbox"
	pose = "pick"
	game.sfx("step", null, -10.0, 0.1)


func _lifted() -> void:
	lift_t = -1.0
	var b: Strongbox = game.strongbox
	if b == null or not b.can_take(global_position):
		anim_gun = ""
		pose = ""
		return   # (somebody else got it first)
	box = b
	b.take(self)
	pose = "carry"
	game.stats["took the gold"] = game.stats.get("took the gold", 0) + 1


## Set it down in front of him (or let it drop, to have his hands free).
func set_box_down() -> void:
	var b := box
	box = null
	anim_gun = ""
	pose = ""
	if b and b.holder == self:
		b.put_down(global_position + facing * 8.0)


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
	if down:   # flat on his back, the gun put down, binding it
		weapon.abort()
		bandage_t = 0.0
		_pose_stand("gasp_sink")
		game.sfx("tear", global_position, -6.0, 0.1)
		game.make_noise(global_position, 45.0, "step", self)
		return true
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
	if down:
		_pose_stand("gasp_rise")   # (back up on his elbow)
	game.hud.toast("Bandaging broken off")
	game.stats["bandaging broken off"] = game.stats.get("bandaging broken off", 0) + 1


# ------------------------------------------------------------------ dynamite

## Lit off his cigar: a wind-up, then it's away (see _let_go).
func light_stick() -> bool:
	if sticks <= 0 or stick or bandage_t >= 0.0 or knife_t >= 0.0 or dragging or down:
		return false
	sticks -= 1
	weapon.abort()
	weapon.fanning = false
	stick = Dynamite.new()
	game.world.add_child(stick)
	stick.setup(game, self)
	stick.fuse = STICK_FUSE
	throw_t = Enemy.WINDUP
	play_action("throw")
	game.stats["his dynamite"] = game.stats.get("his dynamite", 0) + 1
	return true


## Away towards the cursor (as near or as far as he can throw).
func _let_go() -> void:
	var to := get_global_mouse_position()
	if game._args.has("throw-at"):   # (for the tests: grid x,y)
		var xy: PackedStringArray = game._args["throw-at"].split(",")
		to = Iso.to_screen(Vector2(float(xy[0]), float(xy[1])))
	var off := to - global_position
	to = global_position + off.normalized() * clampf(off.length(), STICK_MIN, STICK_MAX)
	stick.throw(to)
	stick = null


## Hit with it lit in his hand: now and then it falls at his feet. Run.
func _drop_stick(sure := false) -> void:
	if stick and (sure or game.loot_rng.randf() < STICK_FUMBLE):
		stick.drop()
		stick = null
		throw_t = 0.0


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
		knife_silent = knife_cand.downed or knife_cand.unaware()


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
		e.silent_death = true
		e.finish(self)
		game.make_noise(global_position, 40.0, "struggle", self)
		_knife_done(KNIFE_CD)
		return
	if knife_quiet and e.unaware():
		# a hand over his mouth, the blade, and he's let down quietly
		e.silent_death = true
		e.die(dir, self, "death_slump")
		e.killed_with = "knife"
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
		e.killed_with = "knife"
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
	if down:
		_pose_stand("gasp_fire")
	exposed_t = 1.0
	if not gun:   # (the machine gun's on its tripod: it throws its own spread, not his hands')
		bloom += 0.7 if weapon.kind != "rifle" else 0.4
	game.add_shake(shake)


func gun_height() -> float:
	return STAND_GUN_H if down else super()


func take_hit(dmg: int, from_dir: Vector2, shooter: Actor) -> void:
	stop_bandage()
	drop_body()   # (a round in him: he lets go)
	_drop_stick(hp - dmg <= 0)
	if alive and not down and hp - dmg <= 0 and _goes_down(dmg, shooter):
		flash_t = 0.12
		game.blood(global_position, from_dir, gun_height())
		game.sfx("hit", global_position, -2.0)
		_go_down(from_dir, shooter)
		return
	super(dmg, from_dir, shooter)
	if alive:
		game.on_player_hurt()


func die(from_dir: Vector2, shooter: Actor = null, how := "") -> void:
	get_off()
	if down:   # where he lies, the gun falling from his hand
		how = weapon.kind + "/gasp_die"
		from_dir = -lie_facing
		down = false
		propped = false
	super(from_dir, shooter, how)


# ------------------------------------------------------------------ the last stand

## Not twice in a level, and not from what nobody gets up from: the heart of a
## blast, or a scattergun at arm's length.
func _goes_down(dmg: int, shooter: Actor) -> bool:
	if stand_used or Engine.has_meta("no_last_stand"):
		return false
	if blasted and dmg >= 8:
		return false
	if shooter and shooter.weapon and shooter.weapon.is_shotgun() \
			and shooter.global_position.distance_to(global_position) < 60.0:
		return false
	return true


func _go_down(from_dir: Vector2, shooter: Actor) -> void:
	get_off()
	stand_used = true
	down = true
	down_t = 0.0
	hp = 1
	bleeding = true
	knife_t = -1.0
	crouched = true   # (low: low cover between him and them stops everything)
	velocity = Vector2.ZERO
	weapon.abort()
	weapon.fanning = false
	held_before = current
	dirt_drops = 0
	if "colt" in owned and weapons["colt"].d.get("twin", false):
		# a pair: one hand's on the dirt, so the right gun alone, as loaded as it is
		switch_to("colt")
		switch_t = 0.0
		boot = Weapon.new("colt", self)
		for i in 6:
			boot.chambers[i] = weapons["colt"].chambers[i * 2]
		boot.cur = maxi(0, boot.chambers.find(1))
		weapon = boot
	elif "colt" in owned:   # (his revolver, or whatever pistol he's taken up in its place)
		switch_to("colt")
		switch_t = 0.0
	else:   # a revolver out of his boot, loaded, and whatever rounds for it he has on his belt
		boot = Weapon.new(BOOT_GUNS.pick_random(), self)
		weapon = boot
	weapon.slow = STAND_SLOW
	lie_facing = -from_dir if from_dir.length() > 0.1 else facing
	facing = lie_facing
	propped = true
	_pose_stand("gasp_rise")
	game.on_player_down(shooter)


func _pose_stand(anim_name: String) -> void:
	_death = weapon.kind + "/" + anim_name
	_layers.erase("full")
	lie_dir = -1
	_lay_hurtbox()


func _down_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	var playing: bool = game.state == "play"
	if playing:
		down_t += delta
		if down_t >= STAND_BLEED:
			game.stats["bled out"] = 1
			die(-lie_facing, null)
			return
	weapon.update(delta)
	if bandage_t >= 0.0:
		bandage_t += delta
		if playing and not game._args.has("bot"):
			for a in ["fire", "reload"]:
				if Input.is_action_just_pressed(a):
					stop_bandage()
					return
		if bandage_t >= STAND_BANDAGE_T:
			_get_up()
		return
	if (_death.ends_with("gasp_rise") or _death.ends_with("gasp_fire")) and not dying():
		_pose_stand("gasp_aim")
	# the gun swung round, slowly, and him with it on his elbow
	var want := facing
	if game._args.has("bot"):
		var near := _bot_target()
		if near:
			want = (near.global_position - global_position).normalized()
	else:
		var m := get_global_mouse_position()
		aim_target = game.enemy_under(m)
		var target := aim_target.aim_point() if aim_target else m
		aim_dist = global_position.distance_to(target)
		if aim_dist > 3.0:
			want = (target - global_position).normalized()
	swing_to(want, delta)
	bloom = max(0.0, bloom - delta * 2.0)
	if not playing or _death.ends_with("gasp_rise"):
		return
	if game._args.has("bot"):
		_bot_down_t -= delta
		if weapon.needs_reload() and not weapon.is_reloading():
			weapon.start_reload()
		elif _bot_target() and _bot_down_t <= 0.0:
			_bot_down_t = 0.6
			weapon.trigger()
		return
	if Input.is_action_just_pressed("bandage"):
		start_bandage()
	elif Input.is_action_just_pressed("reload"):
		weapon.start_reload()
	elif Input.is_action_just_pressed("fire"):
		weapon.trigger()


## Round towards where he wants the gun, as fast as a man can drag himself on one
## elbow: his boots follow, and so does the length of him a bullet can find.
func swing_to(want: Vector2, delta: float) -> void:
	var d8 := Iso.dir8(facing)
	var turn := clampf(facing.angle_to(want), -STAND_TURN * delta, STAND_TURN * delta)
	facing = facing.rotated(turn)
	lie_facing = facing
	if Iso.dir8(facing) != d8:
		lie_dir = -1
		_lay_hurtbox()


## Another of them dropped from the dirt: the third and he's getting up, still
## bleeding, on nothing but nerve (his bandage kept for later).
func dropped_one() -> void:
	dirt_drops += 1
	if dirt_drops == STAND_RISE:
		_rise.call_deferred()   # (after the rest of this moment: if it was the last of them, it's a win)


func _rise() -> void:
	if not down or not alive or game.state != "play":
		return
	_get_up(false, true)
	game.on_player_rise()


## The barber-surgeon's done with him: whole again, the bleeding and the limp
## stopped, and up out of the dirt if that's where he was (his own bandage kept).
func patched_up() -> void:
	if down:
		_get_up(false)
	bandage_t = -1.0   # (if he was at it himself: he keeps the bandage)
	pose = ""
	hp = max_hp
	limp_t = 0.0
	bleeding = false
	game.hud.toast("Patched up")
	game.stats["patched up"] = game.stats.get("patched up", 0) + 1


## Bound up: back on his feet, one bar of him left and a limp, the gun he had (still
## bleeding if it was nerve that got him up, not a bandage).
func _get_up(own := true, nerve := false) -> void:
	down = false
	propped = false
	bandage_t = -1.0
	if own:
		bandages -= 1
	hp = 1
	bleeding = nerve
	limp_t = 6.0
	weapon.slow = 1.0
	if boot and weapons["colt"].d.get("twin", false) and "colt" in owned:
		for i in 6:   # the right gun goes back to being half of the pair
			weapons["colt"].chambers[i * 2] = boot.chambers[i]
	boot = null
	current = held_before
	weapon = weapons[held_before]
	_death = ""
	_layers.erase("full")
	legs_spr.visible = true
	_stand_hurtbox()
	if not nerve:
		game.hud.toast("Back on your feet")
	game.stats["got up"] = game.stats.get("got up", 0) + 1


func _bot_target() -> Enemy:
	var best: Enemy = null
	for e in game.enemies:
		if e.alive and game.line_of_sight(global_position, e.global_position, false) and \
				(best == null or e.global_position.distance_to(global_position) < best.global_position.distance_to(global_position)):
			best = e
	return best


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
