class_name Shutter
extends Sprite2D
## A window's shutters. As the stranger walks into view the townsfolk behind them
## slam them shut, one after another ahead of him; gunfire slams every one within
## earshot. Once the town has been quiet a while and he's moved on, they creak open
## again. A man creeping along crouched is noticed only up close.

const SEEN := 150.0       # px: they see the stranger coming from here
const SEEN_CROUCHED := 70.0
const REOPEN_CLEAR := 260.0   # and open up again only once he's this far off
const SLAM_FPS := 14.0
const OPEN_FPS := 3.0
const LOOK_EVERY := 0.3

var game: Node
var at: Vector2           # the street just outside the window
var shut := false
var pending := -1.0       # seconds until they act on what they've seen
var look_t := 0.0
var _f := 0.0             # animation position: 0 open .. last frame shut
var _last := 3
static var rng := RandomNumberGenerator.new()   # their own dice, so the town's stay as seeded
var glass: Sprite2D       # the pane behind them, once it's shot out (hidden as they close over it)


func setup(g: Node, building: Sprite2D, m: Dictionary, s: Dictionary, corner: Vector2, paint: Color) -> void:
	game = g
	texture = g.tex(s["file"])
	centered = false
	hframes = int(s["frames"])
	_last = hframes - 1
	offset = building.offset + Vector2(m["anchor"][0] - s["anchor"][0], m["anchor"][1] - s["anchor"][1])
	modulate = paint
	var on_y: bool = absf(float(s["at"][1]) - float(m["footprint"][1])) < 0.01
	var out := Vector2(0, 0.5) if on_y else Vector2(0.5, 0)
	at = Iso.to_screen(corner + Vector2(s["at"][0], s["at"][1]) + out)
	look_t = rng.randf() * LOOK_EVERY
	shut = rng.randf() < 0.2   # a few are shut already, against the heat
	_f = _last if shut else 0.0
	frame = int(_f)


## Gunfire within earshot: they slam, the nearest first.
func hear_shot(pos: Vector2, radius: float) -> void:
	if shut:
		if pending >= 0.0 and pos.distance_to(at) < radius * 0.8:
			pending = -1.0   # whoever was about to open up thinks better of it
		return
	var d := pos.distance_to(at)
	if d < radius * 0.8:
		_slam_in(d / 500.0 + rng.randf_range(0.0, 0.5))


func _slam_in(t: float) -> void:
	if pending < 0.0 or t < pending:
		pending = t


func tick(delta: float) -> void:
	var p: Player = game.player
	if pending >= 0.0:
		pending -= delta
		if pending < 0.0:
			if not shut:
				shut = true
			else:
				shut = false   # a reopening that came due
	elif p and p.alive:
		look_t -= delta
		if look_t <= 0.0:
			look_t = LOOK_EVERY
			var d := p.global_position.distance_to(at)
			if not shut and d < (SEEN_CROUCHED if p.crouched else SEEN) \
					and game.line_of_sight(at, p.global_position, false):
				_slam_in(rng.randf_range(0.1, 0.9))
			elif shut and d > REOPEN_CLEAR and game.quiet_for() > game.quiet_after and rng.randf() < 0.04:
				pending = rng.randf_range(0.0, 4.0)   # someone peeks out again
	_animate(delta)


func _animate(delta: float) -> void:
	var was := int(_f)
	if shut and _f < _last:
		_f = minf(_f + delta * SLAM_FPS, _last)
		if int(_f) == _last and was != _last:
			game.sfx("shutter", at, -4.0, 0.12)
	elif not shut and _f > 0.0:
		_f = maxf(_f - delta * OPEN_FPS, 0.0)
	frame = int(_f)
	if glass and glass.has_meta("broken"):
		glass.visible = frame <= 1
