class_name Peso
extends Node2D
## A silver peso flicked from the stranger's thumb: a short, spinning arc (it goes
## over a crate, not a wall), and where it comes down it clinks and lies there for
## whoever wants it (game.peso_landed).

const GRAVITY := 420.0
const HAND := 12.0       # px up: where it leaves his hand

var game: Node
var z := HAND
var vz := 0.0
var gv := Vector2.ZERO   # ground-plane velocity
var spin := 0.0          # (a coin turning over: how much of it you see)


func setup(g: Node, from: Vector2, to: Vector2) -> void:
	game = g
	global_position = from + Vector2(0, 1)
	var t := clampf(from.distance_to(to) / 260.0, 0.3, 0.6)
	gv = (to - from) / t
	vz = (GRAVITY * t * t * 0.5 - z) / t


func _physics_process(delta: float) -> void:
	if game.state != "play":
		return
	var next := global_position + gv * delta
	var mask := Iso.LAYER_WALL | (Iso.LAYER_COVER if z < 7.0 else 0)
	var hit: Dictionary = game.ray(global_position, next, mask)
	if hit.is_empty():
		global_position = next
	else:
		gv = gv.bounce(hit["normal"]) * 0.3   # (off the wall and down)
	vz -= GRAVITY * delta
	z += vz * delta
	spin += delta * 30.0
	if z <= 0.0:
		game.peso_landed(global_position)
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 2.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2(0, -z), 0.0, Vector2(maxf(0.15, absf(cos(spin))), 1.0))
	draw_circle(Vector2.ZERO, 2.2, Color(0.85, 0.85, 0.8))
	draw_set_transform(Vector2.ZERO)
