class_name Smoulder
extends Node2D
## Smoke still going up from something that burned before the stranger got here (a
## gutted boxcar), or steam from a wrecked boiler: a thin column, leaning with the
## wind. Its own dice, and game time, so nothing a test replays is moved.

static var rng := RandomNumberGenerator.new()

const EVERY := 0.3      # s between puffs
const HIGH := 24.0      # px up off the ground point it rises from

var game: Node
var dark := true
var t := 0.0


func setup(g: Node, d: Dictionary) -> void:
	game = g
	position = Iso.to_screen(Vector2(d["x"], d["y"]))
	dark = d.get("dark", true)
	t = rng.randf() * EVERY


func _physics_process(delta: float) -> void:
	t -= delta
	if t > 0.0:
		return
	t = EVERY * rng.randf_range(0.7, 1.3)
	var puff := Puff.new()
	puff.position = position
	var shade := rng.randf_range(0.18, 0.3) if dark else rng.randf_range(0.86, 0.95)
	puff.smoke(Vector2(rng.randf_range(-4, 4), -HIGH), Vector2(rng.randf_range(-3, 3), -rng.randf_range(20, 28)),
		rng.randf_range(4.0, 6.0), rng.randf_range(2.5, 3.5), Color(shade, shade * 0.97, shade * 0.95, 0.35 if dark else 0.28),
		rng.randf_range(2.0, 3.0), game.WIND * 0.7 + Vector2(0, -rng.randf_range(7, 10)))   # (hot: it keeps rising)
	game.world.add_child(puff)
