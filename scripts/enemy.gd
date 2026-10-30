class_name Enemy
extends Actor
## Bandit AI: guard or patrol, grow suspicious of glimpses and noises, fight with a
## reaction delay and aim error, run to cover to reload, search when they lose you.

enum St { GUARD, PATROL, INVESTIGATE, COMBAT, SEARCH, RETURN }

const KINDS := {
	"pistolero": {"weapon": "colt", "hp": 2, "keep": Vector2(70, 170), "cadence": Vector2(0.7, 1.3)},
	"rifleman": {"weapon": "rifle", "hp": 2, "keep": Vector2(130, 320), "cadence": Vector2(1.1, 1.8)},
	"redscarf": {"weapon": "coach", "hp": 2, "keep": Vector2(25, 80), "cadence": Vector2(0.5, 1.0)},
	"jefe": {"weapon": "coach", "hp": 4, "keep": Vector2(30, 95), "cadence": Vector2(0.45, 0.9)},
}
const WALK := 24.0
const RUN := 46.0
# Difficulty knobs: spread multiplier on the weapon's base spread, and a multiplier
# on the pause between shots.
const AIM_SPREAD := 4.0
const AIM_SPREAD_SHOTGUN := 1.5
const CADENCE_MULT := 1.8
const SPOT_LINES := ["¡Allí está!", "There he is!", "¡El gringo!", "Over there!", "¡Mátalo!"]
const SCARE_LINES := ["¡Ay, Dios!", "Whoa!", "¡Cuidado!", "Get down!"]
const COWER_LINES := ["¡Madre de Dios!", "Don't shoot!", "¡No, no, no!"]
const FLEE_LINES := ["¡Vámonos!", "I'm getting out!", "¡Corre!", "He's the devil!"]
const VIEW := 200.0
const NEAR := 95.0
const FOV := deg_to_rad(70.0)

var kind := "pistolero"
var st := St.GUARD
var home := Vector2.ZERO
var home_facing := Vector2.DOWN
var patrol := PackedVector2Array()
var patrol_i := 0
var path := PackedVector2Array()
var path_i := 0
var wait := 0.0
var suspicion := 0.0
var last_known := Vector2.ZERO
var lost_t := 0.0
var look_t := 0.0
var react := 0.0
var shot_cd := 0.0
var wary := false
var running := false
var cover_pos := Vector2.INF
var sees_player := false
var known_corpses: Array[Enemy] = []
var desired := Vector2.DOWN
var repath_t := 0.0
var search_t := 0.0
var strafe_t := 0.0
var strafe_dir := 1.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var marker := ""
var marker_t := 0.0
var t := 0.0
var cone: VisionCone
# Personality: how quickly he reacts (multiplier) and how well he holds his nerve.
var reflex := 1.0
var nerve := 0.5
# Reactions are short cinematic beats that interrupt the fight: "point", "flinch",
# "cower", "dash" (for cover) and "hide". Each is held long enough to be noticed.
var reaction := ""
var reaction_t := 0.0
var hiding := false
var threat := Vector2.ZERO
var pending := ""
var pending_t := 0.0
var fear_cd := 0.0
var shaken := 0.0      # rises with every scare and every comrade lost
var retreat_dir := Vector2.ZERO
# Fighting position: a spot behind cover he ducks behind and pops up from.
var fight_pos := Vector2.INF
var at_cover := false
var fight_repick := 0.0
var duck_t := 0.0
var peek_t := 0.0
var aim_t := 0.0
var shout := ""
var shout_t := 0.0
var flank := 0.0
var flank_dir := Vector2.RIGHT
var sidestep_t := 0.0


func setup(g: Node, k: String, pos: Vector2, route: PackedVector2Array, facing_deg: float) -> void:
	setup_body(g, pos)
	kind = k
	var spec: Dictionary = KINDS[k]
	hp = spec["hp"]
	max_hp = hp
	weapon = Weapon.new(spec["weapon"], self)
	weapon.reserve = 999
	set_sheet(k)
	home = pos
	home_facing = Vector2.from_angle(deg_to_rad(facing_deg))
	facing = home_facing
	desired = facing
	patrol = route
	st = St.PATROL if patrol.size() > 1 else St.GUARD
	if st == St.PATROL:
		facing = (patrol[1] - patrol[0]).normalized()
		desired = facing
	t = randf() * 10.0
	reflex = randf_range(0.6, 1.8)
	nerve = 0.95 if k == "jefe" else randf_range(0.15, 0.9)
	cone = VisionCone.new()
	cone.enemy = self
	g.cone_layer.add_child(cone)


# ------------------------------------------------------------------ senses

func view_range() -> float:
	return VIEW * (1.2 if wary or st == St.COMBAT else 1.0)


func half_fov() -> float:
	return FOV * 0.5 * (1.4 if wary or st == St.COMBAT else 1.0)


func visibility_of(pos: Vector2, low: bool, check_near := true) -> float:
	var to := pos - global_position
	var dist := to.length()
	var rng := view_range()
	if dist > rng:
		return 0.0
	var close := dist < 22.0 and not low
	if not close and abs(facing.angle_to(to)) > half_fov():
		return 0.0
	if low and check_near and dist > NEAR and st != St.COMBAT:
		return 0.0
	if not game.line_of_sight(global_position, pos, low):
		return 0.0
	return clamp(1.0 - dist / rng, 0.15, 1.0)


func _perceive(delta: float) -> void:
	var p: Player = game.player
	var vis := 0.0
	if p.alive:
		vis = visibility_of(p.global_position, p.crouched)
	sees_player = vis > 0.0
	if st == St.COMBAT:
		if sees_player:
			last_known = p.global_position
			lost_t = 0.0
		else:
			lost_t += delta
		return
	if sees_player:
		var rate := 0.8 + 2.4 * vis
		if st == St.INVESTIGATE or wary:
			rate *= 1.6
		suspicion = min(1.0, suspicion + rate * delta)
		desired = (p.global_position - global_position).normalized()
		if suspicion >= 1.0:
			enter_combat(p.global_position, true, true)
			return
		if suspicion > 0.35 and st != St.INVESTIGATE:
			start_investigate(p.global_position, false)
	else:
		suspicion = max(0.0, suspicion - 0.15 * delta)
	for e in game.enemies:
		if not e.alive and e != self and not known_corpses.has(e):
			if visibility_of(e.global_position, true, false) > 0.0:
				known_corpses.append(e)
				_found_corpse(e)


func hear(pos: Vector2, radius: float, k: String, source: Node) -> void:
	if not alive or game.state != "play" or source == self:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	match k:
		"shot":
			if st == St.COMBAT:
				if not sees_player:
					last_known = pos
					lost_t = 0.0
			elif d < radius * 0.6:
				enter_combat(pos, false, true)
				queue_reaction(pos, false)
			else:
				suspicion = max(suspicion, 0.6)
				start_investigate(pos, true)
		"enemy_shot":
			if st != St.COMBAT and source is Enemy:
				enter_combat(source.last_known, false, false)
		"step":
			if st != St.COMBAT and st != St.INVESTIGATE:
				suspicion = min(0.9, suspicion + 0.3)
				desired = (pos - global_position).normalized()
				if suspicion > 0.5:
					start_investigate(pos, false)


func alert_to(pos: Vector2) -> void:
	if alive and st != St.COMBAT:
		enter_combat(pos, false, false)


func enter_combat(pos: Vector2, spotted: bool, propagate: bool) -> void:
	var was := st
	st = St.COMBAT
	last_known = pos
	lost_t = 0.0 if spotted else 2.0
	suspicion = 1.0
	react = (randf_range(0.5, 1.1) if spotted else randf_range(0.3, 0.7)) * reflex
	path = PackedVector2Array()
	cover_pos = Vector2.INF
	crouched = false
	if was != St.COMBAT:
		flank = game.next_flank()
		var from_target: Vector2 = global_position - game.player.global_position
		if from_target.length() < 1.0:
			from_target = Vector2.RIGHT
		flank_dir = from_target.normalized().rotated(flank)
		_mark("!")
		# Sometimes he stops to point the stranger out to the others, film-style.
		if spotted and propagate and randf() < 0.55:
			threat = pos
			start_reaction("point")
		game.on_enemy_alert(self, spotted)
		if propagate:
			game.alert_allies(self, 280.0, pos)


func start_investigate(pos: Vector2, run: bool) -> void:
	if st == St.COMBAT:
		return
	st = St.INVESTIGATE
	look_t = 0.0
	running = run
	_mark("?")
	path_to(pos)


func _found_corpse(e: Enemy) -> void:
	if st == St.COMBAT:
		return
	wary = true
	st = St.SEARCH
	search_t = 10.0
	last_known = e.global_position
	running = true
	path_to(e.global_position)
	_mark("!")
	for o in game.enemies:
		if o != self and o.alive and o.global_position.distance_to(global_position) < 220.0 and o.st != St.COMBAT:
			o.wary = true
			o.start_investigate(e.global_position, true)


func _mark(s: String) -> void:
	marker = s
	marker_t = 2.0


func _say(s: String) -> void:
	shout = s
	shout_t = 1.8


## A bullet cracked past or kicked up dirt near him.
func near_miss(from: Vector2) -> void:
	if not alive:
		return
	shaken = min(1.0, shaken + 0.15)
	_engage(from)
	queue_reaction(from, true)


## A comrade dropped near him: shakes him badly, and he always reacts.
func witness_death(at: Vector2, killer: Vector2) -> void:
	if not alive:
		return
	shaken = min(1.0, shaken + 0.35 * (1.0 - nerve * 0.5))
	_engage(killer)
	if reaction in ["flee", "cower"]:
		return
	fear_cd = 0.0
	pending = ""
	queue_reaction(killer, true, true)


func _engage(from: Vector2) -> void:
	if st != St.COMBAT:
		enter_combat(from, false, true)
	else:
		last_known = from
		lost_t = 0.0


## Fear grows as the fight goes badly: his nerve, minus how shaken he is.
func fear() -> float:
	return clamp(1.0 - nerve + shaken, 0.0, 1.0)


## Roll how he reacts to gunfire and start it after a short, personal delay so a
## group never reacts in unison.
func queue_reaction(from: Vector2, scary: bool, forced := false) -> void:
	if not alive or pending != "" or (fear_cd > 0.0 and not forced):
		return
	if reaction != "" and reaction != "point" and reaction != "backoff":
		return
	fear_cd = 2.0
	threat = from
	var r := _pick_reaction(scary, forced)
	if r == "":
		react += 0.4 * fear()
		return
	pending = r
	pending_t = randf_range(0.05, 0.45) * reflex


func _pick_reaction(scary: bool, forced: bool) -> String:
	var f := fear()
	var w := {
		"point": 0.15 if scary else 0.35,
		"flinch": (0.3 + 0.25 * f) if scary else 0.12,
		"cower": 0.7 * f * f * (1.0 if scary else 0.3),
		"dash": 0.45 * f + 0.1,
		"backoff": 0.35 if scary else 0.2,
		"flee": 0.6 * f * f * f * (1.5 if forced else 1.0),
		"": 0.0 if forced else 0.2 * (1.0 - f),
	}
	return _weighted(w)


func _weighted(w: Dictionary) -> String:
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return ""


func start_reaction(r: String) -> void:
	reaction = r
	hiding = false
	crouched = false
	path = PackedVector2Array()
	match r:
		"point":
			reaction_t = clamp(randf_range(1.8, 3.2) * reflex, 1.5, 5.0)
			_say(SPOT_LINES.pick_random())
		"flinch":
			reaction_t = randf_range(1.2, 2.0)
		"cower":
			reaction_t = randf_range(2.5, 4.5)
			_say(COWER_LINES.pick_random())
		"backoff":
			# step back out of the line of fire, gun still up, not shooting
			reaction_t = randf_range(2.0, 3.5)
			retreat_dir = ((global_position - threat).normalized() +
				(global_position - threat).orthogonal().normalized() * [-0.8, 0.8].pick_random()).normalized()
		"flee":
			reaction_t = randf_range(8.0, 12.0)
			path_to(game.point_away(global_position, threat, 220.0))
			_say(FLEE_LINES.pick_random())
		"dash", "hide":
			cover_pos = game.find_cover(global_position, threat)
			if cover_pos != Vector2.INF:
				path_to(cover_pos)
				reaction_t = 6.0   # give up if cover takes longer than this to reach
			else:
				reaction_t = randf_range(2.0, 3.0)   # nowhere to hide: back away
			if r == "dash":
				_say(SCARE_LINES.pick_random())
	if r == "point" or r == "cower":
		shout_t = reaction_t   # the line hangs for as long as he holds the pose
	if game._args.has("bot") or game._args.has("rattle"):
		print("%.1fs  %s #%d: %s for %.1fs (fear %.2f)" % [(Time.get_ticks_msec() - game.start_time) / 1000.0,
			kind, game.enemies.find(self), r, reaction_t, fear()])


func _do_reaction(delta: float) -> void:
	reaction_t -= delta
	velocity = Vector2.ZERO
	match reaction:
		"point":
			pose = "point"
			desired = (threat - global_position).normalized()
		"flinch":
			pose = "flinch"
			if reaction_t <= 0.0 and randf() < 0.3 + fear() * 0.5:
				start_reaction(_weighted({"backoff": 1.0, "dash": 1.0 + fear(), "flee": fear() * fear()}))
				return
		"cower":
			pose = "cower"
			if reaction_t <= 0.0:
				start_reaction("flee" if randf() < fear() * 0.6 else "hide")   # then off he goes
				return
		"backoff":
			velocity = retreat_dir * WALK
			desired = (threat - global_position).normalized()
		"flee":
			if follow_path(RUN * 1.15):
				crouched = true   # out of sight, catching his breath
				desired = (threat - global_position).normalized()
		"dash", "hide":
			if hiding:
				crouched = true
				desired = (threat - global_position).normalized()
			elif cover_pos == Vector2.INF:
				velocity = (global_position - threat).normalized() * RUN
			elif follow_path(RUN * (1.25 if reaction == "dash" else 0.9)):
				hiding = true
				crouched = true
				reaction_t = randf_range(2.0, 4.0)
	if reaction_t <= 0.0:
		reaction = ""
		hiding = false
		crouched = false
		cover_pos = Vector2.INF
		fight_pos = Vector2.INF
		react = max(react, 0.5 * reflex)


# ------------------------------------------------------------------ movement

func path_to(target: Vector2) -> void:
	path = game.find_path(global_position, target)
	path_i = 0
	repath_t = 0.6


## Returns true once the end of the path is reached.
func follow_path(speed: float) -> bool:
	while path_i < path.size() and global_position.distance_to(path[path_i]) < 4.0:
		path_i += 1
	if path_i >= path.size():
		velocity = Vector2.ZERO
		return true
	velocity = (path[path_i] - global_position).normalized() * speed
	return false


# ------------------------------------------------------------------ frame

func _physics_process(delta: float) -> void:
	t += delta
	if marker_t > 0.0:
		marker_t -= delta
	if not alive:
		cone.queue_redraw()
		if action_t > 0.0:
			update_anim(delta)
		return
	if game.state != "play" and game.state != "lost":
		velocity = Vector2.ZERO
		update_anim(delta)
		cone.refresh()
		return
	weapon.update(delta)
	fear_cd = max(0.0, fear_cd - delta)
	shaken = max(0.0, shaken - 0.02 * delta)
	shout_t = max(0.0, shout_t - delta)
	if game.state == "play":
		_perceive(delta)
	else:
		st = St.GUARD if st == St.COMBAT else st

	pose = ""
	if pending != "":
		pending_t -= delta
		if pending_t <= 0.0:
			start_reaction(pending)
			pending = ""
	if action == "hurt" and action_t > 0.0:
		velocity = Vector2.ZERO   # staggered by the hit
	elif reaction != "":
		_do_reaction(delta)
	else:
		_run_state(delta)
	if st != St.GUARD:
		_separate()
	var fleeing := (reaction in ["dash", "hide"] and not hiding) or (reaction == "flee" and path_i < path.size())
	if velocity.length() > 1.0 and (fleeing or not (st == St.COMBAT and sees_player)):
		desired = velocity.normalized()
	var turn := 4.5 if st == St.COMBAT else 2.0
	facing = facing.rotated(clamp(facing.angle_to(desired), -turn * delta, turn * delta))

	var before := global_position
	move_and_slide()
	_check_stuck(delta, before)
	update_anim(delta)
	cone.refresh()


func _run_state(delta: float) -> void:
	match st:
		St.GUARD:
			_guard(delta)
		St.PATROL:
			_patrol(delta)
		St.INVESTIGATE:
			_investigate(delta)
		St.COMBAT:
			_combat(delta)
		St.SEARCH:
			_search(delta)
		St.RETURN:
			if follow_path(WALK):
				st = St.PATROL if patrol.size() > 1 else St.GUARD


func _check_stuck(delta: float, before: Vector2) -> void:
	if velocity.length() > 10.0 and global_position.distance_to(before) < velocity.length() * delta * 0.25:
		stuck_t += delta
		if stuck_t > 0.6 and path.size() > 0:
			stuck_t = 0.0
			path_to(path[path.size() - 1])
	else:
		stuck_t = 0.0


func _guard(delta: float) -> void:
	if global_position.distance_to(home) > 6.0:
		if path.is_empty() or path_i >= path.size():
			path_to(home)
		follow_path(WALK)
		return
	velocity = Vector2.ZERO
	desired = home_facing.rotated(sin(t * 0.5) * 0.7)


func _patrol(delta: float) -> void:
	if wait > 0.0:
		wait -= delta
		velocity = Vector2.ZERO
		desired = facing.rotated(sin(t * 1.3) * 0.04)
		return
	if path.is_empty() or path_i >= path.size():
		if global_position.distance_to(patrol[patrol_i]) < 6.0:
			patrol_i = (patrol_i + 1) % patrol.size()
			wait = randf_range(1.0, 2.5)
			return
		path_to(patrol[patrol_i])
	follow_path(WALK)


func _investigate(delta: float) -> void:
	if not follow_path(RUN if running else WALK):
		return
	look_t += delta
	if int(look_t * 0.9) != int((look_t - delta) * 0.9):
		desired = Vector2.from_angle(randf() * TAU)
	if look_t > 4.0:
		suspicion = 0.0
		running = false
		wary = true
		st = St.RETURN
		path_to(patrol[patrol_i] if patrol.size() > 1 else home)


func _search(delta: float) -> void:
	search_t -= delta
	if search_t <= 0.0:
		running = false
		st = St.RETURN
		path_to(patrol[patrol_i] if patrol.size() > 1 else home)
		return
	if follow_path(RUN if running else WALK):
		running = false
		wait -= delta
		if wait <= 0.0:
			wait = randf_range(0.8, 1.8)
			desired = Vector2.from_angle(randf() * TAU)
			path_to(game.free_point_near(last_known, 80.0))


func _combat(delta: float) -> void:
	var p: Player = game.player
	if not p.alive:
		velocity = Vector2.ZERO
		return
	var to := p.global_position - global_position
	var dist := to.length()
	var spec: Dictionary = KINDS[kind]

	# Reloading: get behind cover and crouch.
	if weapon.is_reloading():
		if cover_pos != Vector2.INF and global_position.distance_to(cover_pos) > 5.0:
			if path.is_empty() or path_i >= path.size():
				path_to(cover_pos)
			follow_path(RUN)
		else:
			velocity = Vector2.ZERO
			crouched = cover_pos != Vector2.INF
		if sees_player:
			desired = to.normalized()
		return
	if weapon.needs_reload():
		if cover_pos == Vector2.INF:
			cover_pos = game.find_cover(global_position, p.global_position)
			if cover_pos != Vector2.INF:
				path_to(cover_pos)
		if cover_pos == Vector2.INF or global_position.distance_to(cover_pos) < 6.0 or (path_i >= path.size()):
			weapon.start_reload()
		else:
			follow_path(RUN)
		return
	crouched = false
	cover_pos = Vector2.INF

	if sees_player or (at_cover and fight_pos != Vector2.INF and lost_t < 4.0):
		_fight(delta, p, to, dist, spec)
	else:
		react = max(react, 0.3)
		fight_pos = Vector2.INF
		at_cover = false
		if lost_t > 9.0:
			st = St.SEARCH
			search_t = 10.0
			wary = true
			path_to(last_known)
			return
		# Converge on where he was last seen, but each from his own side.
		var goal: Vector2 = last_known + Vector2.from_angle(flank_dir.angle()) * 26.0 * abs(flank) / 1.2
		repath_t -= delta
		if repath_t <= 0.0 and (path.is_empty() or path[path.size() - 1].distance_to(goal) > 16.0):
			path_to(goal)
		if follow_path(RUN):
			look_t += delta
			if int(look_t * 1.2) != int((look_t - delta) * 1.2):
				desired = Vector2.from_angle(randf() * TAU)


## The firefight itself. He picks a fighting position: cover near his own flank
## slot that hides him crouched but lets him shoot standing, or the bare slot if
## there's none. He ducks behind cover and pops up to shoot, never fires on the
## move (bar a shotgunner up close), takes a moment to aim, and sidesteps instead
## of advancing.
func _fight(delta: float, p: Player, to: Vector2, dist: float, spec: Dictionary) -> void:
	desired = to.normalized()
	react -= delta
	shot_cd -= delta
	sidestep_t -= delta
	fight_repick -= delta
	var keep: Vector2 = spec["keep"]
	if fight_pos == Vector2.INF or fight_repick <= 0.0:
		_pick_fight_pos(p.global_position, keep)

	var close_shotgun := weapon.kind == "coach" and dist < keep.y
	if sidestep_t > 0.0:
		velocity = to.orthogonal().normalized() * strafe_dir * WALK
		crouched = false
		aim_t = 0.0
		return
	if global_position.distance_to(fight_pos) > 8.0:
		crouched = false
		aim_t = 0.0
		if path_i >= path.size():
			path_to(fight_pos)
		follow_path(RUN * 0.8)
		if not close_shotgun:
			return
	else:
		velocity = Vector2.ZERO
		if dist < keep.x * 0.8 and not at_cover:
			velocity = -to.normalized() * WALK   # too close: give ground

	if at_cover and velocity == Vector2.ZERO:
		if peek_t > 0.0:
			peek_t -= delta
			crouched = false
			if peek_t <= 0.0:
				duck_t = randf_range(1.2, 2.6) * (1.0 + fear())
		else:
			crouched = true
			aim_t = 0.0
			duck_t -= delta
			if duck_t <= 0.0:
				peek_t = randf_range(1.8, 3.0)
			return
	if not sees_player:
		return

	if velocity.length() < 1.0:
		aim_t += delta
	var aimed := aim_t >= 0.5 * reflex or (close_shotgun and dist < 70.0)
	var in_range: bool = dist < weapon.d["range"] * 0.85
	if react <= 0.0 and shot_cd <= 0.0 and in_range and aimed and abs(facing.angle_to(to)) < 0.2:
		if game.ally_in_line(self, global_position, p.global_position):
			_sidestep()   # a comrade is in the way: hold fire and step out of line
		elif weapon.can_fire():
			weapon.trigger()
			shot_cd = randf_range(spec["cadence"].x, spec["cadence"].y) * CADENCE_MULT
			if at_cover:
				if randf() < 0.5:
					peek_t = min(peek_t, 0.35)   # fire and duck
			elif randf() < 0.45:
				_sidestep()
		elif weapon.state == Weapon.S.READY:
			weapon.trigger()


func _pick_fight_pos(target: Vector2, keep: Vector2) -> void:
	fight_repick = randf_range(7.0, 12.0)
	var slot := target + flank_dir * (keep.x + keep.y) * 0.5
	var c: Vector2 = game.find_fighting_cover(global_position, target, slot, keep, game.taken_positions(self))
	at_cover = c != Vector2.INF
	if at_cover:
		fight_pos = c
	else:
		fight_pos = slot if game.is_free(slot) else game.free_point_near(slot, 30.0)
	path_to(fight_pos)
	duck_t = 0.0
	peek_t = 0.0


func _sidestep() -> void:
	sidestep_t = randf_range(0.6, 1.1)
	strafe_dir = [-1.0, 1.0].pick_random()
	fight_pos = Vector2.INF   # find a new spot once the step is done


## Push away from comrades who are too close, so they never move as a clump.
func _separate() -> void:
	var push := Vector2.ZERO
	for e in game.enemies:
		if e == self or not e.alive:
			continue
		var d: Vector2 = global_position - e.global_position
		var l: float = d.length()
		if l < 32.0 and l > 0.01:
			push += d / l * (32.0 - l) / 32.0
	if push != Vector2.ZERO:
		var speed: float = max(velocity.length(), WALK)
		velocity = (velocity + push * 40.0).limit_length(speed * 1.2)


func accuracy_mult() -> float:
	var m := AIM_SPREAD_SHOTGUN if weapon.kind == "coach" else AIM_SPREAD
	if velocity.length() > 5.0:
		m *= 1.6
	var p: Player = game.player
	if p.crouched:
		m *= 1.3
	return m


func on_hurt_alert(shooter: Actor) -> void:
	if alive and st != St.COMBAT:
		enter_combat(shooter.global_position, true, true)


func take_hit(dmg: int, from_dir: Vector2, shooter: Actor) -> void:
	super(dmg, from_dir, shooter)
	if alive:
		on_hurt_alert(shooter)
		shaken = min(1.0, shaken + 0.3)
		queue_reaction(shooter.global_position, true, true)
		if st == St.COMBAT:
			last_known = shooter.global_position
			lost_t = 0.0
