class_name Puff
extends Node2D
## A burst of particles (gun smoke, dust, splinters, blood) anchored at a ground point
## so it y-sorts with the world. Frees itself when every particle is gone. Round
## particles are drawn as squares of one shared disc texture, so a whole cloud goes
## to the screen in a handful of draw calls rather than a circle at a time.

enum K { DOT, SOFT, MARK, CASE }

const FIELDS := 10
# Each particle: [pos, vel, life, max_life, size, color, grow, gravity, drift, kind]
var parts: Array = []
static var disc: Texture2D   # a white disc, soft at the very edge
static var view := Rect2(-1e6, -1e6, 2e6, 2e6)   # the world on screen, grown by a burst's spread (set by the game)
var keep: Brass   # where its cases go once they've come to rest (K.CASE)


## The shared disc (made once).
static func disc_tex() -> Texture2D:
	if disc == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * n * 0.5, 0.0, 1.0)))
		disc = ImageTexture.create_from_image(img)
	return disc


func add(p: Vector2, v: Vector2, life: float, size: float, color: Color, grow := 0.0, gravity := 0.0,
		drift := Vector2.ZERO, kind := K.DOT) -> void:
	parts.append([p, v, life, life, size, color, grow, gravity, drift, kind])


## A spent case or shell thrown out of a gun: it falls to `floor` (px below the
## burst's ground point, so they don't all come down on one line) and is handed to
## `keep` to lie there.
func case(p: Vector2, v: Vector2, life: float, color: Color, gravity: float, floor_y: float) -> void:
	parts.append([p, v, life, life, 1.0, color, 0.0, gravity, Vector2.ZERO, K.CASE, floor_y])


## Billowing black-powder smoke: big, soft, slow, carried off by the wind.
func smoke(p: Vector2, v: Vector2, life: float, size: float, color: Color, grow: float, drift: Vector2) -> void:
	add(p, v, life, size, color, grow, 0.0, drift, K.SOFT)


## A bullet hole or scorch that stays put for a while.
func mark(p: Vector2, life: float, size: float, color: Color) -> void:
	add(p, Vector2.ZERO, life, size, color, 0.0, 0.0, Vector2.ZERO, K.MARK)


func _process(delta: float) -> void:
	var i := parts.size() - 1
	while i >= 0:
		var q: Array = parts[i]
		q[2] -= delta
		if q[2] <= 0.0:
			if q[9] == K.CASE and keep:
				keep.add(position + Vector2(q[0].x, minf(q[0].y, q[10])), q[5])   # (on the ground, to stay)
			parts.remove_at(i)
		else:
			q[1] = q[1] * pow(0.12, delta) + Vector2(0, q[7] * delta)
			q[0] += (q[1] + q[8]) * delta
			q[4] += q[6] * delta
			var fl: float = q[10] if q.size() > FIELDS else 0.0
			if q[7] > 0.0 and q[0].y > fl:
				q[0].y = fl
				q[1] = Vector2.ZERO
		i -= 1
	if parts.is_empty():
		queue_free()
	elif view.has_point(position):   # (off screen, nobody's watching it drift)
		queue_redraw()


func _draw() -> void:
	var tex := disc_tex()
	for q in parts:
		var c: Color = q[5]
		var ratio: float = q[2] / q[3]
		var s: float = q[4]
		var p: Vector2 = q[0]
		match q[9]:
			K.SOFT:
				# fade in quickly, thin out slowly; a lit top over a shaded underside
				c.a *= clamp((1.0 - ratio) * 8.0, 0.0, 1.0) * clamp(ratio * 1.6, 0.0, 1.0)
				draw_texture_rect(tex, Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), false, Color(c.r * 0.82, c.g * 0.8, c.b * 0.8, c.a))
				var top := p + Vector2(-s * 0.2, -s * 0.25)
				draw_texture_rect(tex, Rect2(top - Vector2(s, s) * 0.75, Vector2(s, s) * 1.5), false,
					Color(c.r * 1.05, c.g * 1.04, c.b * 1.02, c.a * 0.9))
			K.CASE:   # no fading: it's going to lie there
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), c)
			K.MARK:
				c.a *= clamp(ratio * 4.0, 0.0, 1.0)
				draw_rect(Rect2(p - Vector2(s, s * 0.6) * 0.5, Vector2(s, s * 0.6)), c)
			_:
				c.a *= clamp(ratio * 1.5, 0.0, 1.0)
				if s <= 1.2:
					draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), c)
				else:
					draw_texture_rect(tex, Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), false, c)
