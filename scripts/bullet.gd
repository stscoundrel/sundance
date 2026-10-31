class_name Bullet
extends Node2D
## A fast projectile traced along the ground plane and drawn at gun height.
## Low cover stops it, unless the shooter is right behind that cover or the target
## just past it is standing (shooting over a crate).

var game: Node
var vel := Vector2.ZERO
var range_left := 0.0
var damage := 1
var shooter: Actor
var h := 20.0
var pellet := false
var travelled := 0.0
var exclude: Array[RID] = []
var scared: Array[Enemy] = []


func setup(g: Node, origin: Vector2, v: Vector2, rng: float, dmg: int, sh: Actor, height: float, is_pellet: bool) -> void:
	game = g
	position = origin
	vel = v
	range_left = rng
	damage = dmg
	shooter = sh
	h = height
	pellet = is_pellet
	exclude = [sh.get_rid(), sh.hurtbox.get_rid()]


func _physics_process(delta: float) -> void:
	var step := vel * delta
	var to := position + step
	var mask := Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_HURT
	for i in 5:
		var hit: Dictionary = game.ray(position, to, mask, exclude, true)
		if hit.is_empty():
			break
		var col: CollisionObject2D = hit["collider"]
		var hp: Vector2 = hit["position"]
		if col is Area2D:
			var a: Actor = col.get_meta("actor")
			# bandits don't gun each other down
			if a.alive and not (a is Enemy and shooter is Enemy):
				a.take_hit(damage, vel.normalized(), shooter)
				queue_free()
				return
			exclude.append(col.get_rid())
			continue
		if col.collision_layer & Iso.LAYER_COVER:
			if hp.distance_to(shooter.global_position) < 26.0 or _standing_target_behind(hp):
				exclude.append(col.get_rid())
				continue
		game.impact(hp, h, vel, true)
		_scare_impact(hp)
		queue_free()
		return
	if shooter.is_player:
		_scare(position, to)
	travelled += step.length()
	position = to
	if travelled >= range_left:
		# spent: it drops into the dirt
		game.impact(position, h, vel, false)
		_scare_impact(position)
		queue_free()
		return
	queue_redraw()


## Bandits the round cracks past get a fright, unless there's a wall between.
func _scare(a: Vector2, b: Vector2) -> void:
	for e in game.enemies:
		if not e.alive or scared.has(e):
			continue
		var p := Geometry2D.get_closest_point_to_segment(e.global_position, a, b)
		if p.distance_to(e.global_position) < 55.0 and game.line_of_sight(e.global_position, p, false):
			scared.append(e)
			e.near_miss(shooter.global_position)


func _scare_impact(p: Vector2) -> void:
	if not shooter.is_player:
		return
	for e in game.enemies:
		# the strike is on the near face of whatever it hit: seen from the shooter's side
		var face := p + (shooter.global_position - p).normalized() * 4.0
		if e.alive and not scared.has(e) and e.global_position.distance_to(p) < 70.0 \
				and game.line_of_sight(e.global_position, face, false):
			e.near_miss(shooter.global_position)


func _standing_target_behind(p: Vector2) -> bool:
	var hit: Dictionary = game.ray(p, p + vel.normalized() * 30.0, Iso.LAYER_HURT, exclude, true)
	if hit.is_empty():
		return false
	var a: Actor = hit["collider"].get_meta("actor")
	return a.alive and not a.crouched


func _draw() -> void:
	var tip := Vector2(0, -h)
	var tail: Vector2 = tip - vel.normalized() * min(travelled + 2.0, 9.0 if not pellet else 4.0)
	draw_line(tail, tip, Color(1.0, 0.93, 0.66, 0.9), 1.0)
	draw_rect(Rect2(tip - Vector2(0.5, 0.5), Vector2(1, 1)), Color(1, 1, 0.9))
