class_name Breath
extends Node2D
## Breath in the cold (Silencio's): a little white puff at a man's mouth every few
## seconds, drifting off on the wind and gone. Quicker and bigger when he's been
## running. It's his own, drawn with him (so a wall that hides him hides it too),
## and only a look: it gives nobody away. On the clock and his own phase, no dice.

const EVERY := 3.2       # s between breaths, standing
const LAST := 1.3        # s a puff hangs in the air

var actor: Actor
var phase := 0.0
var _hard := 0.0         # how hard he's breathing (from running), 0..1
var _shown := false      # a puff drawn last time: one more redraw clears it


func setup(a: Actor) -> void:
	actor = a
	phase = fposmod(float(a.get_instance_id() % 1000) * 0.137, 1.0) * EVERY   # (not all in step)


func _process(delta: float) -> void:
	_hard = clampf(_hard + (delta * 0.5 if actor.velocity.length() > 40.0 else -delta * 0.12), 0.0, 1.0)
	var up := _puffing()
	if up or _shown:   # (between breaths there's nothing to draw: no redrawing nothing)
		queue_redraw()
	_shown = up


## Is there a puff in the air now (and anyone to see it)?
func _puffing() -> bool:
	if not actor.alive or not actor.visible or (actor is Enemy and actor.downed) \
			or not actor.game.view_rect(40.0).has_point(actor.global_position):
		return false
	return fposmod(float(actor.game.clock) + phase, lerpf(EVERY, EVERY * 0.45, _hard)) <= LAST


func _draw() -> void:
	if not _puffing():
		return
	var game := actor.game
	var every := lerpf(EVERY, EVERY * 0.45, _hard)
	var since := fposmod(float(game.clock) + phase, every)
	if since > LAST:
		return
	var f := since / LAST
	var wind: float = 6.0 + 26.0 * (game.snowfall.storm if game.snowfall else 0.0)
	var mouth := Vector2(actor.facing.x * 4.0, (-20.0 if actor.crouched else -28.0) + actor.facing.y * 2.0)
	var at := mouth + actor.facing * f * 5.0 + Vector2(f * wind * LAST, -f * 3.0)
	var r := (1.2 + f * 3.0) * lerpf(1.0, 1.4, _hard)
	draw_circle(at, r, Color(0.95, 0.96, 1.0, 0.45 * (1.0 - f)))
	draw_circle(at + Vector2(r * 0.6, -r * 0.3), r * 0.7, Color(0.95, 0.96, 1.0, 0.3 * (1.0 - f)))
