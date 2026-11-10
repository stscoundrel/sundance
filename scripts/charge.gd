class_name Charge
extends Node2D
## A powder keg or a crate of dynamite that's been hit, on its way to going up. A
## keg fizzes and spits sparks from its bung for a second; a crate of dynamite
## catches and burns for a few, flames and black smoke, before the biggest bang
## there is. Either is set off at once by a blast close by (a chain of them goes up
## one after another). Once it's going, nothing stops it; nobody gets the blame but
## whoever hit it. A ring on the ground shows how far it'll reach.

static var rng := RandomNumberGenerator.new()   # (the sparks and smoke: only looks, but its own dice)

# fuse: s from the hit to the bang; r: the blast's reach; core: nobody lives through it
const KINDS := {
	"keg": {"fuse": 1.0, "r": 110.0, "core": 45.0, "top": 11.0},
	"dyn_crate": {"fuse": 3.0, "r": 150.0, "core": 60.0, "top": 8.0},
}

var game: Node
var prop: Dictionary
var by: Actor
var fuse := 1.0
var full := 1.0
var r := 110.0
var core := 45.0
var top := 10.0
var puff_t := 0.0
var ring: Node2D
var hiss: AudioStreamPlayer2D


func setup(g: Node, p: Dictionary, shooter: Actor, delay := -1.0) -> void:
	game = g
	prop = p
	by = shooter
	var k: Dictionary = KINDS[p["kind"]]
	fuse = float(k["fuse"]) if delay < 0.0 else delay
	full = fuse
	r = k["r"]
	core = k["core"]
	top = k["top"]
	global_position = game.prop_centre(p)
	ring = Node2D.new()
	ring.z_as_relative = false
	ring.z_index = -9   # on the ground: over the view cones, under everyone
	ring.draw.connect(_draw_ring)
	add_child(ring)
	if game._streams.has("fuse") and fuse > 0.4:
		hiss = AudioStreamPlayer2D.new()
		hiss.stream = game._streams["fuse"][0]
		hiss.volume_db = -4.0
		hiss.pitch_scale = 0.75 if p["kind"] == "dyn_crate" else 1.1
		hiss.max_distance = 1000.0
		add_child(hiss)
		hiss.play()


func _physics_process(delta: float) -> void:
	if game.state == "title" or game.state == "loadout":
		return
	fuse -= delta
	if fuse <= 0.0:
		game.detonate(self)
		queue_free()
		return
	puff_t -= delta
	if puff_t <= 0.0:
		puff_t = 0.06
		_spit()
	ring.queue_redraw()


## Sparks from the keg's bung; flames and smoke off the burning crate.
func _spit() -> void:
	var puff := Puff.new()
	puff.position = global_position + Vector2(0, -top)
	if prop["kind"] == "keg":
		for i in 4:
			puff.add(Vector2.ZERO, Vector2(rng.randf_range(-40, 40), -rng.randf_range(30, 90)), rng.randf_range(0.2, 0.4),
				rng.randf_range(0.6, 1.1), Color(1.0, rng.randf_range(0.7, 0.95), 0.4, 1.0), 0.0, 260.0)
		puff.smoke(Vector2.ZERO, Vector2(rng.randf_range(-6, 6), -rng.randf_range(10, 25)), rng.randf_range(0.6, 1.0),
			rng.randf_range(1.5, 2.5), Color(0.82, 0.8, 0.76, 0.35), 2.0, game.WIND)
	else:
		for i in 3:
			puff.add(Vector2(rng.randf_range(-10, 10), rng.randf_range(-3, 3)), Vector2(rng.randf_range(-8, 8), -rng.randf_range(25, 55)),
				rng.randf_range(0.25, 0.5), rng.randf_range(2.0, 3.5), Color(1.0, rng.randf_range(0.45, 0.75), 0.15, 0.9), -3.0)
		puff.smoke(Vector2(rng.randf_range(-8, 8), -6), Vector2(rng.randf_range(-6, 6), -rng.randf_range(25, 45)),
			rng.randf_range(1.5, 2.5), rng.randf_range(3.0, 4.5), Color(0.2, 0.18, 0.16, 0.45), 4.0, game.WIND)
	game.world.add_child(puff)


## The blast's reach on the ground, pulsing quicker as it burns down.
func _draw_ring() -> void:
	var urgency: float = 1.0 - fuse / maxf(full, 0.01)
	var pulse: float = 0.5 + 0.5 * sin(game.clock * (8.0 + 20.0 * urgency))
	var col := Color(0.95, 0.24, 0.1, 0.6 + 0.35 * pulse)
	ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	ring.draw_circle(Vector2.ZERO, r, Color(0.92, 0.26, 0.12, 0.08 + 0.07 * pulse))
	var n := 36
	var turn: float = game.clock * 0.8
	for i in n:
		var a0: float = turn + TAU * i / n
		ring.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / n * 0.55, 3, col, 2.5)
	ring.draw_set_transform(Vector2.ZERO)
