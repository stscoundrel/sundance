class_name Wounds
extends Sprite2D
## What a blast leaves on a building's wall, there for good: soot up the face that
## took it and, close enough, a ragged hole knocked in the plaster or the planks,
## mud brick or splintered boards round it. Only a look: the wall stops rounds and
## eyes just as it did. A copy of the building's own picture that draws nothing
## itself but clips what's painted on it to the building, so a wound by a corner
## never hangs out in the air.

const MAX := 12        # a building's worth; the oldest go
const HOLE := 0.55     # a wound this big or more knocks a hole in the wall
const BIGGEST := 2.0
const LIFT := 6.0      # px: a hole in planks sits up off the mud-stained foot, where it reads as the wall's

static var rng := RandomNumberGenerator.new()   # (their own dice: a fight's stay as seeded)

var adobe := false
var list: Array[Dictionary] = []   # {at (the wall's foot, screen px from the building), t (along the face), size, seed}
var marks := Marks.new()


## The painting itself, over the copy (which only clips it).
class Marks extends Node2D:
	var wounds: Wounds

	func _draw() -> void:
		wounds.paint(self)


func setup(spr: Sprite2D, tex_scale: float, is_adobe: bool) -> void:
	texture = spr.texture
	centered = spr.centered
	offset = spr.offset
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	adobe = is_adobe
	marks.wounds = self
	marks.scale = Vector2.ONE / tex_scale
	add_child(marks)


## A blast struck the wall at `foot` (screen px from the building, on its base line),
## the face turned `normal` (towards the camera). A wound near an old one on the same
## face makes that one worse instead. Returns the wound.
func add(foot: Vector2, normal: Vector2, size: float) -> Dictionary:
	var t := Vector2(0.894, 0.447) if normal.x < 0.0 else Vector2(0.894, -0.447)   # (one of the two iso faces)
	for w in list:
		if w["t"] == t and w["at"].distance_to(foot) < 12.0 * maxf(w["size"], size):
			w["size"] = minf(BIGGEST, maxf(w["size"], size) + 0.35 * minf(w["size"], size))
			marks.queue_redraw()
			return w
	var w := {"at": foot, "t": t, "size": minf(BIGGEST, size), "seed": rng.randi()}
	list.append(w)
	if list.size() > MAX:
		list.remove_at(0)
	marks.queue_redraw()
	return w


func paint(c: CanvasItem) -> void:
	var disc := Puff.disc_tex()
	for w in list:
		var r := RandomNumberGenerator.new()
		r.seed = w["seed"]
		var s: float = w["size"]
		var at: Vector2 = w["at"]
		var t: Vector2 = w["t"]
		var on := func(u: float, v: float) -> Vector2: return at + t * u + Vector2(0, -v)
		# soot: blackened up the wall, widest at the foot, thinning as it climbs
		var tall := 30.0 * s
		for i in int(12 + 10 * s):
			var v := pow(r.randf(), 0.8) * tall
			var u := r.randf_range(-1.0, 1.0) * lerpf(17.0, 9.0, v / tall) * s
			var rad := (3.0 + 4.0 * v / tall) * s + 1.5
			var a := r.randf_range(0.16, 0.28) * (1.0 - v / (tall * 1.25))
			c.draw_texture_rect(disc, Rect2(on.call(u, v) - Vector2.ONE * rad, Vector2.ONE * rad * 2.0), false,
				Color(0.06, 0.05, 0.04, a))
		if s < HOLE:
			for i in 3 + int(4 * s):   # pocked by the gravel, no worse
				var p: Vector2 = on.call(r.randf_range(-9, 9) * s, r.randf_range(1, 10) * s)
				c.draw_texture_rect(disc, Rect2(p - Vector2.ONE, Vector2.ONE * 2.0), false, Color(0.1, 0.07, 0.06, 0.8))
			continue
		# the hole: a ragged breach low in the wall, its edge laid bare (in adobe, right at the foot)
		var hw := 7.0 * s
		var hh := 6.5 * s
		var lift := 0.0 if adobe else LIFT
		on = func(u: float, v: float) -> Vector2: return at + t * u + Vector2(0, -v - lift)
		var hole := PackedVector2Array()
		var rim := PackedVector2Array()
		var edge: Array[Vector2] = []   # (u, v) round the hole, for the splinters and cracks
		for i in 14:
			var ang := TAU * i / 14.0
			var j := r.randf_range(0.7, 1.15)
			var u := cos(ang) * hw * j
			var v := maxf(0.4 + i * 0.01, hh * 0.75 - sin(ang) * hh * j)
			edge.append(Vector2(u, v))
			hole.append(on.call(u, v))
			var k := r.randf_range(1.2, 1.5)
			rim.append(on.call(u * k, maxf(0.2 + i * 0.01, hh * 0.75 + (v - hh * 0.75) * k)))
		var bare := Color(0.6, 0.45, 0.31) if adobe else Color(0.64, 0.5, 0.33)
		c.draw_colored_polygon(rim, bare)
		if adobe:
			for i in 4 + int(3 * s):   # mud bricks showing through the plaster
				var e: Vector2 = edge[r.randi() % edge.size()] * r.randf_range(1.05, 1.3)
				var q := PackedVector2Array([on.call(e.x - 2.2, e.y), on.call(e.x + 2.2, e.y),
					on.call(e.x + 2.2, e.y + 1.6), on.call(e.x - 2.2, e.y + 1.6)])
				c.draw_colored_polygon(q, Color(0.55, 0.38, 0.25))
			for i in 3 + int(2 * s):   # and cracks running off into it
				var e: Vector2 = edge[r.randi() % edge.size()]
				var dir := e.normalized().rotated(r.randf_range(-0.5, 0.5))
				var p0: Vector2 = e * 1.35
				var p1 := p0 + dir * r.randf_range(4.0, 10.0) * s
				var mid := (p0 + p1) * 0.5 + dir.orthogonal() * r.randf_range(-1.5, 1.5)
				c.draw_polyline(PackedVector2Array([on.call(p0.x, p0.y), on.call(mid.x, mid.y), on.call(p1.x, p1.y)]),
					Color(0.24, 0.17, 0.12, 0.75), 1.0)
		c.draw_colored_polygon(hole, Color(0.08, 0.06, 0.05))
		c.draw_texture_rect(disc, Rect2(on.call(0, hh * 0.35) - Vector2(hw, hh * 0.4), Vector2(hw * 2.0, hh * 0.8)),
			false, Color(0.02, 0.015, 0.01, 0.6))   # (darker low down: the room behind)
		if not adobe:
			var mid := Vector2(0, hh * 0.75)
			for i in 4 + int(3 * s):   # splintered board ends jutting into the hole
				var e: Vector2 = edge[r.randi() % edge.size()]
				var tip := mid + (e - mid) * r.randf_range(0.7, 0.88)
				c.draw_colored_polygon(PackedVector2Array([on.call(e.x - 0.9, e.y), on.call(e.x + 0.9, e.y),
					on.call(tip.x, tip.y)]), Color(0.72, 0.58, 0.4) if r.randf() < 0.6 else Color(0.45, 0.32, 0.2))


## What the blast knocked out of the walls, heaped in the dirt at their foot: the
## sweepers leave it be (it's the town's, now, like the holes).
class Rubble extends Node2D:
	var bits: Array = []   # [where, size, colour, kind]: 0 a lump, 1 a splinter, 2 dust

	func heap(foot: Vector2, normal: Vector2, size: float, adobe: bool) -> void:
		var t := Vector2(0.894, 0.447) if normal.x < 0.0 else Vector2(0.894, -0.447)
		var out := normal.normalized()   # (into the street)
		bits.append([foot + out * 4.0 * size, 12.0 * size,
			Color(0.62, 0.5, 0.36, 0.35) if adobe else Color(0.5, 0.42, 0.32, 0.25), 2])
		for i in int(8 + 10 * size):
			var p := foot + t * Wounds.rng.randf_range(-11.0, 11.0) * size + out * pow(Wounds.rng.randf(), 1.5) * 12.0 * size
			if adobe or Wounds.rng.randf() < 0.3:
				var shade := Wounds.rng.randf_range(0.8, 1.1)
				bits.append([p, Wounds.rng.randf_range(1.0, 2.4), Color(0.62 * shade, 0.45 * shade, 0.3 * shade), 0])
			else:
				var shade := Wounds.rng.randf_range(0.55, 1.0)
				bits.append([p, Wounds.rng.randf_range(2.5, 6.0), Color(0.86 * shade, 0.7 * shade, 0.48 * shade), 1])
		queue_redraw()

	func _draw() -> void:
		var disc := Puff.disc_tex()
		for b in bits:
			var p: Vector2 = b[0]
			var sz: float = b[1]
			var col: Color = b[2]
			match b[3]:
				2:
					draw_texture_rect(disc, Rect2(p - Vector2(sz, sz * 0.5), Vector2(sz * 2.0, sz)), false, col)
				0:
					draw_texture_rect(disc, Rect2(p + Vector2(-sz, -sz * 0.2), Vector2(sz * 2.0, sz)), false, Color(0, 0, 0, 0.35))
					draw_colored_polygon(PackedVector2Array([p + Vector2(-sz, 0), p + Vector2(0, -sz * 0.6),
						p + Vector2(sz, 0), p + Vector2(0, sz * 0.5)]), col)
					draw_line(p + Vector2(-sz, 0), p + Vector2(0, -sz * 0.6), col.lightened(0.2), 1.0)
				1:
					var d := Vector2.from_angle(fposmod(p.x * 1.7 + p.y * 2.3, TAU)) * Vector2(1, 0.5) * sz * 0.5
					draw_line(p - d + Vector2(0, 0.6), p + d + Vector2(0, 0.6), Color(0, 0, 0, 0.3), 1.2)
					draw_line(p - d, p + d, col, 1.2)
