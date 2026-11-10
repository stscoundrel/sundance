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
##
## Thousands of flakes are too many to move one by one in a script every frame: each
## keeps where it started, and the shader (`shaders/snowfall.gdshader`) works out
## where it is now from how far the wind and the fall have carried everything since
## (`drift`, `fall`, summed up here as the squalls come and go).

static var rng := RandomNumberGenerator.new()   # (when the squalls come, and how long they blow)
const SHADER := preload("res://shaders/snowfall.gdshader")

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
var flakes: Array[Vector4] = []   # where each started: x, y, depth (0 far .. 1 near), sway phase
var squalls: Array[Vector2] = []  # [start, end of the worst] in game seconds
var storm := 0.0            # 0 steady snow .. 1 the worst of a squall
var t := 0.0
var drift := 0.0            # px the wind's carried a flake of depth 0.5, all told
var fall := 0.0             # s of falling (a squall's counting for more)
var _was_up := false
var _mm := MultiMesh.new()
var _mats: Array[ShaderMaterial] = []


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
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = STORM_COUNT
	for i in STORM_COUNT:
		var f := flakes[i]
		_mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		_mm.set_instance_custom_data(i, Color(f.x, f.y, f.z, f.w))
	for under in [true, false]:   # the grey undersides, then the flakes over them
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = _mm
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("underside", under)
		mat.set_shader_parameter("fall_px", FALL)
		mmi.material = mat
		_mats.append(mat)
		add_child(mmi)
		# (the shader puts every flake somewhere round the view, nowhere near where
		# the mesh says: never cull it)
		RenderingServer.canvas_item_set_custom_rect(mmi.get_canvas_item(), true, Rect2(-1e6, -1e6, 2e6, 2e6))


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
	return game.view_rect(MARGIN)


func _physics_process(_delta: float) -> void:
	storm = storm_at(game.clock)
	game.sight = lerpf(SIGHT.x, SIGHT.y, storm)
	if storm > 0.5 and not _was_up and game.state == "play":
		game.hud.toast("A squall comes down off the mountain")
	_was_up = storm > 0.5


func _process(delta: float) -> void:
	t += delta
	drift += lerpf(WIND.x, WIND.y, storm) * delta
	fall += (1.0 + storm * 0.8) * delta
	var v := _view()
	_mm.visible_instance_count = int(lerpf(COUNT, STORM_COUNT, storm))
	for mat in _mats:
		mat.set_shader_parameter("view", Vector4(v.position.x, v.position.y, v.size.x, v.size.y))
		mat.set_shader_parameter("drift", drift)
		mat.set_shader_parameter("fall", fall)
		mat.set_shader_parameter("t", t)
		mat.set_shader_parameter("streak", 1.0 + storm * 3.0)


## Where flake `i` is now (the shader's sum, for the tests): drifting east on the
## wind, swaying, falling at its depth's pace, wrapped round the view.
func flake_at(i: int) -> Vector2:
	var f := flakes[i]
	var v := _view()
	var at := Vector2(f.x + drift * (0.5 + f.z) - cos(t * 1.3 + f.w) * 6.0 / 1.3, f.y + fall * lerpf(FALL.x, FALL.y, f.z))
	return Vector2(v.position.x + fposmod(at.x - v.position.x, v.size.x), v.position.y + fposmod(at.y - v.position.y, v.size.y)).floor()
