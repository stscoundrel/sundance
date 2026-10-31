class_name VisionCone
extends Node2D
## Draws a bandit's view on the ground, clipped by walls. The inner band sees a
## crouching hero; the outer band only sees him standing. Purely a picture: the
## rays are cast every other frame (half the cones on each), and only when he has
## moved or turned since, and the cone is shown and on screen.

const RAYS := 18

var enemy: Enemy
var far := PackedVector2Array()
var near := PackedVector2Array()
var _frame := 0
var _cast := Vector4.INF   # x, y, facing angle and range of the last cast
var _drawn := -1           # the state whose colour it was drawn in


func _ready() -> void:
	_frame = get_index()   # stagger: odd and even cones take turns


func refresh() -> void:
	position = enemy.global_position
	_frame += 1
	if not is_visible_in_tree():
		return
	if far.size() > 0 and (_frame % 2 == 0 or not _on_screen()):
		return
	var half := enemy.half_fov()
	var r := enemy.view_range()
	var base := enemy.facing.angle()
	var now := Vector4(position.x, position.y, base, r * half)
	if far.size() > 0 and absf(now.x - _cast.x) < 1.0 and absf(now.y - _cast.y) < 1.0 \
			and absf(angle_difference(now.z, _cast.z)) < 0.02 and now.w == _cast.w:
		if enemy.st != _drawn:
			queue_redraw()
		return   # standing still, looking the same way: the same cone
	_cast = now
	far.clear()
	near.clear()
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


func _on_screen() -> bool:
	var xf := get_global_transform_with_canvas()
	var reach := enemy.view_range() * xf.get_scale().x
	return get_viewport_rect().grow(reach).has_point(xf.origin)


func _draw() -> void:
	_drawn = enemy.st
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
