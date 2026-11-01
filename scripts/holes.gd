class_name Holes
extends Node2D
## Bullet holes in a building's walls, there for good: a child of the building's
## sprite, so they sort and fade with it; the oldest go once there are too many.

const MAX := 150

static var rng := RandomNumberGenerator.new()   # (their own dice: a fight's stay as seeded)

var pts := PackedVector2Array()
var sizes := PackedFloat32Array()
var rim := Color(0.86, 0.72, 0.5, 0.4)   # raw wood round the hole (plaster, on adobe)


func add(p: Vector2) -> void:
	pts.append(p)
	sizes.append(rng.randf_range(0.45, 0.75))
	if pts.size() > MAX:
		pts.remove_at(0)
		sizes.remove_at(0)
	queue_redraw()


func _draw() -> void:
	var tex := Puff.disc_tex()
	for i in pts.size():
		var r := sizes[i]
		draw_texture_rect(tex, Rect2(pts[i] - Vector2.ONE * r * 1.6, Vector2.ONE * r * 3.2), false, rim)
		draw_texture_rect(tex, Rect2(pts[i] - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(0.1, 0.07, 0.06, 0.95))
