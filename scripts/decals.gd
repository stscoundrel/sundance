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
	var tex := Puff.disc_tex()   # (one texture: the lot goes in a few draw calls)
	for s in splats:
		var r: float = s[1]
		draw_texture_rect(tex, Rect2(s[0] - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), false, s[2])
