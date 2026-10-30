class_name Pickup
extends Area2D
## Cartridges dropped by a dead bandit, for the weapon he carried.

const AMOUNT := {"colt": 6, "coach": 4, "rifle": 7}

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
	if b is Player and b.alive:
		b.weapons[kind].reserve += AMOUNT[kind]
		game.sfx("pickup", position, -4.0)
		queue_free()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var glint := 0.5 + 0.5 * sin(t * 4.0)
	var brass := Color(0.82, 0.66, 0.3).lerp(Color(1, 0.95, 0.7), glint * 0.5)
	var shell := Color(0.7, 0.16, 0.12)
	for i in 3:
		var p := Vector2(-3 + i * 3, -2 + (i % 2))
		if kind == "coach":
			draw_rect(Rect2(p + Vector2(0, -3), Vector2(2, 3)), shell)
			draw_rect(Rect2(p, Vector2(2, 1)), brass)
		else:
			draw_rect(Rect2(p + Vector2(0, -3), Vector2(1, 4)), brass)
	draw_rect(Rect2(Vector2(-4, 1), Vector2(9, 1)), Color(0, 0, 0, 0.3))
