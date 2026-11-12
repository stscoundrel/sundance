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
##
## At the stranger's funeral it is rain (the map's "rain"): long grey streaks
## slanting down fast instead of flakes, falling steady, and every so often a
## downpour that hammers down, greys out the edges of the screen and drowns the
## world in its noise. The same squalls, the same cut to everyone's sight; nothing
## else of the snow (no prints, no drifts, nobody goes in out of it: they came to
## bury him and they'll stand there wet). Each downpour is marked coming in: a
## flash of lightning, the screen whitening twice, and the thunder a moment after.

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
# The rain's own (see above): far more drops falling far faster, a little slant on
# the steady rain, a hard one in a downpour, and as far to see through as the snow.
const RAIN_COUNT := 700
const RAIN_STORM_COUNT := 2200
const RAIN_WIND := Vector2(40.0, 150.0)
const RAIN_FALL := Vector2(420.0, 760.0)
const RAIN_SIGHT := Vector2(0.88, 0.6)
const THUNDER_LAG := 0.7    # s from the flash to the thunder (it's a way off, up the valley)

var game: Node
var rain := false           # the funeral's rain, not the snow (setup's `wet`)
var flakes: Array[Vector4] = []   # where each started: x, y, depth (0 far .. 1 near), sway phase
var squalls: Array[Vector2] = []  # [start, end of the worst] in game seconds
var storm := 0.0            # 0 steady snow .. 1 the worst of a squall
var t := 0.0
var drift := 0.0            # px the wind's carried a flake of depth 0.5, all told
var fall := 0.0             # s of falling (a squall's counting for more)
var _was_up := false
var _heard := -1            # the last downpour the thunder marked
var _thunder_at := -1.0     # game time the thunder's due, after the flash
var flashed := -1.0         # game time of the last flash; -1 none yet
var flash := 0.0            # how white the lightning has the screen (post's "flash")
var _mm := MultiMesh.new()
var _mats: Array[ShaderMaterial] = []


func setup(g: Node, wet := false) -> void:
	game = g
	rain = wet
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
	for under in ([false] if rain else [true, false]):   # the grey undersides, then the flakes over them (a raindrop needs none)
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = _mm
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("underside", under)
		mat.set_shader_parameter("fall_px", RAIN_FALL if rain else FALL)
		mat.set_shader_parameter("rain", rain)
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
	var sight := RAIN_SIGHT if rain else SIGHT
	game.sight = lerpf(sight.x, sight.y, storm)
	if storm > 0.5 and not _was_up and game.state == "play":
		game.hud.toast("The heavens open" if rain else "A squall comes down off the mountain")
	_was_up = storm > 0.5
	if rain:
		var i := squall_at(game.clock)
		if i >= 0 and i != _heard:   # a downpour coming in: the lightning, then the thunder
			_heard = i
			flashed = game.clock
			_thunder_at = game.clock + THUNDER_LAG
		if _thunder_at >= 0.0 and game.clock >= _thunder_at:
			_thunder_at = -1.0
			if game.state == "play":
				game.sfx("thunder", null, -1.0, 0.08, rng)
		# (the flash: bright, a dip, bright again, then fading over half a second)
		var since: float = game.clock - flashed
		flash = 0.0 if flashed < 0.0 or since > 0.7 else (1.0 if since < 0.07 else 0.35 if since < 0.14 else 0.9 * (1.0 - (since - 0.14) / 0.56))


func _process(delta: float) -> void:
	t += delta
	var wind := RAIN_WIND if rain else WIND
	drift += lerpf(wind.x, wind.y, storm) * delta
	fall += (1.0 + storm * (0.4 if rain else 0.8)) * delta
	var v := _view()
	_mm.visible_instance_count = int(lerpf(RAIN_COUNT, RAIN_STORM_COUNT, storm)) if rain else int(lerpf(COUNT, STORM_COUNT, storm))
	for mat in _mats:
		mat.set_shader_parameter("view", Vector4(v.position.x, v.position.y, v.size.x, v.size.y))
		mat.set_shader_parameter("drift", drift)
		mat.set_shader_parameter("fall", fall)
		mat.set_shader_parameter("t", t)
		mat.set_shader_parameter("streak", 1.0 + storm * 3.0)
		if rain:   # (the slant of the drops: how far the wind carries one for each px it falls)
			mat.set_shader_parameter("slant", lerpf(wind.x, wind.y, storm) / lerpf(RAIN_FALL.x, RAIN_FALL.y, 0.5))


## Where flake `i` is now (the shader's sum, for the tests): drifting east on the
## wind, swaying, falling at its depth's pace, wrapped round the view.
func flake_at(i: int) -> Vector2:
	var f := flakes[i]
	var v := _view()
	var fp := RAIN_FALL if rain else FALL
	var sway := 0.0 if rain else cos(t * 1.3 + f.w) * 6.0 / 1.3
	var at := Vector2(f.x + drift * (0.5 + f.z) - sway, f.y + fall * lerpf(fp.x, fp.y, f.z))
	return Vector2(v.position.x + fposmod(at.x - v.position.x, v.size.x), v.position.y + fposmod(at.y - v.position.y, v.size.y)).floor()
