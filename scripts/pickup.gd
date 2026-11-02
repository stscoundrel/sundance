class_name Pickup
extends Area2D
## Cartridges dropped by a dead bandit, for the weapon he carried (powder and ball,
## for the cap-and-ball and muzzle-loaders); or a bandage he never got to use, or
## the stick of dynamite he never got to throw.

const AMOUNT := {"colt": 6, "coach": 4, "rifle": 7, "spencer": 5, "powder": 4, "bandage": 1, "dynamite": 1}
const CARRY := {"bandage": 1, "dynamite": 1}   # one of each on him at a time: the rest stay where they lie

var game: Node
var kind := "colt"
var t := 0.0


func setup(g: Node, pos: Vector2, k: String) -> void:
	game = g
	kind = k
	position = pos
	collision_layer = Iso.LAYER_PICKUP
	collision_mask = Iso.LAYER_ACTOR
	monitoring = true
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 9.0
	cs.shape = c
	add_child(cs)
	body_entered.connect(_on_body)


func _on_body(b: Node) -> void:
	if b is Player and b.alive and not b.down:
		match kind:
			"bandage":
				if b.bandages >= CARRY[kind]:
					return
				b.bandages += 1
				game.hud.toast("Bandage picked up")
			"dynamite":
				if b.sticks >= CARRY[kind]:
					return
				b.sticks += 1
				game.hud.toast("Dynamite picked up  [G]")
			_:
				b.belt[kind] = b.belt.get(kind, 0) + AMOUNT[kind]
		if kind in CARRY:
			game.stats[kind + " picked up"] = game.stats.get(kind + " picked up", 0) + 1
		game.sfx("pickup", null, 0.0)
		queue_free()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var glint := 0.5 + 0.5 * sin(t * 4.0)
	var brass := Color(0.82, 0.66, 0.3).lerp(Color(1, 0.95, 0.7), glint * 0.5)
	var shell := Color(0.7, 0.16, 0.12)
	if kind == "bandage":   # a rolled bandage, a tail of it loose
		draw_rect(Rect2(-3, -3, 6, 4), Color(0.93, 0.91, 0.85).lerp(Color.WHITE, glint * 0.3))
		draw_line(Vector2(-1, -3), Vector2(-1, 1), Color(0.72, 0.68, 0.62), 1.0)
		draw_line(Vector2(3, 0), Vector2(6, 1), Color(0.9, 0.88, 0.82), 1.0)
		draw_rect(Rect2(Vector2(-4, 1), Vector2(9, 1)), Color(0, 0, 0, 0.3))
		return
	if kind == "dynamite":   # a red stick, its fuse curled
		draw_rect(Rect2(-4, -2, 8, 3), Color(0.68, 0.14, 0.1).lerp(Color(0.9, 0.3, 0.2), glint * 0.4))
		draw_rect(Rect2(-1, -2, 1, 3), Color(0.85, 0.78, 0.6))
		draw_line(Vector2(4, -1), Vector2(6, -3), Color(0.22, 0.17, 0.12), 1.0)
		draw_rect(Rect2(Vector2(-4, 1), Vector2(9, 1)), Color(0, 0, 0, 0.3))
		return
	if kind == "powder":   # paper cartridges, twisted shut, and a powder flask
		for i in 3:
			draw_rect(Rect2(Vector2(-4 + i * 2, -3 + (i % 2)), Vector2(1, 3)), Color(0.86, 0.8, 0.64).lerp(Color.WHITE, glint * 0.3))
		draw_circle(Vector2(3, -1), 2.0, Color(0.5, 0.32, 0.16).lerp(brass, glint * 0.4))
		draw_rect(Rect2(Vector2(-4, 1), Vector2(9, 1)), Color(0, 0, 0, 0.3))
		return
	for i in 3:
		var p := Vector2(-3 + i * 3, -2 + (i % 2))
		if kind == "coach":
			draw_rect(Rect2(p + Vector2(0, -3), Vector2(2, 3)), shell)
			draw_rect(Rect2(p, Vector2(2, 1)), brass)
		else:
			draw_rect(Rect2(p + Vector2(0, -3), Vector2(1, 4)), brass)
	draw_rect(Rect2(Vector2(-4, 1), Vector2(9, 1)), Color(0, 0, 0, 0.3))
