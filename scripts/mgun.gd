class_name MGun
extends Node2D
## The Colt-Browning M1895 at Paso Esperanza (the map's "mg"), on its low tripod in
## the corner of its own nest of sandbags: the "potato digger", the lever under the
## muzzle swinging with every round. The stranger gets on it with E and off again
## with E or a step away; on it, he can't move, and the gun swings only so fast and
## only so far: half a circle, to the south and east, where the army comes from. It
## has the one belt, 250 rounds, seven or eight a second while the trigger's held,
## each through a man and on into the next. Then it's silent for good, and the
## federales can't use it either. Its rounds go over the nest round it (they clear
## low cover close by further than a man's do), so it fires into nothing of ours.

static var rng := RandomNumberGenerator.new()   # (the spread: its own dice)

const BELT := 250
const RATE := 7.5           # rounds a second
const ARC := PI * 0.5       # either side of straight out
const TRAVERSE := 1.8       # rad/s it swings
const REACH := 24.0         # px from the gunner's place: near enough to get on it
const OWN_COVER := 64.0     # px: low cover this near, its rounds go over
const DAMAGE := 3
const PIERCE := 2           # through a man and into the next, and the next
const RANGE := 760.0
const SPEED := 1000.0
const SPREAD := 1.4         # degrees

var game: Node
var belt := BELT
var seat := Vector2.ZERO    # where the gunner crouches, behind the tripod
var centre := Vector2.DOWN  # straight out (on screen): the arc's middle
var aim := Vector2.DOWN
var gunner: Player = null
var spr: Sprite2D
var cd := 0.0
var _frame := -1
var _ticked := -1           # (the physics frame its clock last ran: once a frame, whoever drives it)


func setup(g: Node, at: Vector2) -> void:
	game = g
	seat = Iso.to_screen(at)
	centre = Iso.to_screen(Vector2(1.0, 1.0)).normalized()   # (the map's south-east)
	aim = centre
	position = seat + centre * 9.0
	spr = Sprite2D.new()
	spr.centered = false
	spr.scale = Vector2.ONE * g.tex_scale
	add_child(spr)
	_show()


func _show() -> void:
	var i := posmod(int(round(aim.angle() / (TAU / 16.0))), 16)
	if i == _frame:
		return
	_frame = i
	var f: Dictionary = game.meta["mgun"][i]
	spr.texture = game.tex(f["file"])
	spr.offset = -Vector2(f["anchor"][0], f["anchor"][1])


## Close enough, and nobody on it?
func can_man(p: Vector2) -> bool:
	return gunner == null and p.distance_to(seat) < REACH


func man(p: Player) -> void:
	gunner = p
	p.global_position = seat
	game.hud.toast("The Colt-Browning: %d in the belt" % belt if belt > 0 else "The belt's spent")


func leave() -> void:
	gunner = null


## A frame on it: swing towards where he wants it (within the arc, at its own
## pace), and fire while he holds the trigger.
func drive(delta: float, want: Vector2, firing: bool) -> void:
	if want.length() > 0.1:
		var target := centre.rotated(clampf(centre.angle_to(want), -ARC, ARC))
		aim = aim.rotated(clampf(aim.angle_to(target), -TRAVERSE * delta, TRAVERSE * delta))
	_show()
	if _ticked != Engine.get_physics_frames():
		_ticked = Engine.get_physics_frames()
		cd -= delta
	if not firing or cd > 0.0:
		return
	if belt <= 0:
		game.sfx("dry", global_position, -4.0, 0.0)
		cd = 0.5
		return
	cd += 1.0 / RATE
	if cd < 0.0:
		cd = 0.0
	_fire()


func _fire() -> void:
	belt -= 1
	var origin := global_position + aim * 14.0
	var a := clampf(rng.randfn(0.0, deg_to_rad(SPREAD) * 0.5), -deg_to_rad(SPREAD) * 1.5, deg_to_rad(SPREAD) * 1.5)
	game.spawn_bullet(origin, aim.rotated(a) * SPEED, RANGE, DAMAGE, gunner, Iso.GUN_H_CROUCH, false, PIERCE, OWN_COVER)
	_flash(origin)
	game.sfx("mg", global_position, -2.0, 0.08)
	game.make_noise(global_position, 700.0, "shot", gunner)
	gunner.on_fired(1.2)
	game.stats["mg rounds"] = game.stats.get("mg rounds", 0) + 1
	if belt == 0:
		game.hud.toast("The belt's spent")


## The muzzle flash, and a wisp from the barrel.
func _flash(at: Vector2) -> void:
	var m: Dictionary = game.meta["muzzle"]
	var s := Sprite2D.new()
	s.texture = game.tex(m["file"])
	s.hframes = int(m["frames"])
	s.frame = rng.randi() % 2
	s.position = at + Vector2(0, -12)
	s.scale = Vector2.ONE * game.tex_scale
	game.world.add_child(s)
	get_tree().create_timer(0.04, false).timeout.connect(s.queue_free)
	if belt % 3 == 0:
		var puff := Puff.new()
		puff.position = at
		var shade := rng.randf_range(0.8, 0.92)
		puff.smoke(Vector2(0, -12), aim * rng.randf_range(10, 30) + Vector2(0, -6), rng.randf_range(1.2, 2.0),
			rng.randf_range(1.5, 2.5), Color(shade, shade * 0.97, shade * 0.93, 0.3), 2.0, game.WIND)
		game.world.add_child(puff)
