class_name Iso
## Isometric helpers and shared constants. Gameplay runs on the screen-space ground
## plane; grid coordinates (tiles) map to it with a 2:1 diamond projection.

const LAYER_WALL := 1
const LAYER_COVER := 2
const LAYER_POST := 4
const LAYER_ACTOR := 8
const LAYER_HURT := 16
const LAYER_PICKUP := 32

const GUN_H := 21.0
const GUN_H_CROUCH := 14.0


static func to_screen(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * 16.0, (g.x + g.y) * 8.0)


static func to_grid(s: Vector2) -> Vector2:
	return Vector2((s.x / 16.0 + s.y / 8.0) * 0.5, (s.y / 8.0 - s.x / 16.0) * 0.5)


static func rect_poly(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([
		to_screen(Vector2(x0, y0)), to_screen(Vector2(x1, y0)),
		to_screen(Vector2(x1, y1)), to_screen(Vector2(x0, y1)),
	])


static func dir8(v: Vector2) -> int:
	return posmod(int(round(v.angle() / (PI / 4.0))), 8)
