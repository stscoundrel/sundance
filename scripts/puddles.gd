class_name Puddles
extends Node2D
## Rainwater standing in the mud at the stranger's funeral (with the map's "rain": see
## Snowfall). Puddles all over the open ground: in the road's ruts, between the
## graves, by the dinners, each a few lobes of dark water with the grey sky caught
## pale in it and a wet rim. The rain rings them: a ring spreading and fading here
## and there in the steady rain, the whole of every puddle stippled with them in a
## downpour, and the puddles spread a little while it lasts.
##
## As the sky clears (Snowfall.clear) the sky in them warms and a glint of sun
## catches each; and once the sun's coming out the wet ground steams, wisps rising
## off the puddles in view, most at first, dying away over a minute.
##
## Only looks: nobody slips or splashes, and they hide nobody. Where they lie is
## dealt once, on dice of their own (never the game's), and the rings run on the
## frame clock (nothing turns on them).

const COUNT := 460           # puddles tried for over the map (those landing on something solid aren't)
const R := Vector2(7.0, 19.0)    # px across the long way, a lobe
const RINGS := 4             # rings a puddle can have going at once
const RING_T := 0.7          # s a ring takes to spread and fade
const RING_ODDS := Vector2(0.12, 0.85)   # of each ring slot, how often it rings: steady, downpour
const SPREAD := 0.14         # how much bigger a puddle gets at the worst of a downpour
const DRY := ["stone_circle", "open_grave_empty"]   # walkable, but paved or dug: no water stands there
const WATER := Color(0.15, 0.16, 0.18, 0.78)
const RIM := Color(0.24, 0.21, 0.18, 0.55)
const SKY := Color(0.62, 0.65, 0.70, 0.32)
const RING := Color(0.78, 0.81, 0.86, 0.55)
const SUNLIT := Color(0.98, 0.9, 0.7, 0.42)   # the sky in them once the sun's out
const GLINT := Color(1.0, 0.96, 0.84, 0.8)    # and the sun itself, caught in each
const STEAM_FROM := 0.8      # clear this far, the ground starts to steam
const STEAM_T := 60.0        # s it steams, dying away
const STEAM_RATE := 1.5      # wisps a second at first, across the screen

var game: Node
var puddles: Array = []      # {at, lobes: [[offset, r]], phase}
var t := 0.0
var _steam_t := -1.0         # s it's been steaming; -1 not yet
var _wisp := 0.0             # wisps owed
var _look := RandomNumberGenerator.new()   # (where the wisps rise: only looks)
var _dry: Array[Rect2] = []  # where nothing stands (DRY's footprints, on the tile grid)


func setup(g: Node) -> void:
	game = g
	var dice := RandomNumberGenerator.new()   # (where they lie: only looks)
	dice.seed = 211
	_look.seed = 227
	var n: int = game.size
	for o in game.level["objects"]:
		if o["type"] in DRY:
			var fp: Array = game.meta["objects"][o["type"]]["footprint"]
			_dry.append(Rect2(Vector2(o["x"], o["y"]), Vector2(fp[0], fp[1])).grow(0.6))
	for i in COUNT:
		var cell := Vector2(dice.randf_range(2.0, n - 2.0), dice.randf_range(2.0, n - 2.0))
		var at: Vector2 = Iso.to_screen(cell)
		var r := dice.randf_range(R.x, R.y)
		var lobes: Array = [[Vector2.ZERO, r]]
		var lean := Vector2.from_angle(dice.randf() * TAU) * Vector2(1.0, 0.5)   # (strung out one way, like water in a rut)
		for k in dice.randi_range(2, 4):
			var off := lean * r * dice.randf_range(-1.1, 1.1) + Vector2(dice.randf_range(-0.3, 0.3), dice.randf_range(-0.15, 0.15)) * r
			lobes.append([off, r * dice.randf_range(0.35, 0.75)])
		if not _on_open_ground(at, lobes):
			continue
		puddles.append({"at": at, "lobes": lobes, "phase": dice.randf() * 100.0})


## Every lobe on open ground, all round its edge at its widest (a downpour's): not
## lapping up a wall or a grave, nor on the paving round his own grave.
func _on_open_ground(at: Vector2, lobes: Array) -> bool:
	for l in lobes:
		var c: Vector2 = at + l[0] * (1.0 + SPREAD)
		var r: float = l[1] * (1.0 + SPREAD) * 1.12   # (the rim)
		for k in 7:
			var p: Vector2 = c if k == 6 else c + Vector2.from_angle(k * TAU / 6.0) * r * Vector2(1.0, 0.5)
			if not game.is_free(p) or _dry.any(func(d): return d.has_point(Iso.to_grid(p))):
				return false
	return true


func _ready() -> void:
	z_index = -16   # (on the ground, under the blood and the brass)


func _process(delta: float) -> void:
	if game.state != "play" or get_tree().paused:
		return   # (rings stood still under a menu: nothing to redraw)
	t += delta
	_steam(delta)
	queue_redraw()


## The wet ground steaming in the sun: a wisp off a puddle in view now and then,
## fewer as it dries.
func _steam(delta: float) -> void:
	if not game.snowfall or game.snowfall.clear < STEAM_FROM or _steam_t >= STEAM_T:
		return
	_steam_t = maxf(_steam_t, 0.0) + delta
	_wisp += STEAM_RATE * (1.0 - _steam_t / STEAM_T) * delta
	if _wisp < 1.0:
		return
	_wisp -= 1.0
	var view: Rect2 = game.view_rect(0.0)
	var near: Array = puddles.filter(func(p): return view.has_point(p["at"]))
	if near.is_empty():
		return
	var p: Dictionary = near[_look.randi() % near.size()]
	var l: Array = p["lobes"][_look.randi() % p["lobes"].size()]
	var puff := Puff.new()
	puff.position = p["at"] + l[0]
	for k in 3:
		puff.smoke(Vector2(_look.randf_range(-0.6, 0.6) * l[1], -2.0 - k * 3.0), Vector2(_look.randf_range(-2.0, 2.0), -_look.randf_range(5.0, 9.0)),
			_look.randf_range(3.0, 5.0), _look.randf_range(3.0, 5.0), Color(0.95, 0.94, 0.9, 0.14), 1.6, game.WIND * 0.4)
	game.world.add_child(puff)


func _storm() -> float:
	return game.snowfall.storm if game.snowfall else 0.0


func _draw() -> void:
	var view: Rect2 = game.view_rect(40.0)
	var storm := _storm()
	var grow := 1.0 + SPREAD * storm
	var odds: float = lerpf(RING_ODDS.x, RING_ODDS.y, storm) * (game.snowfall.wet if game.snowfall else 1.0)   # (no rain, no rings)
	var tex := Puff.disc_tex()
	var sun: float = game.snowfall.clear if game.snowfall else 0.0
	var sky := SKY.lerp(SUNLIT, sun)
	for p in puddles:
		var at: Vector2 = p["at"]
		if not view.has_point(at):
			continue
		for pass_i in 3:   # the wet rim, the water, the sky in it
			for l in p["lobes"]:
				var r: float = l[1] * grow * (1.12 if pass_i == 0 else 1.0)
				var c: Vector2 = at + l[0] * grow
				if pass_i == 2:
					r *= 0.55
					c += Vector2(-r * 0.25, -r * 0.12)
				var col := RIM if pass_i == 0 else WATER if pass_i == 1 else sky
				draw_texture_rect(tex, Rect2(c - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), false, col)
		if sun > 0.5:   # the sun caught in it, off the brightest of the sky
			var g: Array = p["lobes"][0]
			var gr: float = clampf(g[1] * 0.12, 1.2, 2.6)
			var gc: Vector2 = at + g[0] * grow + Vector2(-g[1] * 0.35, -g[1] * 0.18)
			draw_texture_rect(tex, Rect2(gc - Vector2(gr, gr * 0.5), Vector2(gr * 2.0, gr)), false, Color(GLINT.r, GLINT.g, GLINT.b, GLINT.a * (sun - 0.5) * 2.0))
		# the rain on it: each ring slot rings in some of its turns, more in a downpour
		for k in RINGS:
			var clock: float = t / RING_T + p["phase"] + k * 0.37
			var turn := floori(clock)
			var f := clock - turn
			if _hash(p["phase"], k, turn) > odds:
				continue
			var l: Array = p["lobes"][k % p["lobes"].size()]
			var lr: float = l[1] * grow * 0.7
			var c: Vector2 = at + l[0] * grow + Vector2(_hash(turn, k, 1.0) - 0.5, (_hash(turn, k, 2.0) - 0.5) * 0.5) * lr
			var rr := 1.0 + f * minf(6.0, lr * 0.4)
			draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 12, Color(RING.r, RING.g, RING.b, RING.a * (1.0 - f)), 1.0)
			draw_set_transform(Vector2.ZERO)


## A number in 0..1 that's always the same for the same three: which rings ring.
static func _hash(a: float, b: float, c: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453, 1.0)
