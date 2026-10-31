class_name Enemy
extends Actor
## Bandit AI: guard or patrol, grow suspicious of glimpses and noises, fight with a
## reaction delay and aim error, run to cover to reload, search when they lose you.

enum St { GUARD, PATROL, INVESTIGATE, COMBAT, SEARCH, RETURN, POSSE }

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
const COVER_ME_LINES := ["¡Cúbreme!", "Cover me!", "Keep him busy!", "I'm moving!"]
const FLANK_ROUND_LINES := ["¡Por atrás!", "I'll go round!", "Cut him off!", "¡Rodéenlo!"]
const FIRE_LINES := ["¡Fuego!", "Covering fire!", "Pin him down!", "¡Disparen!"]
const FLEE_LINES := ["¡Vámonos!", "I'm getting out!", "¡Corre!", "He's the devil!"]
const VIEW := 200.0
const NEAR := 95.0
const FOV := deg_to_rad(70.0)
const UNMASK := 40.0   # a concealed bandit only gives herself away to a hero this close
const LOCAL := 150.0   # within this, a fight is close enough to rattle him unseen

var kind := "pistolero"
var tdata: Dictionary     # his type, merged with defaults and placement overrides
var stats: Dictionary     # {"keep": preferred range, "cadence": pause between shots}
var loadout: Array = []   # guns he carries; the first in hand, the rest sidearms
var walk := WALK
var run := RUN
var sidearm_rolled := false
var hunt_target := Vector2.INF   # the last-seen spot his current hunting route is for
var hunt_role := ""               # "direct" or "flank"
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
var pending_forced := false
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
var since_shot := 99.0   # seconds since he last fired
var pinned_t := 0.0      # >0 while rounds are landing near him
# Suppressive fire: blazing away at where the stranger probably is.
var suppress_t := 0.0
var suppress_at := Vector2.ZERO
var covered_t := 0.0     # >0 while comrades cover his move
var hold_t := 0.0        # a beat after calling for cover, before breaking it
var cover_call_cd := 0.0
var blocked_t := 0.0
var single_shot := false   # suppression is a lone harassing shot
var blocked_steps := 0
var order_cd := 0.0
var panic_cd := 0.0
var panic := false
var rank := 0
var aiming := false      # set by whatever aimed him this frame; movement then doesn't turn him
var settled := false     # in place at his fighting position
var shout := ""
var shout_t := 0.0
var flank := 0.0
var flank_dir := Vector2.RIGHT
var sidestep_t := 0.0
var revealed := true     # false while a concealed type passes as one of the townsfolk
var in_posse := false    # one of the last few, riding the town together (see Posse)
var posse_slot := 0
var posse_repath := 0.0
var posse_wait := 0.0
var stride_in := 0.0     # how much a sidestep closes in on him as well (bold types)
var bold := 0.0          # 0..1: walks in shooting, shrugs off fire, scorns cover
var opportunist := 0.0   # 0..1: shoots while he isn't looking, wavers when he is
var sights_t := 0.0      # how long the stranger has had her in his sights
var waver_cd := 0.0
var runner_to := Vector2.INF   # the den door he's running to, to fetch the reserve
# Watching a corner: the stranger keeps peeking out of the same spot, so he holds his
# gun on it (see game.watch_post), ready, and shoots the moment he shows there.
const WATCH_MAX := 10.0    # s at most, then he moves again
const WATCH_CD := 8.0      # s before he'll settle to watch again
const WATCH_NEAR := 45.0   # px: the stranger shows this close to it and he's ready for him
const WATCH_LINES := ["Watch that corner!", "He'll be back out there...", "¡Ojo, la esquina!", "I got him covered."]
var watch_at := Vector2.INF
var watch_spot: Dictionary = {}
var watch_t := 0.0
var watch_cd := 0.0
var watch_look := 0.0
var ready_t := 0.0
const ALERT_OVER := 130.0   # px: in a fight, he sees a crouched man over low cover this close
# Breaking his cover: the stranger's gone to ground behind a crate (or barrel,
# trough...) they can see: a couple of them put rounds into it.
const BREAK_NEAR := 34.0    # px: last seen this close to it, he's behind it
const BREAK_LINES := ["Shoot through it!", "¡Tírenle a la caja!", "Splinter that crate!", "Flush him out!"]
var breaking: Dictionary = {}         # he was waiting for him: a moment where nothing pulls him off the shot


## Everything that makes this bandit who he is comes from his type in
## data/enemies.json (merged over the defaults, then any per-placement overrides).
func setup(g: Node, k: String, pos: Vector2, route: PackedVector2Array, facing_deg: float, overrides := {}) -> void:
	setup_body(g, pos)
	kind = k
	tdata = g.enemy_type(k, overrides)
	loadout = _pick_loadout()
	stats = {"keep": _v2(tdata["range"]), "cadence": _v2(tdata["cadence"])}
	hp = int(tdata["hp"])
	max_hp = hp
	weapon = Weapon.new(loadout[0], self)
	weapon.reserve = 999
	walk = WALK * float(tdata["speed"])
	run = RUN * float(tdata["speed"])
	var palettes: Array = tdata["palettes"]
	var pi_: int = int(tdata.get("palette", randi() % palettes.size())) % palettes.size()
	set_character(tdata["template"], palettes[pi_])
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
	reflex = randf_range(tdata["reflex"][0], tdata["reflex"][1])
	nerve = randf_range(tdata["nerve"][0], tdata["nerve"][1])
	rank = int(tdata["rank"])
	bold = float(tdata["bold"])
	opportunist = float(tdata["opportunist"])
	order_cd = randf_range(3.0, 6.0)
	cone = VisionCone.new()
	cone.enemy = self
	g.cone_layer.add_child(cone)
	if tdata["concealed"]:
		# looks like any other townsman: gun out of sight, no tell-tale view cone
		revealed = false
		anim_gun = "unarmed"
		cone.visible = false


## His guns: the type's loadout, or one of its weighted "loadouts" picked at random.
func _pick_loadout() -> Array:
	var options: Array = tdata.get("loadouts", [])
	if options.is_empty():
		return tdata["loadout"]
	var total := 0.0
	for o in options:
		total += float(o.get("weight", 1.0))
	var r := randf() * total
	var pick: Dictionary = options[-1]
	for o in options:
		r -= float(o.get("weight", 1.0))
		if r <= 0.0:
			pick = o
			break
	# an option can bring its own way of fighting (a sawn-off wants him close)
	for key in pick:
		if not key in ["guns", "weight"]:
			tdata[key] = pick[key]
	return pick["guns"]


## In the stranger's sights: he's looking her way down his barrel, or he's close.
func in_his_sights() -> bool:
	var p: Player = game.player
	if not p.alive:
		return false
	var to: Vector2 = global_position - p.global_position
	var d := to.length()
	if d > 260.0 or not game.line_of_sight(p.global_position, global_position, false):
		return false
	return d < 70.0 or abs(p.facing.angle_to(to)) < 0.35


## Drops the act: gun out, and from now on he's plainly one of them.
func reveal() -> void:
	if revealed:
		return
	revealed = true
	anim_gun = ""
	cone.visible = true
	set_ghost_tint(game.GHOST_THREAT)
	_log("reveals himself")


# ------------------------------------------------------------------ senses

func view_range() -> float:
	return VIEW * (1.2 if wary or st == St.COMBAT else 1.0)


func half_fov() -> float:
	return FOV * 0.5 * (1.4 if wary or st == St.COMBAT else 1.0)


func visibility_of(pos: Vector2, low: bool, check_near := true) -> float:
	var to := pos - global_position
	var dist := to.length()
	if low and st == St.COMBAT and dist < ALERT_OVER:
		low = false   # in a fight and this close, he's watching for a head over that crate
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
		vis = visibility_of(p.global_position, p.low_profile())
	sees_player = vis > 0.0
	if sees_player:
		game.report_sighting(p.global_position)
	if st == St.COMBAT:
		if sees_player:
			last_known = p.global_position
			lost_t = 0.0
		else:
			lost_t += delta
		return
	if not revealed:
		# Passing as townsfolk she never starts anything herself: no suspicion, no
		# looking into noises or bodies. Only a stranger walking right up to her makes
		# her draw (or the fight coming to her: comrades, gunfire, a snitch).
		if p.alive and global_position.distance_to(p.global_position) < UNMASK \
				and game.line_of_sight(global_position, p.global_position, false):
			enter_combat(p.global_position, true, true)
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
		if not e.alive and e != self and not known_corpses.has(e) and not e.has_meta("buried"):
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
		"shot", "struggle":   # gunfire, or a man yelling as the knife goes in
			if st == St.COMBAT:
				if not sees_player:
					last_known = pos
					lost_t = 0.0
			elif d < radius * 0.6:
				enter_combat(pos, false, true)
				queue_reaction(pos, false)
			elif not revealed:
				pass   # a distant shot: let someone else go and look
			else:
				suspicion = max(suspicion, 0.6)
				start_investigate(pos, true)
		"enemy_shot":
			if st != St.COMBAT and source is Enemy:
				enter_combat(source.last_known, false, false)
		"step":
			if not revealed:
				return   # footsteps are no business of a townsman's
			if st != St.COMBAT and st != St.INVESTIGATE:
				suspicion = min(0.9, suspicion + 0.3)
				desired = (pos - global_position).normalized()
				if suspicion > 0.5:
					start_investigate(pos, false)


func alert_to(pos: Vector2) -> void:
	if alive and st != St.COMBAT:
		enter_combat(pos, false, false)


func enter_combat(pos: Vector2, spotted: bool, propagate: bool) -> void:
	reveal()
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
	reveal()
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
	shaken = min(1.0, shaken + 0.15 * (1.0 - bold * 0.6))
	pinned_t = 2.5 * (1.0 - bold * 0.7)
	_engage(from)
	queue_reaction(from, true)


## A comrade dropped near him: if he saw it, it shakes him badly and he always
## reacts. Out of sight it only tells him where the fight is.
func witness_death(at: Vector2, killer: Vector2) -> void:
	if not alive:
		return
	if not game.line_of_sight(global_position, at, false):
		_engage(killer)
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


## Close enough to the shooting to be rattled by it: he can see where it's coming
## from, or it's right on top of him.
func near_action(from: Vector2) -> bool:
	if sees_player:
		return true
	var d := global_position.distance_to(from)
	return d < LOCAL * 0.5 or (d < LOCAL * 2.0 and game.line_of_sight(global_position, from, false))


## Fear grows as the fight goes badly: his nerve, minus how shaken he is.
func fear() -> float:
	return clamp(1.0 - nerve + shaken, 0.0, 1.0)


## Roll how he reacts to gunfire and start it after a short, personal delay so a
## group never reacts in unison.
func queue_reaction(from: Vector2, scary: bool, forced := false) -> void:
	if not alive or pending != "" or (fear_cd > 0.0 and not forced):
		return
	if not forced and not near_action(from):
		return   # a fight he can't see, off down the street: he just heads for it
	if reaction != "" and reaction != "point" and reaction != "backoff":
		return
	fear_cd = 2.0
	threat = from
	var r := _pick_reaction(scary, forced)
	if r == "":
		react += 0.4 * fear()
		return
	pending = r
	pending_forced = forced
	pending_t = randf_range(0.05, 0.45) * reflex


func _pick_reaction(scary: bool, forced: bool) -> String:
	var f := fear()
	var timid := 1.0 - bold * 0.75   # a bold man rarely gives ground or ducks
	var w := {
		"point": 0.15 if scary else 0.35,
		"flinch": ((0.3 + 0.25 * f) if scary else 0.12) * timid,
		"cower": 0.7 * f * f * (1.0 if scary else 0.3) * timid,
		"dash": (0.45 * f + 0.1) * timid,
		"backoff": (0.35 if scary else 0.2) * timid,
		"flee": 0.6 * f * f * f * (1.5 if forced else 1.0) * timid,
		"": (0.6 * bold if forced else 0.2 * (1.0 - f) + 0.8 * bold),
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
	suppress_t = 0.0
	hold_t = 0.0
	hiding = false
	crouched = false
	path = PackedVector2Array()
	match r:
		"point":
			reaction_t = clamp(randf_range(1.8, 3.2) * reflex, 1.5, 5.0)
			_say(_line("spot", SPOT_LINES))
		"flinch":
			reaction_t = randf_range(1.2, 2.0)
		"cower":
			reaction_t = randf_range(2.5, 4.5)
			_say(_line("cower", COWER_LINES))
		"backoff":
			# step back out of the line of fire, gun still up, not shooting
			reaction_t = randf_range(2.0, 3.5)
			retreat_dir = ((global_position - threat).normalized() +
				(global_position - threat).orthogonal().normalized() * [-0.8, 0.8].pick_random()).normalized()
		"flee":
			reaction_t = randf_range(8.0, 12.0)
			path_to(game.point_away(global_position, threat, 220.0))
			_say(_line("flee", FLEE_LINES))
		"dash", "hide":
			cover_pos = game.find_cover(global_position, threat)
			if cover_pos != Vector2.INF:
				path_to(cover_pos)
				reaction_t = 6.0   # give up if cover takes longer than this to reach
			else:
				reaction_t = randf_range(2.0, 3.0)   # nowhere to hide: back away
			if r == "dash":
				_say(_line("scare", SCARE_LINES))
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
			velocity = retreat_dir * walk
			desired = (threat - global_position).normalized()
		"flee":
			if follow_path(run * 1.15):
				crouched = true   # out of sight, catching his breath
				desired = (threat - global_position).normalized()
		"dash", "hide":
			if hiding:
				crouched = true
				desired = (threat - global_position).normalized()
			elif cover_pos == Vector2.INF:
				velocity = (global_position - threat).normalized() * run
			elif follow_path(run * (1.25 if reaction == "dash" else 0.9)):
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
		if dying():
			update_anim(delta)
		return
	if game.state != "play" and game.state != "lost":
		velocity = Vector2.ZERO
		update_anim(delta)
		cone.refresh()
		return
	weapon.update(delta)
	fear_cd = max(0.0, fear_cd - delta)
	since_shot += delta
	pinned_t -= delta
	covered_t -= delta
	cover_call_cd -= delta
	order_cd -= delta
	panic_cd -= delta
	shaken = max(0.0, shaken - 0.02 * delta)
	shout_t = max(0.0, shout_t - delta)
	if game.state == "play":
		_perceive(delta)
	else:
		st = St.GUARD if st == St.COMBAT else st

	pose = ""
	aiming = false
	if not revealed and st in [St.INVESTIGATE, St.COMBAT, St.SEARCH]:
		reveal()   # something's up: the act is over
	if pending != "":
		pending_t -= delta
		if pending_t <= 0.0:
			# by now he may have moved on, out of sight of it
			if pending_forced or near_action(threat):
				if not pending_forced and not sees_player and global_position.distance_to(threat) > LOCAL \
						and not game.line_of_sight(global_position, threat, false):
					_log("reacts out of sight")   # (kept for the tests: should never happen)
				start_reaction(pending)
			pending = ""
	if is_staggered():
		velocity = Vector2.ZERO   # reeling from the hit
	elif reaction != "":
		_do_reaction(delta)
		_panic_fire()
	else:
		_run_state(delta)
		if st == St.COMBAT:
			_leader_orders()
	velocity *= limp_factor()
	var own_velocity := velocity
	if st != St.GUARD:
		_separate()
	var fleeing := (reaction in ["dash", "hide"] and not hiding) or (reaction == "flee" and path_i < path.size())
	if own_velocity.length() > 1.0 and (fleeing or not (aiming or (st == St.COMBAT and sees_player))):
		desired = own_velocity.normalized()
	var turn := 4.5 if st == St.COMBAT else 2.0
	facing = facing.rotated(clamp(facing.angle_to(desired), -turn * delta, turn * delta))

	var before := global_position
	move_and_slide()
	_check_stuck(delta, before)
	update_anim(delta)
	cone.refresh()


func _run_state(delta: float) -> void:
	if runner_to != Vector2.INF:
		_run_for_help(delta)
		return
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
			if follow_path(walk):
				st = St.PATROL if patrol.size() > 1 else St.GUARD
		St.POSSE:
			_posse(delta)


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
		follow_path(walk)
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
	follow_path(walk)


func _investigate(delta: float) -> void:
	if not follow_path(run if running else walk):
		return
	look_t += delta
	if int(look_t * 0.9) != int((look_t - delta) * 0.9):
		desired = Vector2.from_angle(randf() * TAU)
	if look_t > 4.0:
		suspicion = 0.0
		running = false
		wary = true
		_go_back()


func _search(delta: float) -> void:
	search_t -= delta
	if search_t <= 0.0:
		running = false
		_go_back()
		return
	if follow_path(run if running else walk):
		running = false
		wait -= delta
		if wait <= 0.0:
			wait = randf_range(0.8, 1.8)
			desired = Vector2.from_angle(randf() * TAU)
			path_to(game.free_point_near(last_known, 80.0))


## Done looking: back to his post, or back in with the posse.
func _go_back() -> void:
	if in_posse:
		st = St.POSSE
		path = PackedVector2Array()
		return
	st = St.RETURN
	path_to(patrol[patrol_i] if patrol.size() > 1 else home)


## Called when the posse forms. A man in a fight or a search finishes it first.
func join_posse(slot: int) -> void:
	reveal()
	in_posse = true
	posse_slot = slot
	wary = true
	for e in game.enemies:
		if not e.alive and not known_corpses.has(e):
			known_corpses.append(e)   # they all know who's down by now
	if st in [St.GUARD, St.PATROL, St.RETURN, St.INVESTIGATE]:
		st = St.POSSE
		path = PackedVector2Array()
		suspicion = 0.0


## Riding with the posse: the leader picks the way, the others keep their slots
## around him and each watches his own side whenever they stop.
func _posse(delta: float) -> void:
	var p: Posse = game.posse
	if p.leader == self:
		_lead_posse(delta, p)
		return
	var slot := p.slot_of(self)
	var d := global_position.distance_to(slot)
	if d < 10.0:
		velocity = Vector2.ZERO
		path = PackedVector2Array()
		desired = p.watch_of(self)
		return
	posse_repath -= delta
	if posse_repath <= 0.0 or path_i >= path.size():
		posse_repath = 0.8
		var to_him := global_position.distance_to(p.leader.global_position)
		path_to(p.leader.global_position if to_him > Posse.LAG else slot)   # far behind: make for him first
	follow_path(run if d > 90.0 else walk * 1.15)


func _lead_posse(delta: float, p: Posse) -> void:
	if p.gathering or p.lagging() or posse_wait > 0.0:
		posse_wait -= delta
		velocity = Vector2.ZERO
		desired = facing.rotated(sin(t * 0.6) * 0.8)   # looking about while they close up
		return
	if path.is_empty() or path_i >= path.size():
		if p.goal >= 0:
			p.reached()
			posse_wait = randf_range(1.5, 3.0)
			return
		path_to(p.next_point(global_position))
	follow_path(walk)


## Not on to the stranger: no fight, no eyes on him. He can be taken from behind.
func unaware() -> bool:
	return alive and st != St.COMBAT and not sees_player and reaction != "point"


## Could he shoot a man rushing him with a knife, right now? Only with a loaded gun
## in his hand, ready, facing him, and his wits about him.
func can_fire_at(p: Actor) -> bool:
	if not alive or not revealed or is_staggered() or weapon.is_reloading() or not weapon.can_fire():
		return false
	if reaction in ["cower", "flee", "dash", "hide"]:
		return false
	return absf(facing.angle_to(p.global_position - global_position)) < 1.1


## A knife rushes him and he's ready: he turns the gun on him point-blank.
func point_blank(p: Actor) -> void:
	facing = (p.global_position - global_position).normalized()
	desired = facing
	weapon.trigger()
	_log("shoots the knife-man point-blank")


## Off to fetch the reserve from the den: he runs for its door, shouting, and
## doesn't stop to shoot.
func run_for_help(door: Vector2) -> void:
	reveal()
	runner_to = door
	path_to(door)
	_say(_line("help", ["¡Al saloon! ¡Refuerzos!", "¡Muchachos! ¡Ayuda!", "Get the boys!"]))
	_log("runs for help")


func _run_for_help(delta: float) -> void:
	repath_t -= delta
	if repath_t <= 0.0:
		path_to(runner_to)
	crouched = false
	if follow_path(run) or global_position.distance_to(runner_to) < 16.0:
		game.rally("runner")
		runner_to = Vector2.INF
		if st != St.COMBAT:
			enter_combat(game.seen_pos, false, false)


func say_line(key: String, stock: Array) -> void:
	_say(_line(key, stock))


func _combat(delta: float) -> void:
	var p: Player = game.player
	if not p.alive:
		velocity = Vector2.ZERO
		return
	var to := p.global_position - global_position
	var dist := to.length()
	var spec: Dictionary = stats

	# Reloading: get behind cover and crouch. A bold man with a pair of guns comes
	# back out as soon as one of them is full.
	if weapon.is_reloading():
		if bold > 0.0 and sees_player and weapon.d.get("twin", false) and weapon.loaded() >= 6:
			weapon.stop_requested = true
		if cover_pos != Vector2.INF and global_position.distance_to(cover_pos) > 5.0:
			if path.is_empty() or path_i >= path.size():
				path_to(cover_pos)
			follow_path(run)
		else:
			velocity = Vector2.ZERO
			crouched = cover_pos != Vector2.INF
		if sees_player:
			desired = to.normalized()
		return
	if not weapon.needs_reload():
		sidearm_rolled = false
	elif not sidearm_rolled:
		sidearm_rolled = true
		if loadout.size() > 1 and weapon.kind == loadout[0] and randf() < float(tdata["draw_sidearm"]):
			_draw_sidearm()
			return
	if weapon.needs_reload():
		if cover_pos == Vector2.INF:
			cover_pos = game.find_cover(global_position, p.global_position)
			if cover_pos != Vector2.INF:
				path_to(cover_pos)
		if cover_pos == Vector2.INF or global_position.distance_to(cover_pos) < 6.0 or (path_i >= path.size()):
			weapon.start_reload()
		else:
			follow_path(run)
		return
	crouched = false
	cover_pos = Vector2.INF

	if opportunist > 0.0 and _waver(delta):
		return
	if _watch(delta, p):
		return   # his gun's on that corner; covering fire is for the others
	if suppress_t > 0.0 and ready_t <= 0.0:
		_suppress(delta, spec)
		return
	breaking = {}
	if not sees_player and _break_cover():
		return
	if sees_player or (at_cover and fight_pos != Vector2.INF and lost_t < 4.0):
		hunt_target = Vector2.INF   # a fresh hunt once he's lost again
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
		# Hunt him down where he was last seen: straight there, or round the other
		# way to cut him off, depending on what his comrades are already doing.
		if hunt_target == Vector2.INF or hunt_target.distance_to(last_known) > 40.0:
			var plan: Dictionary = game.plan_hunt(self, last_known)
			path = plan["path"]
			path_i = 0
			repath_t = 3.0
			hunt_target = last_known
			hunt_role = plan["role"]
			if hunt_role == "flank":
				_log("flanks")
				if shout_t <= 0.0 and randf() < 0.6:
					_say(_line("flank", FLANK_ROUND_LINES))
		if follow_path(run):
			look_t += delta
			if int(look_t * 1.2) != int((look_t - delta) * 1.2):
				desired = Vector2.from_angle(randf() * TAU)


## Keeping his gun on the corner the stranger keeps coming out of. Only a couple of
## them do, and not for long: the rest keep closing in. True while he's watching.
func _watch(delta: float, p: Player) -> bool:
	watch_cd -= delta
	if watch_at == Vector2.INF:
		if sees_player or watch_cd > 0.0 or lost_t < 0.5:
			return false
		watch_look -= delta
		if watch_look > 0.0:
			return false
		watch_look = 0.5
		var post: Dictionary = game.watch_post(self)
		if post.is_empty():
			return false
		watch_at = post["at"]
		watch_spot = post["spot"]
		watch_t = 0.0
		suppress_t = 0.0   # he holds his fire for the corner now
		breaking = {}
		_log("watches a corner")
		if shout_t <= 0.0 and randf() < 0.5:
			_say(_line("watch", WATCH_LINES))
	if sees_player:
		if p.global_position.distance_to(watch_at) < WATCH_NEAR:
			# there he is, right where he was waiting for him
			react = minf(react, 0.08)
			aim_t = maxf(aim_t, 0.35 * reflex)
			suppress_t = 0.0   # no more blind covering fire: he's got him
			ready_t = 0.6
			fight_pos = global_position   # he shoots from where he stands
			settled = true
			fight_repick = 2.0
			shot_cd = minf(shot_cd, 0.0)
			_log("was ready for him")
		_stop_watching(WATCH_CD * 0.5)
		return false
	watch_t += delta
	if watch_t > WATCH_MAX or not game.spot_hot(watch_spot):
		_stop_watching(WATCH_CD)
		return false
	velocity = Vector2.ZERO
	crouched = false   # up and ready, not ducking
	aiming = true
	desired = (watch_at - global_position).normalized()
	return true


## He's behind that crate: shoot the crate. Covering fire aimed at the boards.
func _break_cover() -> bool:
	if lost_t < 0.3 or game.staleness() > game.FRESH * 0.5:
		return false
	var prop: Dictionary = game.cover_to_break(self, last_known)
	if prop.is_empty() or not suppress(game.prop_centre(prop), 4.0):
		return false
	suppress_at = game.prop_centre(prop)   # dead on the boards, not about the spot
	breaking = prop
	_log("shoots the cover")
	if shout_t <= 0.0 and randf() < 0.4:
		_say(_line("break", BREAK_LINES))
	return true


func _stop_watching(cd: float) -> void:
	watch_at = Vector2.INF
	watch_spot = {}
	watch_cd = cd


## The firefight itself. He picks a fighting position: cover near his own flank
## slot that hides him crouched but lets him shoot standing, or the bare slot if
## there's none. He ducks behind cover and pops up to shoot, never fires on the
## move (bar a shotgunner up close), takes a moment to aim, and sidesteps instead
## of advancing.
func _fight(delta: float, p: Player, to: Vector2, dist: float, spec: Dictionary) -> void:
	desired = to.normalized()
	aiming = true
	react -= delta
	shot_cd -= delta
	sidestep_t -= delta
	fight_repick -= delta
	var keep: Vector2 = spec["keep"]
	if fight_pos == Vector2.INF or fight_repick <= 0.0:
		_pick_fight_pos(p.global_position, keep)
	elif global_position.distance_to(fight_pos) <= 10.0:
		settled = true

	# Shotgunners up close, and bold men at any fighting range, shoot on the move.
	var fires_moving: bool = tdata["fires_on_move"] and dist < keep.y
	# Not pinned down and silent for a while: stop whatever he's doing and shoot.
	var must_fire: bool = sees_player and pinned_t <= 0.0 and since_shot > 1.6 and react <= 0.0 \
		and not (opportunist > 0.0 and sights_t > 0.0) \
		and dist < weapon.d["range"] * 0.85 and weapon.can_fire() \
		and not game.ally_in_line(self, global_position, p.global_position)
	var ready := ready_t > 0.0
	if ready:
		ready_t -= delta   # waiting for him at that corner: no moving, no ducking
		velocity = Vector2.ZERO
		crouched = false
	elif hold_t > 0.0:
		hold_t -= delta
		velocity = Vector2.ZERO
		return
	elif must_fire and sidestep_t <= 0.0 and covered_t <= 0.0:
		velocity = Vector2.ZERO
		crouched = false
		peek_t = max(peek_t, 0.6)
	elif sidestep_t > 0.0:
		velocity = (to.orthogonal().normalized() * strafe_dir + to.normalized() * stride_in).normalized() \
			* walk * (1.0 + 0.3 * bold)
		crouched = false
		aim_t = 0.0
		if not (fires_moving and bold > 0.0):
			return
	elif global_position.distance_to(fight_pos) > (18.0 if settled else 8.0):
		# once in place he tolerates being jostled a little before walking back
		crouched = false
		aim_t = 0.0
		if path_i >= path.size():
			path_to(fight_pos)
		follow_path(run if covered_t > 0.0 else run * 0.8)
		if not fires_moving:
			return
	else:
		velocity = Vector2.ZERO
		if dist < keep.x * 0.8 and not at_cover and since_shot < 1.2 and bold < 0.5:
			velocity = -to.normalized() * walk   # too close: fire, then give ground

	if at_cover and velocity == Vector2.ZERO and not ready:
		if peek_t > 0.0:
			peek_t -= delta
			crouched = false
			if peek_t <= 0.0:
				# pinned down he stays low; otherwise he's soon back up shooting
				duck_t = randf_range(1.2, 2.6) * (1.0 + fear()) if pinned_t > 0.0 else randf_range(0.5, 1.0)
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
	# an opportunist the stranger isn't watching wastes no time lining up
	var quick := 0.55 if opportunist > 0.0 and sights_t <= 0.0 else 1.0
	var aimed := aim_t >= 0.35 * reflex * quick or (fires_moving and dist < 70.0 + 70.0 * bold)
	var in_range: bool = dist < weapon.d["range"] * 0.85
	if react <= 0.0 and shot_cd <= 0.0 and in_range and aimed and abs(facing.angle_to(to)) < 0.2:
		if game.ally_in_line(self, global_position, p.global_position):
			blocked_steps += 1
			if blocked_steps >= 2:
				# still blocked after stepping aside: work round to a new spot
				blocked_steps = 0
				flank_dir = flank_dir.rotated([-0.6, 0.6].pick_random())
				fight_pos = Vector2.INF
			else:
				_sidestep(game.blocking_ally(self, global_position, p.global_position))
		elif weapon.can_fire():
			weapon.trigger()
			since_shot = 0.0
			blocked_steps = 0
			shot_cd = randf_range(spec["cadence"].x, spec["cadence"].y) * CADENCE_MULT
			if weapon.d.get("twin", false) and weapon.hand == 0 and randf() < 0.75:
				shot_cd = randf_range(0.2, 0.35)   # the left gun follows the right: bang-bang
			if at_cover:
				if randf() < 0.5:
					peek_t = min(peek_t, 0.35)   # fire and duck
			elif randf() < 0.45 + 0.35 * bold:
				_sidestep()
		elif weapon.state == Weapon.S.READY:
			weapon.trigger()


## An opportunist turns his gun her way (or comes close) and she loses her nerve:
## backs off, ducks for cover or flinches. Not every time, and not again at once.
func _waver(delta: float) -> bool:
	waver_cd -= delta
	if in_his_sights():
		sights_t += delta
	else:
		sights_t = 0.0
	if sights_t < 0.25 * reflex or waver_cd > 0.0:
		return false
	waver_cd = randf_range(3.0, 5.0)
	if randf() > opportunist:
		return false
	threat = game.player.global_position
	start_reaction(_weighted({"backoff": 1.0, "hide": 1.0, "flinch": 0.4}))
	_log("wavers")
	return true


func _pick_fight_pos(target: Vector2, keep: Vector2) -> void:
	fight_repick = randf_range(6.0, 10.0)
	# never further off than his own gun reaches (a derringer doesn't carry far)
	var reach: float = weapon.d["range"] * 0.8
	var slot := target + flank_dir * minf(lerpf((keep.x + keep.y) * 0.5, keep.x, bold), reach)
	var c: Vector2 = game.find_fighting_cover(global_position, target, slot, keep, game.taken_positions(self))
	if c != Vector2.INF and c.distance_to(target) > reach:
		c = Vector2.INF
	if c != Vector2.INF and (randf() < bold * 0.6 or (bold > 0.0 and c.distance_to(target) > keep.y)):
		c = Vector2.INF   # scorns cover, or won't hang back for it: he'll shoot it out in the open
	if settled and fight_pos != Vector2.INF and c != Vector2.INF and c.distance_to(fight_pos) < 24.0 and randf() < 0.6:
		# same spot again: work round the flank instead of sitting tight
		flank_dir = flank_dir.rotated([-0.6, 0.6].pick_random())
		slot = target + flank_dir * minf((keep.x + keep.y) * 0.5, reach)
		c = game.find_fighting_cover(global_position, target, slot, keep, game.taken_positions(self))
		if c != Vector2.INF and c.distance_to(target) > reach:
			c = Vector2.INF
	settled = false
	at_cover = c != Vector2.INF
	if at_cover:
		fight_pos = c
	else:
		fight_pos = slot if game.is_free(slot) else game.free_point_near(slot, 30.0)
	path_to(fight_pos)
	if global_position.distance_to(fight_pos) > 40.0 and lost_t < 2.0:
		_call_for_cover()
	duck_t = 0.0
	peek_t = 0.0


## Step sideways: away from the comrade in the way, if that's the reason.
func _sidestep(away_from: Actor = null) -> void:
	sidestep_t = randf_range(0.6, 1.1) * (1.0 + bold)
	strafe_dir = [-1.0, 1.0].pick_random()
	# a bold man closes in as he goes, down to the near end of his range
	var dist: float = global_position.distance_to(game.player.global_position)
	stride_in = bold * 0.8 if dist > stats["keep"].x else 0.0
	if away_from:
		var perp: Vector2 = (game.player.global_position - global_position).orthogonal()
		strafe_dir = 1.0 if (global_position - away_from.global_position).dot(perp) >= 0.0 else -1.0


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
		var speed: float = max(velocity.length(), walk)
		velocity = (velocity + push * 40.0).limit_length(speed * 1.2)


## Blaze away at where the stranger probably is, seen or not: faster than aimed
## fire and looser, standing up out of cover to do it.
func _suppress(delta: float, spec: Dictionary) -> void:
	suppress_t -= delta
	shot_cd -= delta
	velocity = Vector2.ZERO
	crouched = false
	var aim_at := suppress_at
	if sees_player:
		aim_at = game.player.global_position
	desired = (aim_at - global_position).normalized()
	aiming = true
	if weapon.needs_reload():
		suppress_t = 0.0
		return
	if not single_shot and game.staleness() > game.FRESH * 0.5 and not sees_player:
		suppress_t = 0.0   # nobody's seen him for a few seconds: cease fire
		return
	if single_shot and game.staleness() > game.HARASS_UNTIL:
		suppress_t = 0.0   # too late now
		return
	if shot_cd <= 0.0 and abs(facing.angle_to(desired)) < 0.25:
		if game.ally_in_line(self, global_position, aim_at):
			velocity = desired.orthogonal() * strafe_dir * walk   # step clear of him
			blocked_t += delta
			if blocked_t > 1.0:
				# still blocked: give up suppressing and fight normally
				suppress_t = 0.0
				blocked_t = 0.0
			return
		blocked_t = 0.0
		if not game.line_of_sight(global_position, aim_at, false):
			suppress_t = 0.0   # lost his view of the spot: no use shooting the wall
			return
		if weapon.can_fire():
			weapon.trigger()
			since_shot = 0.0
			# suppressing a place he can't see, he slows as the sighting ages
			var taper: float = 1.0 if sees_player else 1.0 + game.staleness() * 0.8
			# (never faster than a steady rhythm, however quick his hands)
			shot_cd = max(randf_range(spec["cadence"].x, spec["cadence"].y) * 0.7, 0.45) * taper
			if single_shot:
				suppress_t = 0.0
		elif weapon.state == Weapon.S.READY:
			weapon.trigger()


## Ordered (or asked) to keep the stranger's head down. Only a man with a view of
## the spot answers (nobody blazes away at a wall); returns whether he does.
func suppress(at: Vector2, seconds: float) -> bool:
	if not alive or reaction != "" or weapon.is_reloading() or st != St.COMBAT:
		return false
	if game.staleness() > game.FRESH:
		return false   # nobody has seen him for a while: no reason to blaze away
	if global_position.distance_to(at) > weapon.d["range"] * 0.8 or not game.line_of_sight(global_position, at, false):
		return false
	single_shot = false
	breaking = {}   # (whoever wants it shot at, it's not his own crate-breaking now)
	suppress_t = seconds
	suppress_at = at + Vector2(randf_range(-14, 14), randf_range(-8, 8))
	shot_cd = randf_range(0.0, 0.5)
	return true


## One unaimed shot at where the stranger was last seen, to keep him honest
## (the game only asks bandits with a view of the spot).
func harass(at: Vector2) -> void:
	if not alive or reaction != "" or suppress_t > 0.0:
		return
	suppress_t = 2.0
	suppress_at = at + Vector2(randf_range(-20, 20), randf_range(-10, 10))
	shot_cd = 0.0
	single_shot = true
	_log("harassing shot")


## About to break cover: ask the comrades in cover nearby to lay down fire.
## Leaders always do; the others only sometimes think of it.
func _call_for_cover() -> void:
	if cover_call_cd > 0.0 or randf() > float(tdata["cover_call"]) or game.staleness() > game.FRESH:
		return
	var helpers: Array[Enemy] = []
	for e in game.enemies:
		# the ones holding a position (in cover or standing their ground) with a view
		# of the stranger's spot answer
		if e != self and e.alive and e.st == St.COMBAT and e.reaction == "" and e.suppress_t <= 0.0 \
				and (e.settled or e.velocity.length() < 5.0) and not e.weapon.is_reloading() \
				and e.global_position.distance_to(global_position) < 240.0 \
				and game.line_of_sight(e.global_position, last_known, false):
			helpers.append(e)
	if helpers.is_empty():
		return
	cover_call_cd = 8.0
	_say(_line("cover_me", COVER_ME_LINES))
	for h in helpers:
		h.suppress(last_known, randf_range(2.5, 3.5))
	hold_t = 0.4
	covered_t = 3.0
	_log("calls for cover, %d answer" % helpers.size())


## A leader seeing the fight stall (the stranger gone to ground) or a man in
## trouble (fleeing, cowering, reloading) orders covering fire on the stranger's
## likely position, then moves up himself while they shoot.
func _leader_orders() -> void:
	if rank == 0 or order_cd > 0.0 or reaction != "" or suppress_t > 0.0:
		return
	if game.staleness() > game.FRESH:
		return   # nothing to shoot at any more
	var stalled := not sees_player and lost_t > 1.2
	var trouble := false
	var men: Array[Enemy] = []
	for e in game.enemies:
		if e == self or not e.alive or e.global_position.distance_to(global_position) > 320.0:
			continue
		if e.reaction in ["flee", "dash", "cower", "hide"] or e.weapon.is_reloading():
			trouble = true
		elif e.st == St.COMBAT and game.line_of_sight(e.global_position, last_known, false):
			men.append(e)   # only the ones who can see where he is can shoot at it
	if not (stalled or trouble) or men.is_empty():
		return
	order_cd = randf_range(9.0, 14.0)
	_say(_line("fire", FIRE_LINES))
	for e in men:
		e.suppress(last_known, randf_range(3.0, 4.5))
	if randf() < 0.5:
		fight_pos = Vector2.INF   # he uses the cover to move up...
		covered_t = 3.5
	elif not suppress(last_known, randf_range(3.0, 4.5)):   # ...or leads the shooting
		fight_pos = Vector2.INF   # (no view from here: he moves up anyway)
		covered_t = 3.5
	_log("orders covering fire, %d answer" % men.size())


## Running for it, he may still loose off a wild shot over his shoulder.
func _panic_fire() -> void:
	if panic_cd > 0.0 or not (reaction in ["flee", "dash", "backoff"] or (reaction == "hide" and not hiding)):
		return
	panic_cd = randf_range(0.8, 1.8)
	if randf() > 0.55 or not weapon.can_fire() or game.player == null or not game.player.alive:
		return
	if game.staleness() > game.FRESH or not game.line_of_sight(global_position, threat, false):
		return   # nothing chasing him that he knows of, or nothing to shoot back at
	var run_facing := facing
	facing = (threat - global_position).normalized()
	panic = true
	weapon.trigger()
	panic = false
	since_shot = 0.0
	if reaction != "backoff":
		facing = run_facing
	_log("panic shot")


const RELOAD_LINES := ["¡Recargando!", "Reloading!", "Cover me, I'm loading!"]


## He's out and loading: everyone should know (the stranger included).
func on_reload() -> void:
	if randf() < 0.6 and shout_t <= 0.0:
		_say(_line("reload", RELOAD_LINES))


## The long gun is empty and there's no time: he throws it down and draws.
func _draw_sidearm() -> void:
	game.drop_gun(self)
	weapon = Weapon.new(loadout[1], self)
	weapon.reserve = 999
	hold_t = 0.45
	game.sfx("close", global_position, -6.0)
	if shout_t <= 0.0 and randf() < 0.5:
		_say(_line("sidearm", ["To hell with it!", "¡Al diablo!"]))
	_log("draws his " + weapon.kind)


## A shouted line: his type's own if it has them, else the stock ones.
func _line(key: String, stock: Array) -> String:
	var own: Dictionary = tdata.get("shouts", {})
	var lines: Array = own.get(key, stock)
	return lines.pick_random()


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _log(what: String) -> void:
	var key := what.split(",")[0]
	game.stats[key] = game.stats.get(key, 0) + 1
	if game._args.has("bot") or game._args.has("rattle"):
		print("%.1fs  %s #%d: %s" % [(Time.get_ticks_msec() - game.start_time) / 1000.0, kind, game.enemies.find(self), what])


func accuracy_mult() -> float:
	var m: float = (AIM_SPREAD_SHOTGUN if weapon.is_shotgun() else AIM_SPREAD) * float(tdata["aim"])
	if panic:
		return m * 5.0   # wild, over the shoulder
	if suppress_t > 0.0:
		m *= 1.5
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
