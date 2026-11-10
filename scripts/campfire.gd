class_name Campfire
extends Node2D
## A fire by a guard post in the snow (Silencio's: the map's "campfire" objects, two
## at each gang's end). It burns down on its own, about three and a half minutes from
## a full stack to cold ashes, flames shrinking as it goes; the woodcutter of that end
## brings an armful of split wood now and then and lays it on (Civilian._woodcut). The
## men of the posts nearby come over to warm their hands at it (Enemy, "warm"), and a
## post whose fire is out is a cold one, its men the quicker to go in out of a squall.
## Flames, a warm glow on the snow, sparks, smoke and a crackle: all on game time, the
## flicker only a look.

const BURN_T := 210.0     # s from a full stack to cold
const FEED := 0.5         # what an armful adds
const LOW := 0.08         # under this it's embers: nobody warms at it, and it soon goes out

var game: Node
var end := ""             # whose end of town: "outlaws" or "hunters"
var fuel := 1.0
var hiss: AudioStreamPlayer2D


func setup(g: Node, at: Vector2, side: String, start: float) -> void:
	game = g
	position = at
	end = side
	fuel = start
	# (sorted with everyone by its place on the ground, and after the stones and ash of
	# the prop it sits in, which it was added after)
	if game.meta["sfx"].has("crackle"):
		hiss = AudioStreamPlayer2D.new()
		hiss.stream = load(game.meta["sfx"]["crackle"])
		hiss.volume_db = -14.0
		hiss.max_distance = 420.0
		add_child(hiss)


func lit() -> bool:
	return fuel > LOW


func lay_on() -> void:
	fuel = minf(1.0, fuel + FEED)
	game.stats["fires fed"] = game.stats.get("fires fed", 0) + 1


func _physics_process(delta: float) -> void:
	if game.state != "play":
		return
	fuel = maxf(0.0, fuel - delta / BURN_T)
	if hiss:
		if fuel > 0.0 and not hiss.playing:
			hiss.play()
		elif fuel <= 0.0 and hiss.playing:
			hiss.stop()
		hiss.volume_db = -22.0 + 10.0 * minf(1.0, fuel * 2.0)
	queue_redraw()


func _draw() -> void:
	if fuel <= 0.0:
		return
	var t: float = game.clock
	var k := minf(1.0, fuel * 1.6)   # (the flames' size: a full fire, down to embers)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))   # the glow on the snow round it
	draw_circle(Vector2.ZERO, 34.0 * k + 6.0, Color(1.0, 0.55, 0.2, 0.10 * k))
	draw_circle(Vector2.ZERO, 18.0 * k + 4.0, Color(1.0, 0.6, 0.25, 0.16 * k))
	draw_set_transform(Vector2.ZERO)
	if fuel < LOW:   # embers: a red glow in the ash
		draw_circle(Vector2(0, -2), 3.0, Color(0.9, 0.25, 0.08, 0.6 + 0.3 * sin(t * 3.0)))
		return
	for i in 5:   # tongues of flame, licking up and flickering
		var ph := t * (7.0 + i) + i * 1.9
		var h := (7.0 + 5.0 * sin(ph) * 0.4 + 3.0 * sin(ph * 2.3)) * k + 2.0
		var x := (i - 2) * 1.6 * k + sin(ph * 0.7) * 0.8
		var base := Vector2(x, -3.0)
		var tip := base + Vector2(sin(ph * 1.3) * 1.5, -h)
		var col := Color(1.0, 0.45 + 0.1 * i, 0.12, 0.85)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-2.2 * k - 0.6, 0), base + Vector2(2.2 * k + 0.6, 0), tip]), col)
	draw_circle(Vector2(0, -4.0), 2.4 * k + 0.6, Color(1.0, 0.92, 0.6, 0.9))   # the white heart of it
	for i in 4:   # sparks going up
		var f := fposmod(t * 0.9 + i * 0.27, 1.0)
		var at := Vector2(sin(t * 2.0 + i * 2.1) * 4.0 + f * 6.0, -6.0 - f * 26.0 * k)
		draw_rect(Rect2(at, Vector2(1, 1)), Color(1.0, 0.75, 0.3, 1.0 - f))
	for i in 5:   # and a little smoke, off on the wind
		var f := fposmod(t * 0.25 + i * 0.2, 1.0)
		var wind: float = 6.0 + 24.0 * (game.snowfall.storm if game.snowfall else 0.0)
		var at := Vector2(f * wind + sin(t + i) * 2.0, -12.0 - f * 34.0)
		draw_circle(at, 2.0 + f * 5.0, Color(0.55, 0.55, 0.57, 0.3 * (1.0 - f) * k))
