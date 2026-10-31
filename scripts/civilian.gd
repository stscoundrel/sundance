class_name Civilian
extends Actor
## Townsfolk: unarmed, and only in the way. They idle and stroll near home. Gunfire
## close by or in view, a round cracking past or a man dropping in front of them
## sends them running for the nearest doorway that isn't towards the shooting (or off
## the edge of town) and they're gone; the faint-hearted cower first. One in five or
## so is a snitch, and a sharp eye can tell: honest folk glance at the stranger and
## look away, a snitch keeps staring and edges off towards the bandits. Given a good
## long look he hurries to the nearest one, points him out and shouts, then makes
## himself scarce.

enum St { IDLE, WALK, FLEE, COWER, SNITCH, GONE }

const WALK := 18.0
const RUN := 52.0
const VIEW := 160.0
const FOV := deg_to_rad(65.0)
const CLOSE := 110.0     # gunfire this close frightens him even unseen
const HEAR := 320.0      # and this far off if he can see where it came from
const LOOK := 2.5        # seconds a snitch stares at the stranger before he runs to tell
const GLANCE := 0.9      # how long anyone else looks before averting his eyes
const FLEE_LINES := ["Lord help us!", "¡Corran!", "Get inside!"]
const SNITCH_LINES := ["There! A stranger!", "¡Allá, un gringo!"]
const MURDER_LINES := ["Murderer!", "¡Asesino!", "He shot him down!", "¡Dios mío!"]

var kind := "townsman"
var tdata: Dictionary
var st := St.IDLE
var home := Vector2.ZERO
var path := PackedVector2Array()
var path_i := 0
var wait := 0.0
var walk := WALK
var run := RUN
var nerve := 0.5
var snitch := false
var threat := Vector2.ZERO
var desired := Vector2.DOWN
var saw_t := 0.0         # how long he's had the stranger in view
var watching := false    # eyes on the stranger this frame (he turns his head, not his walk)
var looked_away := false
var sidle := Vector2.ZERO  # a snitch drifting off towards the bandits
var seen_at := Vector2.ZERO
var cower_t := 0.0
var tell: Enemy          # the bandit a snitch is running to
var told_t := 0.0
var repath_t := 0.0
var shout := ""
var shout_t := 0.0
var t := 0.0


func setup(g: Node, k: String, pos: Vector2, facing_deg: float, overrides := {}) -> void:
	setup_body(g, pos)
	kind = k
	tdata = g.civilian_type(k, overrides)
	hp = 1
	max_hp = 1
	weapon = Weapon.new("unarmed", self)
	var palettes: Array = tdata["palettes"]
	set_character(tdata["template"], palettes[int(tdata.get("palette", randi() % palettes.size())) % palettes.size()])
	walk = WALK * float(tdata["speed"])
	run = RUN * float(tdata["speed"])
	nerve = randf_range(tdata["nerve"][0], tdata["nerve"][1])
	snitch = randf() < float(tdata["snitch"])
	home = pos
	facing = Vector2.from_angle(deg_to_rad(facing_deg))
	desired = facing
	wait = randf_range(1.0, 6.0)
	t = randf() * 10.0


# ------------------------------------------------------------------ senses

func sees(pos: Vector2) -> bool:
	var to := pos - global_position
	return to.length() < VIEW and abs(facing.angle_to(to)) < FOV and game.line_of_sight(global_position, pos, false)


## Gunfire: close, or in sight within earshot, and he's off.
func hear(pos: Vector2, radius: float, _k: String, source: Node) -> void:
	if not alive or st in [St.FLEE, St.COWER, St.GONE] or source == self:
		return
	var d := global_position.distance_to(pos)
	if d > minf(radius, HEAR):
		return
	if d < CLOSE or game.line_of_sight(global_position, pos, false):
		alarm(pos, false)


func near_miss(from: Vector2) -> void:
	alarm(from, true)


func witness_death(at: Vector2) -> void:
	if alive and global_position.distance_to(at) < 200.0 and game.line_of_sight(global_position, at, false):
		alarm(at, true)


## The stranger shot one of us: those who saw it say so.
func witness_murder(at: Vector2) -> void:
	if alive and st != St.GONE and global_position.distance_to(at) < 220.0 \
			and game.line_of_sight(global_position, at, false):
		_say(MURDER_LINES.pick_random())
		alarm(at, true)


## Run for it, or (short of nerve, or caught close) cower first.
func alarm(from: Vector2, scary: bool) -> void:
	if not alive or st in [St.FLEE, St.GONE]:
		return
	threat = from
	if st == St.COWER:
		return
	var freeze := (1.0 - nerve) * (0.7 if scary else 0.4)
	if randf() < freeze:
		st = St.COWER
		cower_t = randf_range(2.0, 5.0)
		velocity = Vector2.ZERO
		return
	_flee()


func _flee() -> void:
	st = St.FLEE
	crouched = false
	path = game.find_path(global_position, game.refuge_for(global_position, threat))
	path_i = 0
	if randf() < 0.5:
		_say(_line("flee", FLEE_LINES))
	game.stats["civilian flees"] = game.stats.get("civilian flees", 0) + 1


# ------------------------------------------------------------------ frame

func _physics_process(delta: float) -> void:
	t += delta
	if not alive:
		if dying():
			update_anim(delta)
		return
	if st == St.GONE:
		return
	shout_t = max(0.0, shout_t - delta)
	if game.state != "play" and game.state != "lost":
		velocity = Vector2.ZERO
		update_anim(delta)
		return
	pose = ""
	if game.state == "play":
		_perceive(delta)
	match st:
		St.IDLE:
			_idle(delta)
		St.WALK:
			if _follow(walk):
				st = St.IDLE
				wait = randf_range(3.0, 8.0)
		St.FLEE:
			if _follow(run):
				_go_inside()
				return
		St.COWER:
			velocity = Vector2.ZERO
			crouched = true
			pose = "cower"
			cower_t -= delta
			if cower_t <= 0.0:
				_flee()
		St.SNITCH:
			_snitch(delta)
	if velocity.length() > 1.0 and not watching:
		desired = velocity.normalized()
	facing = facing.rotated(clamp(facing.angle_to(desired), -3.0 * delta, 3.0 * delta))
	move_and_slide()
	update_anim(delta)


func _perceive(delta: float) -> void:
	var p: Player = game.player
	if not p.alive or st in [St.FLEE, St.COWER, St.SNITCH]:
		return
	watching = false
	sidle = Vector2.ZERO
	if sees(p.global_position):
		saw_t += delta
		seen_at = p.global_position
		var to_him := (p.global_position - global_position).normalized()
		if snitch:
			# the tell: he doesn't look away, and he starts drifting off to the bandits
			if saw_t > 0.3:
				watching = true
				desired = to_him
			if saw_t > 1.0:
				var b := _nearest_bandit()
				if b:
					sidle = (b.global_position - global_position).normalized()
			if saw_t > LOOK:
				_start_snitch()
		elif saw_t < GLANCE:
			if saw_t > 0.3:
				watching = true
				desired = to_him
		elif not looked_away:
			looked_away = true   # eyes down, none of his business
			desired = (-to_him).rotated(randf_range(-1.2, 1.2))
	else:
		saw_t = max(0.0, saw_t - delta * 0.5)
		if saw_t == 0.0:
			looked_away = false


func _idle(delta: float) -> void:
	velocity = sidle * walk * 0.6
	wait -= delta
	if not watching and not looked_away:
		desired = facing.rotated(sin(t * 0.4) * 0.02)
	if wait <= 0.0:
		var r: float = float(tdata["wander"])
		var to: Vector2 = game.free_point_near(home, r) if r > 0.0 else home
		path = game.find_path(global_position, to)
		path_i = 0
		st = St.WALK


func _follow(speed: float) -> bool:
	while path_i < path.size() and global_position.distance_to(path[path_i]) < 4.0:
		path_i += 1
	if path_i >= path.size():
		velocity = Vector2.ZERO
		return true
	velocity = (path[path_i] - global_position).normalized() * speed
	return false


## Through the door (or off the edge of town): out of the story.
func _go_inside() -> void:
	st = St.GONE
	velocity = Vector2.ZERO
	occluded = false
	_sync_ghost()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("collision_layer", 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): visible = false)
	game.stats["civilian hides"] = game.stats.get("civilian hides", 0) + 1


# ------------------------------------------------------------------ snitching

func _nearest_bandit() -> Enemy:
	var best := 420.0
	var out: Enemy = null
	for e in game.enemies:
		if e.alive and e.st != Enemy.St.COMBAT:
			var d := global_position.distance_to(e.global_position)
			if d < best:
				best = d
				out = e
	return out


func _start_snitch() -> void:
	tell = _nearest_bandit()
	snitch = false   # once is enough
	if tell == null:
		return
	st = St.SNITCH
	told_t = 0.0
	repath_t = 0.0
	game.stats["snitch runs"] = game.stats.get("snitch runs", 0) + 1


func _snitch(delta: float) -> void:
	if tell == null or not tell.alive:
		_flee_from(seen_at)
		return
	if told_t > 0.0:
		# pointing the way, then off he goes
		told_t -= delta
		velocity = Vector2.ZERO
		pose = "point"
		desired = (seen_at - global_position).normalized()
		if told_t <= 0.0:
			_flee_from(seen_at)
		return
	if global_position.distance_to(tell.global_position) < 34.0:
		_say(_line("snitch", SNITCH_LINES))
		told_t = 1.8
		tell.enter_combat(seen_at, false, true)
		game.stats["snitch tells"] = game.stats.get("snitch tells", 0) + 1
		return
	repath_t -= delta
	if repath_t <= 0.0:
		repath_t = 1.0
		path = game.find_path(global_position, tell.global_position)
		path_i = 0
	_follow(run * 0.8)


func _flee_from(at: Vector2) -> void:
	threat = at
	_flee()


# ------------------------------------------------------------------ talk

func _say(s: String) -> void:
	shout = s
	shout_t = 1.8


func _line(key: String, stock: Array) -> String:
	var own: Dictionary = tdata.get("shouts", {})
	return (own[key] if own.has(key) else stock).pick_random()


func gone() -> bool:
	return st == St.GONE
