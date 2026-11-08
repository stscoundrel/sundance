class_name Snowfall
extends Node2D
## Snow coming down out of a grey sky (a map's "weather": "snow", Silencio's). The
## flakes are in the world, so they pan with the town rather than the screen, and
## wrap round the view as the camera goes: three depths of them, the far ones fine
## and slow and faint, the nearest bigger, quicker and whiter, all of them drifting
## on the wind and swaying as they fall. Only looks: its own dice, and nothing in
## the game asks it anything (what the snow does to a man's sight is to come).

const COUNT := 900
const MARGIN := 24.0   # px past the view's edge, so a flake doesn't pop in at it
const WIND := 9.0      # px/s, east across the screen
const FALL := Vector2(12.0, 32.0)   # px/s, far to near

var rng := RandomNumberGenerator.new()
var flakes: Array[Vector4] = []   # x, y, depth (0 far .. 1 near), sway phase
var t := 0.0


func _ready() -> void:
	rng.seed = 97
	z_as_relative = false
	z_index = 60   # (over the town and everyone in it)
	for i in COUNT:
		flakes.append(Vector4(rng.randf_range(0.0, 4000.0), rng.randf_range(0.0, 4000.0), rng.randf(), rng.randf() * TAU))


## The world the camera shows, and a margin round it.
func _view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom if cam else Vector2.ONE
	var size := get_viewport_rect().size / zoom
	var c := cam.get_screen_center_position() if cam else size * 0.5
	return Rect2(c - size * 0.5 - Vector2.ONE * MARGIN, size + Vector2.ONE * MARGIN * 2.0)


func _process(delta: float) -> void:
	t += delta
	var v := _view()
	for i in flakes.size():
		var f := flakes[i]
		f.x += (WIND * (0.5 + f.z) + sin(t * 1.3 + f.w) * 6.0) * delta
		f.y += lerpf(FALL.x, FALL.y, f.z) * delta
		f.x = v.position.x + fposmod(f.x - v.position.x, v.size.x)
		f.y = v.position.y + fposmod(f.y - v.position.y, v.size.y)
		flakes[i] = f
	queue_redraw()


## White on white is nothing: the nearer flakes carry a grey underside, so they show
## against the snow on the ground as well as against a wall or a man.
func _draw() -> void:
	for f in flakes:
		var at := Vector2(f.x, f.y).floor()
		var s := 2.0 if f.z > 0.6 else 1.0
		if f.z > 0.35:
			draw_rect(Rect2(at + Vector2(0, s), Vector2(s, 1)), Color(0.42, 0.46, 0.56, 0.45 * f.z))
		draw_rect(Rect2(at, Vector2(s, s)), Color(0.96, 0.97, 1.0, lerpf(0.4, 1.0, f.z)))
