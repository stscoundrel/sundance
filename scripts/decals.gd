class_name Decals
extends Node2D
## Blood and other marks drawn flat on the ground (as iso ellipses). In the rain
## (the funeral's: see Snowfall) the blood washes out: `wash` thins every red mark
## by so much of its life, and one washed through is gone. Whatever bleeds says so
## when it makes its mark (`add`'s `blood`).

var splats: Array = []


func add(p: Vector2, r: float, c: Color, blood := false) -> void:
	splats.append([p, r, c, 0.0 if blood else -1.0, c.a])   # (where, size, colour, how far washed out (-1: no blood, it stays), its first alpha)
	if splats.size() > 500:
		splats.pop_front()
	queue_redraw()


func _draw() -> void:
	var tex := Puff.disc_tex()   # (one texture: the lot goes in a few draw calls)
	for s in splats:
		var r: float = s[1]
		draw_texture_rect(tex, Rect2(s[0] - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), false, s[2])


## The rain at the blood: `by` of a mark's life washed off each (1 is the lot).
func wash(by: float) -> void:
	var changed := false
	for i in range(splats.size() - 1, -1, -1):
		var s: Array = splats[i]
		if s[3] < 0.0:
			continue
		changed = true
		s[3] = minf(1.0, s[3] + by)
		if s[3] >= 1.0:
			splats.remove_at(i)
		else:
			s[2] = Color(s[2].r, s[2].g, s[2].b, s[4] * (1.0 - s[3]))
	if changed:
		queue_redraw()
