class_name Snowfall
extends Node2D
## Snow coming down out of a grey sky (a map's "weather": "snow", Silencio's). The
## flakes are in the world, so they pan with the town rather than the screen, and
## wrap round the view as the camera goes: three depths of them, the far ones fine
## and slow and faint, the nearest bigger, quicker and whiter, all of them drifting
## on the wind and swaying as they fall.
##
## Most of the time it falls steady; every minute or so a squall comes down off the
## mountain (the snowstorm of The Hateful Eight, the wind getting up): it thickens
## and drives sideways, the white closes in from the edges of the screen, the wind
## howls. It steers the game, so it runs on game time (`game.clock`) and its own
## dice: how far everyone sees (`game.sight`: the steady snow trims it, a squall cuts
## it to half and a bit), and how fast footprints fill (Footprints).

static var rng := RandomNumberGenerator.new()   # (when the squalls come, and how long they blow)

const COUNT := 900          # flakes in the steady snow
const STORM_COUNT := 2600   # and in a squall
const MARGIN := 24.0        # px past the view's edge, so a flake doesn't pop in at it
const WIND := Vector2(9.0, 70.0)    # px/s east across the screen: steady, squall
const FALL := Vector2(12.0, 32.0)   # px/s, far to near
const SIGHT := Vector2(0.85, 0.55)  # of a man's sight: steady snow, squall
const FIRST := Vector2(40.0, 70.0)  # s before the first squall
const GAP := Vector2(45.0, 80.0)    # s of steady snow between squalls
const BLOW := Vector2(20.0, 35.0)   # s a squall blows at its worst
const RISE := 8.0           # s for one to build (and as long to die away)

var game: Node
var flakes: Array[Vector4] = []   # x, y, depth (0 far .. 1 near), sway phase
var squalls: Array[Vector2] = []  # [start, end of the worst] in game seconds
var storm := 0.0            # 0 steady snow .. 1 the worst of a squall
var t := 0.0
var _was_up := false


func setup(g: Node) -> void:
	game = g
	var at := rng.randf_range(FIRST.x, FIRST.y)
	while at < 3600.0:
		var blow := rng.randf_range(BLOW.x, BLOW.y)
		squalls.append(Vector2(at, at + RISE + blow))
		at += RISE + blow + RISE + rng.randf_range(GAP.x, GAP.y)
	var look := RandomNumberGenerator.new()   # (where the flakes are: only looks)
	look.seed = 97
	for i in STORM_COUNT:
		flakes.append(Vector4(look.randf_range(0.0, 4000.0), look.randf_range(0.0, 4000.0), look.randf(), look.randf() * TAU))


func _ready() -> void:
	z_as_relative = false
	z_index = 60   # (over the town and everyone in it)


## How hard it's blowing at game time `s`: 0 the steady snow, 1 the worst of a squall.
func storm_at(s: float) -> float:
	for q in squalls:
		if s < q.x:
			break
		if s < q.x + RISE:
			return smoothstep(0.0, 1.0, (s - q.x) / RISE)
		if s < q.y:
			return 1.0
		if s < q.y + RISE:
			return 1.0 - smoothstep(0.0, 1.0, (s - q.y) / RISE)
	return 0.0


## Which squall is blowing at game time `s` (building, at its worst or dying away),
## by its place in the list; -1 between them.
func squall_at(s: float) -> int:
	for i in squalls.size():
		if s >= squalls[i].x and s < squalls[i].y + RISE:
			return i
	return -1


## When squall `i` has blown itself out.
func squall_over(i: int) -> float:
	return squalls[i].y + RISE


## The world the camera shows, and a margin round it.
func _view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom if cam else Vector2.ONE
	var size := get_viewport_rect().size / zoom
	var c := cam.get_screen_center_position() if cam else size * 0.5
	return Rect2(c - size * 0.5 - Vector2.ONE * MARGIN, size + Vector2.ONE * MARGIN * 2.0)


func _physics_process(_delta: float) -> void:
	storm = storm_at(game.clock)
	game.sight = lerpf(SIGHT.x, SIGHT.y, storm)
	if storm > 0.5 and not _was_up and game.state == "play":
		game.hud.toast("A squall comes down off the mountain")
	_was_up = storm > 0.5


func _process(delta: float) -> void:
	t += delta
	var v := _view()
	var wind := lerpf(WIND.x, WIND.y, storm)
	for i in flakes.size():
		var f := flakes[i]
		f.x += (wind * (0.5 + f.z) + sin(t * 1.3 + f.w) * 6.0) * delta
		f.y += lerpf(FALL.x, FALL.y, f.z) * (1.0 + storm * 0.8) * delta
		f.x = v.position.x + fposmod(f.x - v.position.x, v.size.x)
		f.y = v.position.y + fposmod(f.y - v.position.y, v.size.y)
		flakes[i] = f
	queue_redraw()


## White on white is nothing: the nearer flakes carry a grey underside, so they show
## against the snow on the ground as well as against a wall or a man. In a squall
## they're driven near flat, streaks more than flakes.
func _draw() -> void:
	var n := int(lerpf(COUNT, STORM_COUNT, storm))
	var streak := 1.0 + storm * 3.0
	for i in n:
		var f := flakes[i]
		var at := Vector2(f.x, f.y).floor()
		var s := 2.0 if f.z > 0.6 else 1.0
		var w := (s * streak) if f.z > 0.35 else s
		if f.z > 0.35:
			draw_rect(Rect2(at + Vector2(0, s), Vector2(w, 1)), Color(0.42, 0.46, 0.56, 0.45 * f.z))
		draw_rect(Rect2(at, Vector2(w, s)), Color(0.94, 0.96, 1.0, lerpf(0.4, 1.0, f.z)))
