class_name Actor
extends CharacterBody2D
## Shared body for the hero and the bandits: 8-direction sprite sheet, hurtbox,
## facing, crouching and damage.

signal died(actor: Actor)

const LOOPS := {"walk": 7.0, "cwalk": 4.0, "cower": 5.0}

var game: Node
var sprite: Sprite2D
var hurtbox: Area2D
var weapon: Weapon
var facing := Vector2.RIGHT
var crouched := false
var alive := true
var hp := 2
var max_hp := 2
var is_player := false
var anim_t := 0.0
var flash_t := 0.0
var pose := ""   # held animation set by the AI each frame: "point", "flinch", "cower"
var pose_t := 0.0
var _last_pose := ""
var anims := {}   # {name: [first column, frames]} from the sprite sheet metadata
var action := ""
var action_t := 0.0
var action_len := 1.0


func setup_body(g: Node, pos: Vector2) -> void:
	game = g
	global_position = pos
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = Iso.LAYER_ACTOR
	collision_mask = Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 4.0
	cs.shape = c
	add_child(cs)

	hurtbox = Area2D.new()
	hurtbox.collision_layer = Iso.LAYER_HURT
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	var hs := CollisionShape2D.new()
	var hc := CircleShape2D.new()
	hc.radius = 7.0
	hs.shape = hc
	hurtbox.add_child(hs)
	hurtbox.set_meta("actor", self)
	add_child(hurtbox)

	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)


func set_sheet(key: String) -> void:
	var m: Dictionary = game.meta["chars"][key]
	sprite.texture = game.tex(m["file"])
	sprite.hframes = int(m["cols"])
	sprite.vframes = int(m["rows"])
	sprite.scale = Vector2.ONE * game.tex_scale
	sprite.offset = -Vector2(m["anchor"][0], m["anchor"][1])
	anims = m["anims"]


## Plays a one-shot animation ("hurt", "fire", "fall") over `length` seconds; it
## takes priority over poses and movement.
func play_action(anim: String, length: float) -> void:
	if not anims.has(anim):
		return
	action = anim
	action_t = length
	action_len = length


func update_anim(delta: float) -> void:
	var speed := velocity.length()
	var moving := speed > 4.0
	anim_t += delta * (speed / 40.0 if moving else 1.0)
	action_t = max(0.0, action_t - delta)
	if pose != _last_pose:
		_last_pose = pose
		pose_t = 0.0
	pose_t += delta

	var anim := "idle"
	var f := 0
	if not alive:
		anim = "fall" if action == "fall" and action_t > 0.0 else "dead"
	elif action_t > 0.0:
		anim = action
		f = int((1.0 - action_t / action_len) * anims[anim][1])
	elif pose != "":
		anim = pose
		# held poses play through once and hold the last frame; LOOPS keep cycling
		f = int(pose_t * LOOPS[pose]) if LOOPS.has(pose) else min(int(pose_t * 6.0), anims[pose][1] - 1)
	elif crouched:
		anim = "cwalk" if moving else "crouch"
		f = int(anim_t * LOOPS["cwalk"])
	elif moving:
		anim = "walk"
		f = int(anim_t * LOOPS["walk"])
	var a: Array = anims[anim]
	sprite.frame = Iso.dir8(facing) * sprite.hframes + int(a[0]) + posmod(f, int(a[1]))
	if flash_t > 0.0:
		flash_t -= delta
		sprite.modulate = Color(1.8, 0.8, 0.7) if flash_t > 0.0 else Color.WHITE


func gun_height() -> float:
	var h := Iso.GUN_H_CROUCH if crouched else Iso.GUN_H
	if weapon and weapon.kind == "coach":
		h -= 3.0   # carried at the hip
	return h


## Spread multiplier applied to the weapon's base spread.
func accuracy_mult() -> float:
	return 1.0


func on_fired(_shake: float) -> void:
	pass


func take_hit(dmg: int, from_dir: Vector2, _shooter: Actor) -> void:
	if not alive:
		return
	hp -= dmg
	flash_t = 0.12
	game.blood(global_position, from_dir, gun_height())
	game.sfx("hit", global_position, -2.0)
	if hp <= 0:
		die(from_dir)
	else:
		play_action("hurt", 0.9)


func die(from_dir: Vector2) -> void:
	alive = false
	crouched = false
	flash_t = 0.0
	sprite.modulate = Color.WHITE
	pose = ""
	velocity = Vector2.ZERO
	facing = -from_dir
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("collision_layer", 0)
	if weapon:
		weapon.abort()
	play_action("fall", 0.6)
	update_anim(0.0)
	died.emit(self)
