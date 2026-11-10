class_name Hearth
extends Node2D
## A house with men in it out of the squall (Silencio's: see Enemy._shelter): a fire
## lit, smoke going up out of the cabin's stone chimney and lamplight in its windows
## (not behind shut shutters). Both come up as the first man goes in and die away a
## while after the last comes out. It hangs off the building's sprite, so it fades
## with the building and sorts with it. Only looks: on the clock, no dice.

const UP := 2.5          # s for the fire to take, and as long for it to die down
const SMOKE := 14        # puffs in the air at once
const RISE_PX := 70.0    # how far a puff rises before it's gone
const GLOW := Color(1.0, 0.55, 0.15)

var game: Node
var house: Dictionary    # game.houses' entry: its doors, its men inside, its chimney, its windows
var warm := 0.0          # 0 cold .. 1 the fire going
var _at := Vector2.ZERO  # where it hangs in the world


func setup(g: Node, h: Dictionary, building: Sprite2D) -> void:
	game = g
	house = h
	scale = Vector2.ONE / building.scale   # (drawing in the world's pixels)
	_at = Iso.to_screen(h["corner"] + h["footprint"])   # (its front corner: sorted over the building)
	position = (_at - building.position) / building.scale


func _process(delta: float) -> void:
	var lit: bool = house["in"] > 0
	warm = clampf(warm + delta / UP * (1.0 if lit else -1.0), 0.0, 1.0)
	visible = warm > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var t: float = game.clock
	var corner: Vector2 = house["corner"]
	draw_set_transform(-_at)   # (drawn in the world's coordinates)
	for w in house["windows"]:   # lamplight in the panes
		var sh: Shutter = w["shutter"]
		if sh and sh.shut:
			continue
		var flick := 0.85 + 0.15 * sin(t * 7.0 + float(w["span"][0][0]) * 3.0)
		var a := Iso.to_screen(corner + Vector2(w["span"][0][0], w["span"][0][1]))
		var b := Iso.to_screen(corner + Vector2(w["span"][1][0], w["span"][1][1]))
		var lo := Vector2(0, -float(w["z"][0]) * Actor.PZ)
		var hi := Vector2(0, -float(w["z"][1]) * Actor.PZ)
		var pane := PackedVector2Array([a + lo, b + lo, b + hi, a + hi])
		draw_colored_polygon(pane, Color(GLOW, 0.8 * warm * flick))
		var mid := (a + b) * 0.5 + (lo + hi) * 0.5   # (brighter at the heart of it, by the lamp)
		draw_circle(mid, 2.5, Color(1.0, 0.85, 0.5, 0.8 * warm * flick))
	if house["chimney"] == Vector3.INF:
		return
	var c: Vector3 = house["chimney"]
	var top := Iso.to_screen(corner + Vector2(c.x, c.y)) - Vector2(0, c.z * Actor.PZ)
	var wind: float = 8.0 + 30.0 * (game.snowfall.storm if game.snowfall else 0.0)
	for i in SMOKE:   # puffs rising off the stack, drifting east on the wind, swelling as they go
		var f := fposmod(t * 0.18 + i / float(SMOKE), 1.0)
		var at := top + Vector2(f * wind * 1.5 + sin(t * 0.9 + i * 1.7) * 3.0, -f * RISE_PX)
		var r := 3.0 + f * 9.0
		draw_circle(at, r, Color(0.5, 0.5, 0.53, 0.6 * (1.0 - f) * warm))
		draw_circle(at + Vector2(-r * 0.3, -r * 0.3), r * 0.6, Color(0.66, 0.66, 0.69, 0.5 * (1.0 - f) * warm))
