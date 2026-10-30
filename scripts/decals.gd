class_name Decals
extends Node2D
## Blood and other marks drawn flat on the ground (as iso ellipses).

var splats: Array = []


func add(p: Vector2, r: float, c: Color) -> void:
	splats.append([p, r, c])
	if splats.size() > 500:
		splats.pop_front()
	queue_redraw()


func _draw() -> void:
	for s in splats:
		draw_set_transform(s[0], 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, s[1], s[2])
	draw_set_transform(Vector2.ZERO)
