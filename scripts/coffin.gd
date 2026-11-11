class_name Coffin
extends Node2D
## The stranger's own coffin, at the graveside at his funeral (the map's "coffin":
## its corner, before his empty grave). He starts in it, the lid nailed down over
## him: nobody can see him and he can't move (the player still sees the graveside
## round him, as ever). Every press of E is a blow on the lid from inside: an
## unnailed lid gives on the first, and a nailed one takes BLOWS_PER_NAIL a nail
## ("nails": the level's, or --nails=N, or the tests' meta; phase 3 drives them in
## from his record).
##
## The guests round the grave may hear the knocking, one blow in three or so each
## (they've the padre to listen to). A man who does turns to the coffin and mutters,
## once, and goes back to listening: a dead man knocking is nothing a man draws on.
## When the lid gives, it flies off and he stands up out of the box, the pair of
## Colts in his hands. Everyone who sees it, near or far, is struck dumb for a few
## seconds, each his own (Enemy "agape"), and then fumbles for his gun; the others,
## out of sight at the horses and the drink, only hear the crash (see the wake in
## Enemy). There's no stand-off close-up: the surprise is his, not theirs, and the
## seconds are the player's to use.

static var rng := RandomNumberGenerator.new()   # (how long each man stares, what he mutters: its own dice)

const BLOWS_PER_NAIL := 2
const NAILS := 1                    # the lid's nails when nothing else says
const KNOCK_EAR := 130.0            # px: a guest this near may hear the knocking...
const KNOCK_HEARD := 0.35           # ...this often, a blow
const STUN_R := 230.0               # px: a guest this near sees him come out, whichever way he faces
const STUN_T := Vector2(2.0, 4.0)   # s struck dumb
const OUT := 0.85                   # tiles: where he stands, before the box (away from the grave)

var game: Node
var nails := NAILS
var blows := 0
var inside := false
var out_at := Vector2.ZERO          # where he stands up (screen)
var sprite: Sprite2D
var lid: Sprite2D = null
var _corner := Vector2.ZERO         # the box's corner (tiles)
var _shake_t := 0.0


func setup(g: Node, corner: Vector2, n: int) -> void:
	game = g
	nails = n
	_corner = corner
	var fp := _footprint("his_coffin")
	global_position = Iso.to_screen(corner + fp * 0.5)
	out_at = Iso.to_screen(corner + Vector2(fp.x * 0.5, fp.y + OUT))
	sprite = _sprite("his_coffin", corner)
	add_child(sprite)


func _footprint(k: String) -> Vector2:
	var m: Dictionary = game.meta["objects"][k]
	return Vector2(m["footprint"][0], m["footprint"][1])


## A sprite of object `k`, its corner at `corner` (tiles), placed as the map's own are.
func _sprite(k: String, corner: Vector2) -> Sprite2D:
	var m: Dictionary = game.meta["objects"][k]
	var s := Sprite2D.new()
	s.texture = game.tex(m["file"])
	s.centered = false
	s.scale = Vector2.ONE * game.tex_scale
	s.offset = ((Iso.to_screen(corner) - global_position) / game.tex_scale - Vector2(m["anchor"][0], m["anchor"][1])).round()
	return s


## The stranger laid in it, the lid on.
func shut_in(p: Player) -> void:
	inside = true
	p.in_coffin = true
	p.visible = false
	p.velocity = Vector2.ZERO
	p.global_position = global_position


## Blows still to come before the lid gives: BLOWS_PER_NAIL a nail, or one kick
## for a lid that isn't nailed.
func blows_left() -> int:
	return maxi(0, maxi(1, nails * BLOWS_PER_NAIL) - blows)


## The nails still holding it.
func nails_left() -> int:
	return ceili(blows_left() / float(BLOWS_PER_NAIL)) if nails > 0 else 0


func _process(delta: float) -> void:
	if _shake_t > 0.0:   # (the box jumping: a wobble, no dice, the frame rate being what it is)
		_shake_t -= delta
		sprite.position = Vector2(sin(_shake_t * 90.0), -absf(sin(_shake_t * 60.0))) * game.tex_scale if _shake_t > 0.0 else Vector2.ZERO
	if inside and game.state == "play" and Input.is_action_just_pressed("knife"):
		blow()


## A blow on the lid from inside: the box jumps, a guest close by may hear it, and
## every BLOWS_PER_NAIL a nail screeches out. The last one and it's off.
func blow() -> void:
	if not inside:
		return
	var held := nails_left()
	blows += 1
	_shake_t = 0.12
	game.sfx("wood_hit", global_position, -4.0, 0.15)
	if nails_left() < held:
		game.sfx("twang", global_position, -10.0, 0.2)   # a nail drawn
	for e in game.enemies:
		if e.alive and e.global_position.distance_to(global_position) < KNOCK_EAR and rng.randf() < KNOCK_HEARD:
			e.knocked(global_position)
	if blows_left() == 0:
		burst()


## Out: the lid flies off, the box stands open, and he's up out of it beside it.
## Everyone who sees it stands there with his mouth open; the crash carries further.
func burst() -> void:
	inside = false
	var p: Player = game.player
	sprite.texture = game.tex(game.meta["objects"]["his_coffin_open"]["file"])
	var lc := _corner + Vector2(-1.8, 0.05)   # (the lid, thrown off past the head of the box)
	lid = _sprite("coffin_lid", lc)
	add_child(lid)
	lid.position = Vector2(0, -10)
	create_tween().tween_property(lid, "position", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	game.sfx("wood_break", global_position, 2.0, 0.05)
	p.in_coffin = false
	p.visible = true
	p.rise_from_coffin(global_position + Vector2(0, 3), out_at)   # (a touch forward: drawn in front of the box's far side)
	game.stats["out of the coffin"] = snappedf(game.clock, 0.1)
	var stunned := 0
	for e in game.enemies:
		if e.alive and (e.visibility_of(out_at, false, false) > 0.0
				or e.global_position.distance_to(out_at) < STUN_R and game.line_of_sight(e.global_position, out_at, false)):
			e.agape(out_at, rng.randf_range(STUN_T.x, STUN_T.y), rng)
			stunned += 1
	game.stats["struck dumb"] = stunned
	game.alerted_once = true   # (the stand-off's spent: no close-up when the first of them comes to)
	game.make_noise(global_position, 420.0, "crash", p)   # (heard about the valley: not a shot, but something)
