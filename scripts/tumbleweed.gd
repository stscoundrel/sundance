class_name Tumbleweed
extends Node2D
## Drifts across town with the wind, bouncing.

var game: Node
var sprite: Sprite2D
var vel := Vector2.ZERO
var t := 0.0


func setup(g: Node, pos: Vector2) -> void:
	game = g
	position = pos
	var m: Dictionary = g.meta["tumbleweed"]
	sprite = Sprite2D.new()
	sprite.texture = g.tex(m["file"])
	sprite.hframes = int(m["frames"])
	sprite.scale = Vector2.ONE * g.tex_scale
	sprite.centered = false
	sprite.offset = -Vector2(m["anchor"][0], m["anchor"][1])
	add_child(sprite)
	_new_speed()
	t = randf() * 10.0


func _new_speed() -> void:
	vel = Iso.to_screen(Vector2(1, randf_range(-0.25, 0.25))).normalized() * randf_range(18, 34)


func _process(delta: float) -> void:
	t += delta
	position += vel * delta * (0.6 + 0.6 * abs(sin(t * 0.4)))
	sprite.position.y = -round(abs(sin(t * 5.0)) * 4.0)
	sprite.frame = int(t * 9.0) % 4
	var g := Iso.to_grid(position)
	var n: float = game.size
	if g.x > n + 3 or g.y < -3 or g.y > n + 3:
		position = Iso.to_screen(Vector2(-3, randf_range(0, n)))
		_new_speed()
