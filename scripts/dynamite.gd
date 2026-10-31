class_name Dynamite
extends Node2D
## A lit stick of dynamite: in a bandit's hand while he winds up, then lobbed in an
## arc (over crates, not over walls), bouncing and rolling to a stop, its fuse
## fizzing all the while. Once it's lit, it's lit: if he goes down holding it, it
## blows where he fell. On the ground a ring shows how far the blast will reach.

const R := 80.0          # px: the blast reaches this far
const CORE := 32.0       # px: this close, nobody lives through it
const FUSE := 6.0        # s from lighting to the bang (4-5 s of it on the ground)
const GRAVITY := 420.0
const HAND := 14.0       # px up: where it leaves his hand

enum S { HELD, FLY, GROUND }

var game: Node
var by: Enemy            # who lit it (and gets the blame)
var st := S.HELD
var fuse := FUSE
var z := 0.0
var vz := 0.0
var gv := Vector2.ZERO   # ground-plane velocity
var spin := 0.0
var angle := 0.0
var landed := false
var ring: Node2D
var hiss: AudioStreamPlayer2D


func setup(g: Node, thrower: Enemy) -> void:
	game = g
	by = thrower
	global_position = thrower.global_position + Vector2(0, 1)
	ring = Node2D.new()
	ring.z_as_relative = false
	ring.z_index = -9   # on the ground: over the view cones, under everyone
	ring.draw.connect(_draw_ring)
	add_child(ring)
	if game._streams.has("fuse"):
		hiss = AudioStreamPlayer2D.new()
		hiss.stream = game._streams["fuse"][0]
		hiss.volume_db = -8.0
		hiss.max_distance = 900.0
		add_child(hiss)
		hiss.play()


## Out of his hand towards `to`, landing there (walls and bounces permitting).
func throw(to: Vector2) -> void:
	st = S.FLY
	z = HAND
	var d := global_position.distance_to(to)
	var t := clampf(d / 210.0, 0.45, 0.95)
	gv = (to - global_position) / t
	vz = (GRAVITY * t * t * 0.5 - z) / t
	spin = randf_range(9.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)


## Let go of where he stands (shot, stabbed or fumbled): it tumbles to his feet.
func drop() -> void:
	if st != S.HELD:
		return
	st = S.FLY
	z = HAND * 0.8
	vz = 30.0
	gv = Vector2.from_angle(randf() * TAU) * randf_range(10.0, 30.0)
	spin = randf_range(4.0, 8.0)
	game.stats["dynamite dropped"] = game.stats.get("dynamite dropped", 0) + 1


func _physics_process(delta: float) -> void:
	if game.state == "title" or game.state == "loadout":
		return
	fuse -= delta
	if fuse <= 0.0:
		game.blast(global_position, by)
		game.lit.erase(self)
		queue_free()
		return
	if st == S.HELD:
		global_position = by.global_position + Vector2(0, 1)
	else:
		_move(delta)
	queue_redraw()
	ring.queue_redraw()


func _move(delta: float) -> void:
	if gv.length() > 0.5:
		var next := global_position + gv * delta
		# a lob clears crates; low down, or rolling, it doesn't
		var mask := Iso.LAYER_WALL | (Iso.LAYER_COVER if z < 7.0 else 0)
		var hit: Dictionary = game.ray(global_position, next, mask)
		if hit.is_empty():
			global_position = next
		else:
			gv = gv.bounce(hit["normal"]) * 0.4
	if st == S.FLY:
		angle += spin * delta
		vz -= GRAVITY * delta
		z += vz * delta
		if z <= 0.0:
			z = 0.0
			if not landed:
				landed = true
				game.stick_landed(self)
			if vz < -60.0:
				vz = -vz * 0.3   # a hop
				gv *= 0.5
				spin *= 0.5
			else:
				st = S.GROUND
				vz = 0.0
				gv *= 0.5
	else:
		gv *= pow(0.015, delta)   # rolling in the dirt, slowing fast
		angle += gv.length() * delta * 0.25
		if gv.length() < 2.0:
			gv = Vector2.ZERO


func _draw() -> void:
	if st == S.HELD:
		return   # it's in his hand (the pose draws it)
	var sh := clampf(1.0 - z / 40.0, 0.4, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 3.0 * sh, Color(0, 0, 0, 0.35 * sh))
	var at := Vector2(0, -z - 1.5)
	draw_set_transform(at, angle, Vector2.ONE)
	draw_rect(Rect2(-2.6, -0.9, 5.2, 1.8), Color(0.66, 0.13, 0.1))
	draw_rect(Rect2(-2.6, -0.9, 5.2, 0.6), Color(0.82, 0.24, 0.18))
	draw_rect(Rect2(-0.4, -0.9, 0.8, 1.8), Color(0.85, 0.78, 0.6))   # the paper band
	draw_line(Vector2(2.6, 0), Vector2(3.8, -0.6), Color(0.2, 0.16, 0.12), 0.5)
	# the fuse fizzing: a hot spark spitting bits
	var tip := Vector2(3.9, -0.7)
	var flick := randf()
	draw_circle(tip, 0.7 + 0.5 * flick, Color(1.0, 0.92, 0.55, 0.95))
	for i in 3:
		draw_rect(Rect2(tip + Vector2(randf_range(-3, 3), randf_range(-3, 1)), Vector2(0.6, 0.6)), Color(1.0, 0.7, 0.3, randf()))
	draw_set_transform(Vector2.ZERO)


## The blast's reach, drawn on the ground once it's down: a ring of dashes that
## turns and pulses quicker as the fuse burns down.
func _draw_ring() -> void:
	if not landed:
		return
	var urgency: float = 1.0 - fuse / FUSE
	var pulse: float = 0.5 + 0.5 * sin(game.clock * (6.0 + 18.0 * urgency))
	var col := Color(0.95, 0.24, 0.1, 0.6 + 0.35 * pulse)
	ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	ring.draw_circle(Vector2.ZERO, R, Color(0.92, 0.26, 0.12, 0.09 + 0.07 * pulse))
	var n := 28
	var turn: float = game.clock * 0.8
	for i in n:
		var a0: float = turn + TAU * i / n
		ring.draw_arc(Vector2.ZERO, R, a0, a0 + TAU / n * 0.55, 3, col, 2.5)
	ring.draw_set_transform(Vector2.ZERO)
