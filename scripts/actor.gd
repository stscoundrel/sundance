class_name Actor
extends CharacterBody2D
## Shared body for the hero and the bandits: hurtbox, facing, crouching, damage, and a
## two-layer animated sprite. The legs layer follows movement; the upper body (arms,
## head, gun) plays the gun's own animations and reactions on top of it, raised or
## lowered by the hip height of the current legs frame. Deaths are whole-body.

signal died(actor: Actor)

const PZ := 15.7   # world px per metre of height
const PALETTE_SHADER := preload("res://shaders/palette.gdshader")
const SILHOUETTE_SHADER := preload("res://shaders/silhouette.gdshader")
const HITS := ["hit_l", "hit_r", "hit_gut"]
const NO_ANIM := {}

var game: Node
var hurtbox: Area2D
var legs_spr: Sprite2D
var upper_spr: Sprite2D
var weapon: Weapon
var facing := Vector2.RIGHT
var crouched := false
var alive := true
var hp := 2
var max_hp := 2
var is_player := false
var flash_t := 0.0
var pose := ""        # held upper-body pose set by the AI each frame: "point", "flinch", "cower"
var action := ""      # one-shot upper-body animation: "fire", "hit_l", "hit_r", "hit_gut"
var action_t := 0.0
var limp_t := 0.0     # a leg wound: he limps for a while
var stagger_t := 0.0  # knocked back a step

var char_key := ""
var cdata: Dictionary
var _anims: Dictionary    # cdata's animations, by key
var _shown := [null, null]  # the frame each sprite (legs, upper) shows
var _move_t := 0.0    # distance-driven clock for walk cycles
var _layers := {}     # layer -> [anim key, start time, last frame]
var _clock := 0.0
var _death := ""
var ghost: Node2D          # his silhouette, shown over buildings that hide him
var occluded := false
var anim_gun := ""         # play another gun's upper-body set ("unarmed": hiding his)
var killer: Actor          # who shot him dead
var propped := false       # alive, but down in the dirt: drawn whole from _death like the dead
var lie_dir := -1          # which way his hurtbox is laid along him, lying there
var stand_shape: Shape2D   # (and the one he had on his feet)
var blasted := false       # being hit by dynamite (just for the length of the hit)
var lift := Vector2.ZERO   # drawn this far off his ground point (up on the gallows)
# Wounded, he bleeds till he's bandaged: a drop in the dirt every few steps (and
# now and then where he stands), a trail anyone can follow.
const DRIP_EVERY := 14.0   # px walked between drops
const DRIP_STILL := 2.5    # s standing between drops
var bleeding := false
var _drip_from := Vector2.INF
var _drip_t := 0.0


func setup_body(g: Node, pos: Vector2) -> void:
	game = g
	global_position = pos
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = Iso.LAYER_ACTOR
	collision_mask = Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 4.0
	cs.shape = c
	add_child(cs)

	hurtbox = Area2D.new()
	hurtbox.collision_layer = Iso.LAYER_HURT
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	var hs := CollisionShape2D.new()
	var hc := CircleShape2D.new()
	hc.radius = 7.0
	hs.shape = hc
	hurtbox.add_child(hs)
	hurtbox.set_meta("actor", self)
	add_child(hurtbox)

	for i in 2:
		var s := Sprite2D.new()
		s.centered = false
		s.region_enabled = true
		add_child(s)
		if i == 0:
			legs_spr = s
		else:
			upper_spr = s
	if g.level.get("weather", "") == "snow":   # (breath in the cold: after his sprites, drawn over them)
		var br := Breath.new()
		br.setup(self)
		add_child(br)


## A silhouette copy of him on a layer above the buildings, shown while he's hidden.
func make_ghost(layer: Node2D, tint: Color) -> void:
	ghost = Node2D.new()
	layer.add_child(ghost)
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	mat.set_shader_parameter("tint", tint)
	for s in [legs_spr, upper_spr]:
		var g := Sprite2D.new()
		g.centered = false
		g.region_enabled = true
		g.texture = s.texture
		g.scale = s.scale
		g.material = mat
		ghost.add_child(g)
	ghost.visible = false


func set_ghost_tint(tint: Color) -> void:
	if ghost:
		(ghost.get_child(0) as Sprite2D).material.set_shader_parameter("tint", tint)


func _sync_ghost() -> void:
	if ghost == null:
		return
	ghost.visible = occluded and alive
	if not ghost.visible:
		return
	ghost.position = global_position
	var src := [legs_spr, upper_spr]
	for i in 2:
		var g: Sprite2D = ghost.get_child(i)
		g.visible = src[i].visible
		g.region_rect = src[i].region_rect
		g.offset = src[i].offset
		g.position = src[i].position


## Use a body template's atlas ("hero", "poncho", "suit", ...) painted with a palette
## ({slot name: [r, g, b]}); slots it doesn't name stay neutral grey.
func set_character(template: String, palette: Dictionary) -> void:
	char_key = template
	cdata = game.meta["chars"][template]
	_anims = cdata.get("anims", {})
	var tex: Texture2D = game.tex(cdata["atlas"])
	var mat := painted(game, template, palette)
	for s in [legs_spr, upper_spr]:
		s.texture = tex
		s.scale = Vector2.ONE * game.tex_scale
		s.material = mat


## A body template's paint: its slots coloured from `palette`, the rest neutral grey
## (his own, and the briefing card's stills of who's who).
static func painted(g: Node, template: String, palette: Dictionary) -> ShaderMaterial:
	var cd: Dictionary = g.meta["chars"][template]
	var neutral: float = float(g.meta.get("neutral", 200)) / 255.0
	var pal := PackedVector3Array()
	pal.resize(16)
	pal.fill(Vector3(neutral, neutral, neutral))
	var names: Array = g.enemy_data["slots"]
	for i in names.size():
		if palette.has(names[i]):
			var c: Array = palette[names[i]]
			pal[i + 1] = Vector3(c[0], c[1], c[2]) / 255.0
	var mat := ShaderMaterial.new()
	mat.shader = PALETTE_SHADER
	mat.set_shader_parameter("slots", g.tex(cd["slots"]))
	mat.set_shader_parameter("pal", pal)
	mat.set_shader_parameter("neutral", neutral)
	return mat


## Draw nothing of him below world height `y` (1e9: all of him).
func clip_below(y: float) -> void:
	(legs_spr.material as ShaderMaterial).set_shader_parameter("clip_y", y)


func anim(key: String) -> Dictionary:
	return _anims.get(key, NO_ANIM)


func has_anim(key: String) -> bool:
	return _anims.has(key)


func _upper_key(name: String) -> String:
	return "upper/%s/%s" % [anim_gun if anim_gun != "" else weapon.kind, name]


## Length in seconds of an upper-body animation for the current gun.
func anim_length(name: String) -> float:
	var a := anim(_upper_key(name))
	if a.is_empty():
		return 0.0
	return a["frames"][0].size() / float(a["fps"])


## Play a one-shot upper-body animation; it overrides poses and the gun's state.
func play_action(name: String) -> void:
	if not alive or (weapon == null and anim_gun == "") or not has_anim(_upper_key(name)):
		return
	action = name
	action_t = anim_length(name)
	_layers.erase("upper")   # restart it even if the same one is already playing


func is_staggered() -> bool:
	return (action in HITS and action_t > 0.0) or stagger_t > 0.0


## Movement speed multiplier: a leg wound slows him down.
func limp_factor() -> float:
	return 0.6 if limp_t > 0.0 else 1.0


func _upper_choice() -> String:
	if action != "" and action_t > 0.0:
		return action
	if pose != "":
		return pose
	if weapon:
		match weapon.state:
			Weapon.S.OPEN:
				return "reload_open"
			Weapon.S.EJECT:
				return "reload_eject" if has_anim(_upper_key("reload_eject")) else "reload_open"
			Weapon.S.INSERT:
				return "reload_insert"
			Weapon.S.CLOSE:
				return "reload_close"
			Weapon.S.CYCLE:
				if weapon.fanning:
					return "fan"
				if weapon.racking and has_anim(_upper_key("lever2")):
					return "lever2"   # a pump gun run dry: two strokes
				for a in ["cock", "lever"]:   # whichever this gun has
					if has_anim(_upper_key(a)):
						return a
	return "aim"


func _legs_choice(moving: bool) -> String:
	if crouched or pose == "cower":
		return "legs/cwalk" if moving else "legs/crouch"
	if stagger_t > 0.0:
		return "legs/stagger"
	if moving:
		return "legs/limp" if limp_t > 0.0 else "legs/walk"
	return "legs/idle"


## Advance one layer and return [anim, frame]. Animations restart when they change;
## looping ones cycle, the rest hold their last frame. Walk cycles run on distance.
func _advance(layer: String, key: String) -> Array:
	var st = _layers.get(layer)
	if st == null or st[0] != key:
		st = [key, _clock, -1]
	var a := anim(key)
	var n: int = a["frames"][0].size()
	var t: float = _move_t if a.get("speed", false) else _clock - st[1]
	var f := int(t * float(a["fps"]))
	f = posmod(f, n) if a["loop"] else mini(f, n - 1)
	if f != st[2]:
		var ev: Dictionary = a.get("events", {})
		if ev.has(str(f)):
			game.anim_event(self, ev[str(f)])
	st[2] = f
	_layers[layer] = st
	return [a, f]


func _show(spr: Sprite2D, a: Dictionary, f: int, dir: int) -> void:
	var fr: Array = a["frames"][dir][f]
	var i := 0 if spr == legs_spr else 1
	if is_same(fr, _shown[i]):
		return   # still the same frame
	_shown[i] = fr
	spr.region_rect = Rect2(fr[0], fr[1], fr[2], fr[3])
	spr.offset = Vector2(fr[4], fr[5])


func update_anim(delta: float) -> void:
	_clock += delta
	action_t = max(0.0, action_t - delta)
	stagger_t = max(0.0, stagger_t - delta)
	limp_t = max(0.0, limp_t - delta)
	var speed := velocity.length()
	var moving := speed > 4.0
	if moving:
		_move_t += delta * speed / 40.0
	var dir := Iso.dir8(facing)
	if bleeding and alive:
		_bleed(delta)

	if not alive or propped:
		var r := _advance("full", "full/" + _death)
		_show(upper_spr, r[0], r[1], dir)
		upper_spr.position = lift
		legs_spr.visible = false
		_sync_ghost()
		return

	var l := _advance("legs", _legs_choice(moving))
	_show(legs_spr, l[0], l[1], dir)
	var hip: float = l[0]["hip"][l[1]]
	legs_spr.position = lift
	upper_spr.position = lift + Vector2(0, (float(cdata["h_ref"]) - hip) * PZ)
	var u := _advance("upper", _upper_key(_upper_choice()))
	_show(upper_spr, u[0], u[1], dir)
	_sync_ghost()

	if flash_t > 0.0:
		flash_t -= delta
		var c := Color(1.8, 0.8, 0.7) if flash_t > 0.0 else Color.WHITE
		legs_spr.modulate = c
		upper_spr.modulate = c


func _bleed(delta: float) -> void:
	_drip_t += delta
	if _drip_from == Vector2.INF:
		_drip_from = global_position
	if global_position.distance_to(_drip_from) > DRIP_EVERY or _drip_t > DRIP_STILL:
		_drip_from = global_position
		_drip_t = 0.0
		game.drip(self, global_position)


## Where the muzzle is, relative to his feet, in the frame now showing (the left
## gun's, of a pair, after it fired).
func muzzle_offset() -> Vector2:
	var st: Array = _layers.get("upper" if alive and not propped else "full", [])
	if not st.is_empty():
		var a := anim(st[0])
		var key := "muzzle2" if weapon and weapon.hand == 1 and a.has("muzzle2") else "muzzle"
		if a.has(key):
			var m = a[key][Iso.dir8(facing)][maxi(st[2], 0)]
			if m != null:
				return upper_spr.position + Vector2(m[0], m[1]) * game.tex_scale
	return facing * 12.0 + Vector2(0, -gun_height())


func gun_height() -> float:
	var h := Iso.GUN_H_CROUCH if crouched else Iso.GUN_H
	if weapon and weapon.is_shotgun():
		h -= 3.0   # carried at the hip
	return h


## His body on the ground, end to end, in screen space (by how he fell and which
## way he's lying).
func lie_line() -> PackedVector2Array:
	var l: Array = game.meta["lie"]["gasp" if "/" in _death else _death][Iso.dir8(facing)]
	return PackedVector2Array([global_position + Vector2(l[0][0], l[0][1]) * game.tex_scale,
		global_position + Vector2(l[1][0], l[1][1]) * game.tex_scale])


## Down, his hurtbox goes from round his boots to the length of him in the dirt (a
## round aimed at the body as drawn should find it).
func _lay_hurtbox() -> void:
	var d := Iso.dir8(facing)
	if d == lie_dir:
		return
	lie_dir = d
	var l := lie_line()
	var a := l[0] - global_position
	var b := l[1] - global_position
	var hs: CollisionShape2D = hurtbox.get_child(0)
	if stand_shape == null:
		stand_shape = hs.shape
	var c := CapsuleShape2D.new()
	c.radius = 6.0
	c.height = a.distance_to(b) + c.radius * 2.0
	hs.set_deferred("shape", c)
	hs.set_deferred("position", (a + b) / 2.0)
	hs.set_deferred("rotation", (b - a).angle() - PI / 2.0)   # (a capsule stands upright)


func _stand_hurtbox() -> void:
	lie_dir = -1
	if stand_shape == null:
		return
	var hs: CollisionShape2D = hurtbox.get_child(0)
	hs.set_deferred("shape", stand_shape)
	hs.set_deferred("position", Vector2.ZERO)
	hs.set_deferred("rotation", 0.0)


## Spread multiplier applied to the weapon's base spread.
## How far his rounds carry, as a share of the gun's own reach (the smoke of a big
## battle shortens it for the army; the stranger sees through it).
func range_mult() -> float:
	return 1.0


func accuracy_mult() -> float:
	return 1.0


func on_fired(_shake: float) -> void:
	pass


func take_hit(dmg: int, from_dir: Vector2, shooter: Actor) -> void:
	if not alive:
		return
	hp -= dmg
	flash_t = 0.12
	game.blood(global_position, from_dir, gun_height())
	game.sfx("hit", global_position, -2.0)
	if hp <= 0:
		die(from_dir, shooter)
		return
	bleeding = true
	# Where it struck decides how he reels: a leg (stagger, then a limp), the gut
	# (doubled over), or a shoulder, which snaps back on the side it came from.
	var r := randf()
	if r < 0.2:
		stagger_t = 0.5
		limp_t = randf_range(5.0, 8.0)
		play_action("hit_gut" if randf() < 0.3 else ("hit_l" if randf() < 0.5 else "hit_r"))
	elif r < 0.45:
		play_action("hit_gut")
	else:
		play_action("hit_l" if facing.cross(-from_dir) < 0.0 else "hit_r")


## His own gun's chainfire: the hand out in front of the cylinder burnt, a point
## off him and no one else to blame. A burn, not a round: no blood, no limp, the
## left hand snatched back; and on the chainfire's own dice, so a seeded fight
## stays as it was up to it.
func chain_burn() -> void:
	if not alive:
		return
	hp -= 1
	flash_t = 0.12
	game.sfx("hit", global_position, -2.0, 0.06, Weapon.chain_rng)
	if hp <= 0:
		die(-facing, self)
		return
	play_action("hit_l")


func die(from_dir: Vector2, shooter: Actor = null, how := "") -> void:
	alive = false
	killer = shooter
	crouched = false
	flash_t = 0.0
	legs_spr.modulate = Color.WHITE
	upper_spr.modulate = Color.WHITE
	pose = ""
	action = ""
	velocity = Vector2.ZERO
	facing = -from_dir
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("collision_layer", 0)
	_death = how if how != "" else _pick_death(shooter)
	if weapon:
		weapon.abort()
		game.drop_gun(self)
	update_anim(0.0)
	game.lay_pool(self)
	died.emit(self)


## Thrown back by dynamite, or a shotgun blast up close; otherwise one of the four, the slow
## Leone slump among them.
func _pick_death(shooter: Actor) -> String:
	if blasted:
		return "death_back"   # flung off his feet
	if shooter and shooter.weapon and shooter.weapon.is_shotgun() \
			and shooter.global_position.distance_to(global_position) < 90.0:
		return "death_back"
	var w := {"death_knees": 0.3, "death_spin": 0.25, "death_slump": 0.25, "death_back": 0.2}
	var r := randf()
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "death_knees"


## Still playing his death (so the body keeps moving)?
func dying() -> bool:
	if alive and not propped or _death == "":
		return false
	var a := anim("full/" + _death)
	return _clock - float(_layers.get("full", ["", _clock])[1]) < a["frames"][0].size() / float(a["fps"]) + 0.1
