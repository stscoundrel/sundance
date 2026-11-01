class_name Civilian
extends Actor
## Townsfolk: unarmed, and only in the way. They idle and stroll near home. Gunfire
## close by or in view, a round cracking past or a man dropping in front of them
## sends them running for the nearest doorway that isn't towards the shooting (or off
## the edge of town) and they're gone; the faint-hearted cower first. One in five or
## so is a snitch, and a sharp eye can tell: honest folk glance at the stranger and
## look away, a snitch keeps staring and edges off towards the bandits. Given a good
## long look he hurries to the nearest one, points him out and shouts, then makes
## himself scarce. Once the town has been quiet a while they come back out.
## The undertaker and his apprentice ("role": "undertaker") work the quiet: each
## claims a dead bandit, measures him, and drags him to boot hill to be buried. The
## padre ("role": "priest") kneels and blesses the dead first, anyone at all, and
## the church bell tolls for each; he fears no man, and neither gunfire nor the
## stranger sends him running. Couples ("couple" in the placement) stroll arm in
## arm while all is calm, and scatter separately when it isn't. Mourners ("role":
## "mourner", placed "indoors") stay inside until there's a fresh grave and the town
## is quiet, then come out in black to stand at it a while, and go home again.
## The gunsmith ("role": "gunsmith") gathers up the guns the dead dropped, once the
## undertaker has the body away, four or five a trip, cartridges and all, and carries
## them into his shop. Shoot him and his armful spills round him.
## The mayor ("role": "mayor", with a "stump" to speak from) is all bluster: when
## the shooting starts he hurries out to the plaza and harangues the lot of them to
## stop. A round cracking past or a man dropping near him, and he's down on his
## knees, hat in hands, until it's calmer; then back to it. Once the town has gone
## quiet he tours the damage, hands behind his back, tutting at every wrecked crate
## and scorch mark.
## Once it's quiet the town puts itself right. The carpenter ("role": "carpenter")
## mends whatever wood is broken (crates, barrels, troughs, wagons, chairs, coops),
## the mayor's list first, and cover is cover again. The saloon keeper ("keeper")
## sets his own tables and chairs back up, bottles and all. Sweepers ("sweeper")
## sweep blood, glass and scorch into the dirt, the stranger's trail with it. Hen
## women ("henwife") shoo strays back home to the coops.

enum St { IDLE, WALK, FLEE, COWER, SNITCH, GONE, TO_BODY, MEASURE, DRAG, TO_BLESS, BLESS, TO_GRAVE, MOURN,
	TO_GUN, PICK, HAUL, TO_STUMP, ORATE, TO_SCAR, SURVEY, TO_FIX, FIX, TO_SWEEP, SWEEP, HERD }

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
const WORK := [St.TO_BODY, St.MEASURE, St.DRAG, St.TO_BLESS, St.BLESS, St.TO_GRAVE, St.MOURN, St.TO_GUN,
	St.PICK, St.HAUL, St.TO_STUMP, St.ORATE, St.TO_SCAR, St.SURVEY, St.TO_FIX, St.FIX, St.TO_SWEEP, St.SWEEP,
	St.HERD]
const MEASURE_T := 3.5
const BLESS_T := 4.0
const MOURN_T := Vector2(20.0, 32.0)
const PICK_T := 2.0
const GATHER_NEAR := 400.0   # once he has a gun in hand, he only goes on for ones this close
const ARM := 13.0          # how far beside him she walks
const DRAG_SPEED := 0.65   # of his walk, with a man in tow
const HUSH := 8.0          # s of quiet and the mayor steps down
const SURVEY_AFTER := 12.0 # s of quiet before he goes round the damage
const SURVEY_T := 3.5      # s tutting at each
const TOUR := 4            # wrecks a tour, then home
const FIX_T := 12.0        # s at a broken crate, barrel, wagon...
const MEND_T := 6.0        # s at a chair, table or coop
const SWEEP_T := 4.0       # s sweeping a spot

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
var hid_at := Vector2.ZERO   # the door he went in by, and comes back out of
var back_after := 0.0        # extra quiet he waits for before coming out
var inside_t := 0.0          # how long he's been indoors
var fade: Tween
var undertaker := false
var priest := false
var mourner := false
var mourning: Dictionary = {}   # the grave she's going to, or standing at
var gunsmith := false
var gun: Dictionary = {}        # the loose gun he's going for
var carried: Array[Dictionary] = []   # what he's gathered: {kind, ammo_kind}
var load_size := 5              # how many he'll carry this trip
var mayor := false
var stump := Vector2.INF        # where he makes his speeches
var orate_t := 0.0              # till his next line
var scar: Dictionary = {}       # the damage he's looking at
var toured := 0
var carpenter := false
var keeper := false
var sweeper := false
var henwife := false
var job: Dictionary = {}        # the broken thing he's mending
var dirt := Vector2.INF         # the mess she's sweeping
var hen: Chicken                # the stray she's shooing home
var knock_t := 0.0
var body: Actor              # the dead man he's seeing to
var partner: Civilian        # the other half of a couple
var leads := false           # he sets the way; she keeps to his arm
var work_t := 0.0
var grave := Vector2.ZERO
var trail := Vector2.ZERO    # where the last smear went down
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
	undertaker = tdata.get("role", "") == "undertaker"
	priest = tdata.get("role", "") == "priest"
	mourner = tdata.get("role", "") == "mourner"
	gunsmith = tdata.get("role", "") == "gunsmith"
	mayor = tdata.get("role", "") == "mayor"
	carpenter = tdata.get("role", "") == "carpenter"
	keeper = tdata.get("role", "") == "keeper"
	sweeper = tdata.get("role", "") == "sweeper"
	henwife = tdata.get("role", "") == "henwife"
	if tdata.has("stump"):
		stump = Iso.to_screen(Vector2(tdata["stump"][0], tdata["stump"][1]))
	if undertaker:
		anim_gun = "tools"   # empty hands plus the tape and the haul
	elif priest:
		anim_gun = "prayer"  # a book in one hand, a blessing in the other
	elif mourner:
		anim_gun = "grief"   # hands clasped, and a handkerchief
	elif gunsmith:
		anim_gun = "smith"   # a gun held up to the light, and an armful of them
	elif mayor:
		anim_gun = "mayor"   # thumbs in his waistcoat, arms wide on the soapbox
	elif carpenter:
		anim_gun = "carpentry"   # a hammer in hand
	elif keeper:
		anim_gun = "keeper"      # a towel over his arm
	elif sweeper or henwife:
		anim_gun = "broom"
	home = pos
	facing = Vector2.from_angle(deg_to_rad(facing_deg))
	desired = facing
	wait = randf_range(1.0, 6.0)
	t = randf() * 10.0
	if tdata.get("indoors", false):
		_go_inside(false)
		modulate.a = 0.0
		visible = false


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
	if priest:
		# a holy man: he stands his ground, and may have a word for it
		if shout_t <= 0.0 and randf() < 0.4:
			_say(_line("calm", ["Peace, my son."]))
		return
	threat = from
	if mayor:
		_bluster(scary)
		return
	_drop_body()   # the dead can wait
	_leave_grave()
	_let_go_of_gun()
	_drop_job()
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
	hid_at = game.refuge_for(global_position, threat)
	path = game.find_path(global_position, hid_at)
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
		inside_t += delta
		if game.state == "play" and inside_t > 10.0 and game.quiet_for() >= game.quiet_after + back_after:
			if not mourner:
				_come_out()
			else:
				_to_a_grave()
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
		St.IDLE, St.WALK when _on_his_arm():
			_escort()
		St.IDLE:
			_idle(delta)
		St.WALK:
			if leads and partner and partner._on_his_arm() and partner.global_position.distance_to(global_position) > ARM * 3.0:
				velocity = Vector2.ZERO   # waits for her to catch up
			elif _follow(walk):
				st = St.IDLE
				wait = randf_range(2.0, 5.0) if leads else randf_range(3.0, 8.0)
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
				if not mayor:
					_flee()
				elif game.quiet_for() < 3.0:
					cower_t = 1.0   # still shooting: he stays down
				else:
					crouched = false
					_to_stump()   # calmer: he picks himself up and starts again
		St.SNITCH:
			_snitch(delta)
		St.TO_BODY, St.MEASURE, St.DRAG:
			_work(delta)
		St.TO_BLESS, St.BLESS:
			_bless(delta)
		St.TO_GRAVE, St.MOURN:
			_mourn(delta)
		St.TO_GUN, St.PICK, St.HAUL:
			_gather(delta)
		St.TO_STUMP, St.ORATE, St.TO_SCAR, St.SURVEY:
			_mayor(delta)
		St.TO_FIX, St.FIX:
			_mend(delta)
		St.TO_SWEEP, St.SWEEP:
			_sweep(delta)
		St.HERD:
			_herd(delta)
	if carried and pose == "":
		pose = "carry"
	if velocity.length() > 1.0 and not watching:
		desired = velocity.normalized()
	facing = facing.rotated(clamp(facing.angle_to(desired), -3.0 * delta, 3.0 * delta))
	move_and_slide()
	update_anim(delta)


func _perceive(delta: float) -> void:
	var p: Player = game.player
	watching = false
	if not p.alive or st in [St.FLEE, St.COWER, St.SNITCH] or st in WORK:
		return
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
	if mourner:
		_go_inside(false)   # home again, and in at the door
		return
	if undertaker and game.quiet_for() >= game.quiet_after:
		body = game.claim_body(self)
		if body:
			st = St.TO_BODY
			path = game.find_path(global_position, body.global_position)
			path_i = 0
			return
	if gunsmith and game.quiet_for() >= game.quiet_after:
		_next_gun()
		if st != St.IDLE:
			return
	if mayor:
		if game.quiet_for() < SURVEY_AFTER:
			toured = 0   # more damage to come, likely
		elif toured < TOUR:
			_next_scar()
			if st != St.IDLE:
				return
	if game.quiet_for() >= game.quiet_after and _find_work():
		return
	if priest and game.quiet_for() >= game.quiet_after:
		body = game.blessing_for(self)
		if body:
			st = St.TO_BLESS
			path = game.find_path(global_position, body.global_position)
			path_i = 0
			return
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
func _go_inside(hiding := true) -> void:
	st = St.GONE
	velocity = Vector2.ZERO
	occluded = false
	_sync_ghost()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("collision_layer", 0)
	fade = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.4)
	fade.tween_callback(func(): visible = false)
	inside_t = 0.0
	back_after = randf_range(0.0, 15.0)   # they don't all come out at once
	if hiding:
		game.stats["civilian hides"] = game.stats.get("civilian hides", 0) + 1


## The town's been quiet long enough: back out the way he went in, and home.
func _come_out() -> void:
	st = St.WALK
	visible = true
	crouched = false
	saw_t = 0.0
	looked_away = false
	snitch = randf() < float(tdata["snitch"])
	collision_layer = Iso.LAYER_ACTOR
	collision_mask = Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR
	hurtbox.collision_layer = Iso.LAYER_HURT
	if fade:
		fade.kill()
	fade = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.5)
	path = game.find_path(global_position, home)
	path_i = 0
	game.stats["civilian returns"] = game.stats.get("civilian returns", 0) + 1


# ------------------------------------------------------------------ the undertaker

func _work(delta: float) -> void:
	if body == null or body.has_meta("buried"):
		_drop_body()
		st = St.IDLE
		return
	match st:
		St.TO_BODY:
			if global_position.distance_to(body.global_position) < 14.0 or _follow(walk):
				st = St.MEASURE
				work_t = MEASURE_T
				velocity = Vector2.ZERO
				if randf() < 0.6:
					_say(_line("work", ["Hm."]))
		St.MEASURE:
			# the tape out over him, head to boots
			velocity = Vector2.ZERO
			pose = "measure"
			desired = (body.global_position - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				grave = game.grave_spot()
				path = game.find_path(global_position, grave)
				path_i = 0
				trail = body.global_position
				st = St.DRAG
		St.DRAG:
			pose = "drag"
			var there := _follow(walk * DRAG_SPEED)
			if velocity.length() > 1.0:
				body.global_position = global_position - velocity.normalized() * 16.0
			if body.global_position.distance_to(trail) > 9.0:
				trail = body.global_position
				game.decals.add(trail, randf_range(1.2, 2.2), Color(0.34, 0.07, 0.05, 0.4))
			if there:
				game.bury(body, grave)
				body = null
				st = St.IDLE
				wait = randf_range(2.0, 4.0)


func _drop_body() -> void:
	if body and body.has_meta("claimed_by") and body.get_meta("claimed_by") == self:
		body.remove_meta("claimed_by")
	if body and body.has_meta("blessing_by") and body.get_meta("blessing_by") == self:
		body.remove_meta("blessing_by")
	crouched = false
	body = null


# ------------------------------------------------------------------ the padre

func _bless(delta: float) -> void:
	# gone, or already in the undertaker's hands: on to the next
	if body == null or body.has_meta("buried") or game.in_hand(body):
		_drop_body()
		st = St.IDLE
		return
	match st:
		St.TO_BLESS:
			if global_position.distance_to(body.global_position) < 16.0 or _follow(walk):
				st = St.BLESS
				work_t = BLESS_T
				velocity = Vector2.ZERO
				if randf() < 0.7:
					_say(_line("work", ["Requiescat in pace."]))
		St.BLESS:
			# on one knee, the sign of the cross over him
			velocity = Vector2.ZERO
			crouched = true
			pose = "bless"
			desired = (body.global_position - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				body.set_meta("blessed", true)
				game.sfx("bell", null, -14.0, 0.0)   # the church bell, far off
				game.stats["blessings"] = game.stats.get("blessings", 0) + 1
				_drop_body()
				st = St.IDLE
				wait = randf_range(1.5, 3.0)


# ------------------------------------------------------------------ mourners

## A fresh grave wants weeping over: out she comes, in black, and up to boot hill.
func _to_a_grave() -> void:
	var g: Dictionary = game.grave_to_mourn()
	if g.is_empty():
		return
	_come_out()
	mourning = g
	# beside the mound, a little apart from whoever else is there
	var spot: Vector2 = g["at"] + Vector2(randf_range(-16.0, 16.0), randf_range(10.0, 16.0))
	path = game.find_path(global_position, game.free_point_near(spot, 10.0))
	path_i = 0
	st = St.TO_GRAVE


func _mourn(delta: float) -> void:
	match st:
		St.TO_GRAVE:
			if _follow(walk):
				st = St.MOURN
				work_t = randf_range(MOURN_T.x, MOURN_T.y)
				velocity = Vector2.ZERO
				if randf() < 0.6:
					_say(_line("work", ["..."]))
		St.MOURN:
			velocity = Vector2.ZERO
			pose = "mourn"
			desired = (mourning["at"] - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				mourning["done"] = true
				mourning = {}
				game.stats["mournings"] = game.stats.get("mournings", 0) + 1
				path = game.find_path(global_position, home)
				path_i = 0
				st = St.WALK


## Frightened off before she'd done: the grave is free for someone else.
func _leave_grave() -> void:
	if not mourning.is_empty():
		mourning["mourners"] -= 1
		mourning = {}


# ------------------------------------------------------------------ the gunsmith

## On to the next gun: the nearest one going, then only ones close by; with his
## arms full, or nothing more nearby, home with the lot.
func _next_gun() -> void:
	if carried.is_empty():
		load_size = randi_range(4, 5)
	if carried.size() < load_size:
		gun = game.claim_gun(self, global_position, INF if carried.is_empty() else GATHER_NEAR)
		if not gun.is_empty():
			st = St.TO_GUN
			path = game.find_path(global_position, gun["at"])
			path_i = 0
			return
	if carried:
		st = St.HAUL
		path = game.find_path(global_position, home)
		path_i = 0


func _gather(delta: float) -> void:
	match st:
		St.TO_GUN:
			if not game.loose_guns.has(gun):
				_let_go_of_gun()
				st = St.IDLE
			elif global_position.distance_to(gun["at"]) < 12.0 or _follow(walk):
				st = St.PICK
				work_t = PICK_T
				velocity = Vector2.ZERO
		St.PICK:
			# down on one knee for it, then holding it up to the light
			velocity = Vector2.ZERO
			crouched = true
			pose = "pick"
			if not game.loose_guns.has(gun):
				_let_go_of_gun()
				st = St.IDLE
				return
			desired = (gun["at"] - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				game.take_gun(gun)
				carried.append({"kind": gun["kind"], "ammo_kind": gun["ammo_kind"]})
				if randf() < 0.3:
					_say(_line("work", ["Hm."]))
				gun = {}
				crouched = false
				st = St.IDLE
				wait = 0.3
		St.HAUL:
			if _follow(walk):
				game.stats["guns stored"] = game.stats.get("guns stored", 0) + carried.size()
				carried.clear()
				_go_inside(false)   # into the shop with them


func _let_go_of_gun() -> void:
	if not gun.is_empty() and gun.get("claimed_by") == self:
		gun["claimed_by"] = null
	gun = {}
	crouched = false


# ------------------------------------------------------------------ the mayor

## Gunfire: out to his soapbox to tell them all to stop. Something close and
## frightening, though, and he's on his knees.
func _bluster(scary: bool) -> void:
	if scary:
		if st != St.COWER:
			st = St.COWER
			velocity = Vector2.ZERO
			_say(_line("cower", ["Don't shoot!"]))
			game.stats["mayor cowers"] = game.stats.get("mayor cowers", 0) + 1
		cower_t = randf_range(2.5, 4.5)
		return
	if st == St.COWER or st == St.TO_STUMP or st == St.ORATE:
		return
	_to_stump()


func _to_stump() -> void:
	scar = {}
	st = St.TO_STUMP
	var at := stump if stump != Vector2.INF else home
	path = game.find_path(global_position, at if game.is_free(at) else game.free_point_near(at, 20.0))
	path_i = 0


## Hurrying out, then holding forth; down again once it's been quiet a while. Then,
## when it's been quiet longer, round the damage one wreck at a time.
func _mayor(delta: float) -> void:
	if st in [St.TO_STUMP, St.ORATE] and game.quiet_for() >= HUSH:
		st = St.IDLE
		wait = randf_range(2.0, 4.0)
		return
	match st:
		St.TO_STUMP:
			if _follow(run * 0.75):
				st = St.ORATE
				orate_t = 0.3
		St.ORATE:
			velocity = Vector2.ZERO
			pose = "orate"
			desired = (threat - global_position).normalized()
			orate_t -= delta
			if orate_t <= 0.0:
				orate_t = randf_range(3.0, 4.5)
				_say(_line("calm", ["Gentlemen, please!"]))
				game.stats["mayor speeches"] = game.stats.get("mayor speeches", 0) + 1
		St.TO_SCAR:
			pose = "survey"
			if _follow(walk):
				st = St.SURVEY
				work_t = SURVEY_T
		St.SURVEY:
			velocity = Vector2.ZERO
			pose = "survey"
			desired = (scar["at"] - global_position).normalized()
			work_t -= delta
			if work_t <= SURVEY_T - 0.6 and work_t + delta > SURVEY_T - 0.6 and randf() < 0.75:
				_say(_line("work", ["Tsk."]))
			if work_t <= 0.0:
				game.stats["damage surveyed"] = game.stats.get("damage surveyed", 0) + 1
				toured += 1
				scar = {}
				st = St.IDLE
				wait = 0.5


## The next wreck to tut over, or home when there's none (or he's seen enough).
func _next_scar() -> void:
	scar = game.scar_to_survey(global_position) if toured < TOUR else {}
	if scar.is_empty():
		if toured > 0 and global_position.distance_to(home) > 10.0:
			path = game.find_path(global_position, home)
			path_i = 0
			st = St.WALK
		toured = TOUR   # done for now
		return
	var at: Vector2 = scar["at"] + Vector2.from_angle(randf() * TAU) * 22.0 * Vector2(1.0, 0.5)
	path = game.find_path(global_position, at if game.is_free(at) else game.free_point_near(at, 20.0))
	path_i = 0
	st = St.TO_SCAR


# ------------------------------------------------------------------ the town tidies up

## The quiet's back: anything for him to see to?
func _find_work() -> bool:
	if carpenter or keeper:
		job = game.repair_job(self)
		if not job.is_empty():
			var at: Vector2 = game.job_at(job)
			var stand := at + (global_position - at).normalized() * 16.0
			path = game.find_path(global_position, stand if game.is_free(stand) else game.free_point_near(stand, 16.0))
			path_i = 0
			st = St.TO_FIX
			return true
	if sweeper:
		dirt = game.dirt_job(self)
		if dirt != Vector2.INF:
			path = game.find_path(global_position, dirt if game.is_free(dirt) else game.free_point_near(dirt, 12.0))
			path_i = 0
			st = St.TO_SWEEP
			return true
	if henwife:
		hen = game.stray_hen(self)
		if hen:
			st = St.HERD
			work_t = 40.0   # (she gives up on one that won't be shooed)
			repath_t = 0.0
			return true
		job = game.laundry_job(self)   # the washing shot through, or down in the dirt: out again
		if not job.is_empty():
			var at: Vector2 = game.job_at(job)
			path = game.find_path(global_position, at if game.is_free(at) else game.free_point_near(at, 14.0))
			path_i = 0
			st = St.TO_FIX
			return true
	return false


func _mend(delta: float) -> void:
	if job.is_empty() or job["state"] == 0:
		_drop_job()
		st = St.IDLE
		return
	match st:
		St.TO_FIX:
			if _follow(walk):
				st = St.FIX
				work_t = MEND_T if keeper or not job.has("hp") else FIX_T
				knock_t = 0.0
		St.FIX:
			velocity = Vector2.ZERO
			desired = (game.job_at(job) - global_position).normalized()
			if keeper:
				pose = "tidy"
			elif henwife:
				pose = "shoo"   # (pegging it out again)
			else:
				crouched = true
				pose = "hammer"
				knock_t -= delta
				if knock_t <= 0.0:
					knock_t = 1.1
					game.sfx("hammer", global_position, -12.0, 0.1)
			work_t -= delta
			if work_t > 0.0:
				return
			if game.in_the_way(job, self):
				work_t = 1.0   # someone's standing right there
				return
			game.repair(job)
			job = {}
			crouched = false
			if randf() < 0.5:
				_say(_line("work", ["There."]))
			st = St.IDLE
			wait = 0.4


func _sweep(delta: float) -> void:
	match st:
		St.TO_SWEEP:
			if _follow(walk):
				st = St.SWEEP
				work_t = SWEEP_T
				knock_t = 0.0
		St.SWEEP:
			velocity = Vector2.ZERO
			pose = "sweep"
			desired = (dirt - global_position).normalized() if global_position.distance_to(dirt) > 4.0 else desired
			knock_t -= delta
			if knock_t <= 0.0:
				knock_t = 0.9
				game.sfx("sweep", global_position, -14.0, 0.15)
			work_t -= delta
			if work_t <= 0.0:
				game.sweep_at(dirt, self)
				dirt = Vector2.INF
				if randf() < 0.2:
					_say(_line("work", ["..."]))
				st = St.IDLE
				wait = 0.3


## Round behind the stray, broom up, and on towards the coop she goes.
func _herd(delta: float) -> void:
	work_t -= delta
	if hen == null or not is_instance_valid(hen) or not hen in game.hens or work_t <= 0.0:
		_drop_job()
		st = St.IDLE
		wait = 0.5
		return
	if hen.st != Chicken.S.HERD and hen.herder != self:
		_drop_job()
		st = St.IDLE
		return
	var coop: Dictionary = game.coop_for(hen.position)
	var ahead: Vector2 = hen.heading() if hen.st == Chicken.S.HERD else coop["at"]
	var behind: Vector2 = hen.position + (hen.position - ahead).normalized() * 16.0
	if global_position.distance_to(behind) > 12.0:
		repath_t -= delta
		if repath_t <= 0.0 or path_i >= path.size():
			repath_t = 0.8
			path = game.find_path(global_position, behind if game.is_free(behind) else hen.position)
			path_i = 0
		_follow(run * 0.55 if hen.st == Chicken.S.HERD else walk * 1.2)
	else:
		velocity = (behind - global_position) * 2.0
	pose = "shoo"
	if hen.st != Chicken.S.HERD and global_position.distance_to(hen.position) < 26.0:
		hen.herd(coop)
		if shout_t <= 0.0 and randf() < 0.5:
			_say(_line("work", ["¡Fuera!"]))


## Frightened off (or done): whatever he'd taken on is free for someone else.
func _drop_job() -> void:
	if not job.is_empty() and job.get("fixer") == self:
		job["fixer"] = null
	job = {}
	if dirt != Vector2.INF:
		game.sweeping.erase(self)
		dirt = Vector2.INF
	if hen and is_instance_valid(hen) and hen.herder == self:
		hen.herder = null
		if hen.st == Chicken.S.HERD:
			hen.st = Chicken.S.PECK
	hen = null


# ------------------------------------------------------------------ couples

## She's on his arm while they're both just out for a stroll.
func _on_his_arm() -> bool:
	return partner != null and not leads and partner.alive and partner.st in [St.IDLE, St.WALK] \
		and st in [St.IDLE, St.WALK]


func _escort() -> void:
	var at := partner.global_position + partner.facing.orthogonal() * ARM
	var d := global_position.distance_to(at)
	if d > ARM * 2.0 or not game.clear_path(global_position, at):
		# fallen behind, or something in the way: find her way round to him
		repath_t -= get_physics_process_delta_time()
		if repath_t <= 0.0 or path_i >= path.size():
			repath_t = 0.6
			path = game.find_path(global_position, partner.global_position)
			path_i = 0
		_follow(run * 0.7)
	elif d > 3.0:
		velocity = (at - global_position).normalized() * minf(run * 0.7, maxf(walk, d * 3.0))
	else:
		velocity = Vector2.ZERO
		if not watching:
			desired = partner.facing


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
