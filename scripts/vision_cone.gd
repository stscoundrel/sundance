class_name VisionCone
extends Node2D
## Draws a bandit's view on the ground, clipped by walls. The inner band sees a
## crouching hero; the outer band only sees him standing.

const RAYS := 18

var enemy: Enemy
var far := PackedVector2Array()
var near := PackedVector2Array()
var _frame := 0


func refresh() -> void:
	position = enemy.global_position
	_frame += 1
	if _frame % 2 == 0 and far.size() > 0:
		return
	far.clear()
	near.clear()
	var half := enemy.half_fov()
	var r := enemy.view_range()
	var base := enemy.facing.angle()
	var mask := Iso.LAYER_WALL
	for i in RAYS + 1:
		var a := base - half + 2.0 * half * i / RAYS
		var d := Vector2.from_angle(a)
		var hit: Dictionary = enemy.game.ray(position, position + d * r, mask)
		var len := r
		if not hit.is_empty():
			len = max(2.0, position.distance_to(hit["position"]))
		far.append(d * len)
		near.append(d * min(len, Enemy.NEAR))
	queue_redraw()


func _draw() -> void:
	if not enemy.alive or far.size() < 2:
		return
	var base: Color
	match enemy.st:
		Enemy.St.COMBAT:
			base = Color(0.9, 0.15, 0.08)
		Enemy.St.INVESTIGATE, Enemy.St.SEARCH:
			base = Color(1.0, 0.62, 0.15)
		_:
			base = Color(1.0, 0.96, 0.78)
	var combat := enemy.st == Enemy.St.COMBAT
	var cf := Color(base, 0.04 if combat else 0.10)
	var cn := Color(base, 0.07 if combat else 0.18)
	for i in far.size() - 1:
		draw_primitive(PackedVector2Array([Vector2.ZERO, far[i], far[i + 1]]), PackedColorArray([cf, cf, cf]), PackedVector2Array())
		draw_primitive(PackedVector2Array([Vector2.ZERO, near[i], near[i + 1]]), PackedColorArray([cn, cn, cn]), PackedVector2Array())
	var edge := Color(base, 0.15 if combat else 0.35)
	var line := PackedVector2Array([Vector2.ZERO])
	line.append_array(far)
	line.append(Vector2.ZERO)
	draw_polyline(line, edge, 1.0)
