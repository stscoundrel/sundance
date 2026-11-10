extends Node2D
## Builds the town from data/town.json and assets/meta.json, owns the shared systems
## (physics queries, pathfinding, noise, bullets, effects, sound) and the match flow.

const LEVELS_PATH := "res://data/levels.json"
const BUDGET := 12   # loadout points where a level names none: a good gun in each slot and a bandage
# The level picker's choice, kept over the scene reload that loads it; and where
# that reload lands ("loadout" after a pick, "levels" after a restart).
static var chosen_level := ""
static var open_on := ""
static var ridden := {}         # the towns he's left quiet this sitting (the picker marks them)
var menu: Array[String] = []    # Esc's menu, while it's up (the town stands still under it)
var menu_pick := 0
var levels: Array = []          # the ones the picker shows
var level_entry: Dictionary = {}
var level_pick := 0             # the picker's cursor
var posse_size := Posse.SIZE    # how few left before they band together (fewer, in a smaller gang)
const META_PATH := "res://assets/meta.json"
const ENEMIES_PATH := "res://data/enemies.json"
const POST_SHADER := preload("res://shaders/post.gdshader")
const LOUD := ["colt", "coach", "rifle", "sharps", "howdah", "spencer", "musket", "bell", "boom"]
const WIND := Vector2(7, -2)   # px/s drift for smoke and dust
# How much of the town the screen shows. The art is drawn in whole screen pixels to a
# world pixel (never smeared between them), three at the least, the close, detailed
# view a 1280x720 window has always had; a bigger window shows more of the town, out
# to VIEW_CAP, and past that its pixels only grow (a monitor's size buys the stranger
# no more sight than this). The HUD is laid out on a 640x360 page, scaled whole too.
const VIEW_CAP := Vector2(860, 400)   # world pixels, the most anyone sees (wide for a 21:9 screen, 640x360 at 16:9)
const VIEW_ZOOM := 3                  # screen pixels a world pixel, at the least (bar tiny windows)
const HUD_PAGE := Vector2(640, 360)   # the HUD's own pixels, at the least

var meta: Dictionary
var enemy_data: Dictionary   # data/enemies.json: body templates, bandit types, palettes
var level: Dictionary
var size := 40

var world: Node2D
var decals: Decals
var brass: Brass   # the spent cases, where they fell
var rubble: Wounds.Rubble   # (what blasts knock out of the walls: not for sweeping)
var cone_layer: Node2D
var statics: Node2D
var ghost_layer: Node2D
var camera: Camera2D
var hud_layer: CanvasLayer
var hud: Hud
var post: ColorRect

var player: Player
var enemies: Array[Enemy] = []
var civilians: Array[Civilian] = []
var doors := PackedVector2Array()   # doorsteps townsfolk can run inside from
var innocents := 0                  # townsfolk the hero has shot
var quiet_after := 45.0             # seconds without gunfire or a fight before the town stirs again
var last_gunfire := -1e9
var last_gunfire_at := Vector2.INF
var director: Director = null   # a level's waves, if it has any
var snowfall: Snowfall = null   # a snowy map's weather (see Snowfall), if it has any
var drifts: Drifts = null       # and the snow covering the dead (see Drifts)
var footprints: Footprints = null   # and the tracks everyone leaves in its snow
var sight := 1.0                # of a man's sight the weather leaves him (Snowfall: snow, a squall)
var wind_player: AudioStreamPlayer
var hanging: Hanging = null     # a man on the gallows to save, if the level has one
var captive: Captive = null     # a man tied to a pole, if the level has one
var cargo: Cargo = null         # the arms to be carried off, if the level has them (it's won at the wagon)
var mgun: MGun = null           # a machine gun for him, if the map has one
var minefield: Minefield = null # ground mined round his breastwork, and the plunger, if the map has them
var strongbox: Strongbox = null # the outlaws' gold to ride off with, if the map has it (Silencio)
# A big battle's smoke and chaos (the map's "haze": [range, spread]): the army's guns
# reach so far and throw so wide of what they would (the stranger's don't: he's seen
# it all before).
var haze := Vector2.ONE
# A gang with a coordinator (El General: "coordinator" in his type) fights to his
# orders while he lives: the alarm sends men out and falls back on a holdout. Down
# he goes, and it's over: no more orders, every man shaken, the faint-hearted run.
# (Each gang's own: see `gangs`. This is the one gang's, or the unnamed one's.)
var leaderless: bool:
	get: return gangs[""]["leaderless"]
	set(v): gangs[""]["leaderless"] = v
var flags: Array[Dictionary] = []   # colours lying in the dirt: {at, rec}
var said_line := false   # the level's line, said
const FLAG_SEEN := 300.0    # px: men this near see the colours go down (or up again)
const FLAG_RAISE := 340.0   # px: a regular this near runs to raise them
const FLAG_BREAKS := 0.4    # chance a leva who sees them go down loses heart
const GUN_FEAR_NEAR := 90.0 # px: men this near one the machine gun cuts down take fright
const GUN_FEAR_SEEN := 300.0   # px from the stranger: near enough for him to see it, on screen or not
var _quiet := 0.0
var graves := PackedVector2Array()
var to_mourn: Array[Dictionary] = []
var old_graves := PackedVector2Array()   # the long dead, for the families to go round
var open_graves: Array[Dictionary] = []  # graves being dug, each with its coffin waiting
const GRAVES := ["cross", "headstone", "headstone_b", "mound"]
const FLAT := ["stone_circle"]   # things on the ground people walk across, drawn under them
# Guns lying about: {kind, sprite, at, under (the body it fell with, or null),
# ammo (the cartridges dropped beside it: a Pickup, or null), ammo_kind, claimed_by,
# weapon (how it was left loaded, if known), his (the stranger put it down)}
var loose_guns: Array[Dictionary] = []
var at_feet: Dictionary = {}   # the gun the stranger's standing over, his to take (F)
# The gang's reserve, drinking in the den (the saloon) until the shooting comes close
# and loud enough (heat), or a runner fetches them. Silence the street first and
# they never come; once out, they have to die too.
const DEN_EAR := 450.0       # px from the den door: gunfire this close heats it up
const DEN_HEAT := 7.0        # this much heat (about a shot each) and out they come
const DEN_COOL := 0.25       # heat lost a second
const RUNNER_AFTER := 3.0    # seconds of fighting before someone runs for help
const RUNNER_CD := 15.0      # after a runner falls, before another goes
var den := {}
# Where the stranger has been shooting from: spots, each a cluster of the places he
# fired from (the corners of one small house count as one spot, as does turning
# from side to side). Bandits who've seen him peek out of one twice hold their aim
# on it; the kills from each are counted too.
const SPOT_SPAN := 90.0      # px from a spot's centre that still counts as it
const SPOT_LINK := 50.0      # or this close to any place he fired from there
const PEEK_GAP := 1.5        # s without a shot before the next one is a new peek
const SPOT_FORGET := 35.0    # s unused and the gang forgets it
const SPOT_HOT := 2          # peeks before they start watching it
const WATCHERS := 2          # at most this many on one spot; the rest keep moving
var fire_spots: Array[Dictionary] = []
# Dynamite: thrown at a firing spot the stranger has killed from, one stick at a time.
const DYN_KILLS := 2         # kills from one spot before it's worth a stick
const DYN_FRESH := 8.0       # s: he has to have fired from there this recently
const DYN_CD := 20.0         # s after a blast before anyone lights another
const THROW_MIN := 100.0     # px: never close enough to catch it himself
const THROW_MAX := 220.0
var lit: Array[Dynamite] = []
var pesos_heard: Array = []   # [{at, t}]: where money's fallen from the sky lately (see peso_landed)
var dyn_cd := 0.0
# Cover that wears: crates, barrels, coffins, troughs and wagons take the rounds that
# hit them, look shot up past half, and fall to a heap of boards (no longer cover,
# nor in anyone's way). A damaged trough leaks. Toughness decides which rounds go
# straight through (a Winchester through a crate, a Sharps through a barrel too).
const PROP_HP := {"crate": 9, "coffin": 8, "barrel": 12, "trough": 21, "wagon": 33, "wagon_over": 33, "nest_x": 120, "nest_y": 120, "crate_stack": 16,
	"upturned_n": 7, "upturned_s": 7, "upturned_e": 7, "upturned_w": 7, "keg": 1, "dyn_crate": 1}
const PROP_TOUGH := {"crate": 1, "coffin": 1, "barrel": 2, "trough": 3, "wagon": 3, "wagon_over": 3, "nest_x": 3, "nest_y": 3, "crate_stack": 2,
	"upturned_n": 1, "upturned_s": 1, "upturned_e": 1, "upturned_w": 1, "keg": 9, "dyn_crate": 9}
# Props that go up when hit (see Charge): anyone's round, or a blast close by.
const EXPLOSIVE := ["keg", "dyn_crate"]
const CHAIN := Vector2(0.15, 0.35)   # s: a keg in reach of a blast goes up this soon after
const WOUND_RAYS := 40               # rays fanned out from a blast to find the walls it marks
const RUNS_FROM := 2                 # rank: officers know a lit keg when they see one, and run
const SPOT_STICK := 0.35             # chance one of the rest sees the stranger's stick land in time
var charges: Array[Charge] = []
const BANDAGE_DROP := 0.2     # chance a dead man leaves a bandage he hadn't used
const PESO_DROP := 0.25       # chance a dead man's pockets give up a peso
const PESO_START := 3         # pesos the stranger rides in with
const PESO_EAR := 140.0       # px: how far off a peso's clink is heard
const PESO_SPOT := 120.0      # px: pesos landing this close together are the same trick
const PESO_MEMORY := 90.0     # s the gang remembers money falling from the sky there
const STICK_DROP := 0.5       # and the dynamite he hadn't thrown
var loot_rng := RandomNumberGenerator.new()
var peso_rng := RandomNumberGenerator.new()   # (the pesos: a dead man's, the clink of a tossed one)
var litter_rng := RandomNumberGenerator.new()   # (how last night's bottles lie)
var rise_rng := RandomNumberGenerator.new()     # (what they say when he gets up out of the dirt)
var scars: Array[Dictionary] = []   # damage for the mayor to tut over: {at, seen, prop}
# Blood trails: every drop a wounded man leaves. The gang can follow the stranger's.
const TRAIL_FRESH := 45.0   # s a drop stays a lead worth following
const TRAIL_SEE := 170.0    # px: a bandit notices a drop this close (in view)
const TRAIL_CLOSE := 70.0   # px: following a trail, he picks up the next drop this close anywhere round him
var trails: Array[Dictionary] = []   # {at, t, player}
const CORNER_NEAR := 60.0   # px: how close to his spot the corner they shoot at must be
var blood_pools: Array[Dictionary] = []   # where bandits fell: {at, body, known (who's seen it bare)}
# Things gunfire breaks that are no cover at all: window panes, porch lanterns,
# tables of bottles, chairs, clay jars. Each hit moves one a look further gone.
const FRAGILE_R := {"olla": 5.0, "chair": 5.0, "table": 7.0, "lantern": 4.0, "coop": 9.0, "hencrate": 6.0,
	"sign": 7.0, "laundry": 6.0}
# Hanging signs swing when hit (a damped pendulum, a baked frame per angle); the
# third round parts a chain. Washing flaps; the first round holes it, the third
# tears it off the line.
const SIGN_REST := 3          # (frames: 7 angles of swing, then hanging askew)
const SIGN_STEP := 0.17       # rad between swing frames
const SIGN_K := 12.0          # pull back to the vertical (a swing of about two seconds)
const SIGN_DAMP := 1.4
const SIGN_KICK := 3.2        # rad/s a round sets it going
const SIGN_HITS := 3
const LAUNDRY_HITS := 3
var swinging: Array[Dictionary] = []   # signs on the move
var laundry: Array[Dictionary] = []
static var wind_rng := RandomNumberGenerator.new()   # (the breeze in the washing: the town's dice stay as seeded)
const HENS_IN := {"coop": 4, "hencrate": 3}   # shut in, till a round lets them out
const HENS_OUT := 2                           # pecking about each coop from the start
var hens: Array[Chicken] = []
var fragile: Array[Dictionary] = []   # {kind, at, state, last, sprite, body, (glass: a, b, z, shutter)}
var props: Array[Dictionary] = []   # {kind, sprite, body, g, fp, hp, state, cells, covers}
var _solid := {}                    # cell -> how many things block it   # {centre, points (newest first), peeks, kills, last_t}                # {door, sprite, squad, heat, rallied, cause, spawn_t, runner, runner_cd, fight_t, alarm}   # fresh graves: {at, mourners, done}
var innocent_t := 0.0               # the town's disapproval, on screen for a moment
const GHOST_THREAT := Color(1.0, 0.36, 0.26, 0.5)   # a known bandit behind a building
const GHOST_TOWN := Color(0.86, 0.82, 0.72, 0.5)    # anyone else: townsfolk, or so they seem
var buildings: Array[Dictionary] = []
var placed: Array[Dictionary] = []   # every object put down from the map: {type, g, sprite, body, cells, covers}
var _chunk_groups := 0   # (the pieces of each long thing placed so far, counted)
var shutters: Array[Shutter] = []
var cover_points := PackedVector2Array()
var astar := AStarGrid2D.new()

var state := "title"   # title, loadout, play, won, lost
static var picked: Array[String] = ["colt", "coach"]   # the loadout screen's choice (a gun a slot at most), kept across restarts
var start_guns: Array = Player.ORDER   # what he rides in with (tests: all three)
static var kit: Array[String] = ["bandage", "dynamite"]   # the kit bought on the loadout screen, kept too
var start_kit: Array = []      # the kit he rides in with...
var kit_chosen := false        # ...once he's come through the loadout screen (tests keep the level's own)
var shake := 0.0
var hurt_fx := 0.0
var alerted_once := false
var player_fired := false
var title_t := 0.0
var closeup_left := 0.0   # seconds of the stand-off still to run, in unscaled frame time
const FINISHERS := 2      # at most this many walking up to finish the stranger off
var down_slow := 0.0      # the moment he goes down, slowed (unscaled seconds left)
var heart_t := 0.0
var finish_cd := 3.0
var last_twang := -100.0   # (game time: a wall clock here would let machine load decide the dice)
var end_time := 0
var start_time := 0

var _textures := {}
var tex_scale := 0.5   # sprites carry 2x detail; world units stay 32x16 per tile
var _streams := {}
var _args := {}
var _shot_done := false
var _rattled := false
# What the gang knows about the stranger: when anyone last saw him or heard him
# fire, and where. Covering fire needs a fresh reason; stale knowledge only earns
# the odd harassing shot, and then silence.
const FRESH := 5.0       # seconds a sighting stays a reason to suppress
const HARASS_UNTIL := 12.0
const HARASS_EVERY := 3.0
var clock := 0.0         # game time in seconds (physics frames, so tests can run fast)
var seen_at := -100.0
var seen_pos := Vector2.ZERO
var harass_cd := 0.0
var posse: Posse   # the last few bandits, once they band together
var stats := {}   # counts of AI events ("orders covering fire", "panic shot"...)


func _ready() -> void:
	if not Engine.has_meta("fixed_seed"):   # tests seed the RNG themselves
		randomize()
		Shutter.rng.randomize()
		Chicken.rng.randomize()
		Smoulder.rng.randomize()
		Cargo.rng.randomize()
		Enemy.assault_rng.randomize()
		MGun.rng.randomize()
		Minefield.rng.randomize()
		Strongbox.rng.randomize()
		Snowfall.rng.randomize()
		Enemy.feud_rng.randomize()
		Enemy.gasp_rng.randomize()
		wind_rng.randomize()
		loot_rng.randomize()
		Enemy.rabble_rng.randomize()
		Enemy.return_rng.randomize()
		Enemy.schofield_rng.randomize()
		Enemy.henry_rng.randomize()
		Enemy.pump_rng.randomize()
		Enemy.champion_rng.randomize()
		Enemy.rollingblock_rng.randomize()
		Wounds.rng.randomize()
		Civilian.rng.randomize()
		Civilian.flirt_rng.randomize()
		litter_rng.randomize()
		rise_rng.randomize()
		Hanging.rng.randomize()
		Captive.rng.randomize()
		Brass.rng.randomize()
		Enemy.peso_rng.randomize()
		Enemy.habit_rng.randomize()
		peso_rng.randomize()
	else:
		Shutter.rng.seed = 7
		Chicken.rng.seed = 11
		Enemy.gasp_rng.seed = 13
		wind_rng.seed = 17
		loot_rng.seed = 19
		Enemy.rabble_rng.seed = 23
		Enemy.return_rng.seed = 29
		Enemy.schofield_rng.seed = 31
		Enemy.henry_rng.seed = 89
		Enemy.pump_rng.seed = 97
		Enemy.champion_rng.seed = 37
		Enemy.rollingblock_rng.seed = 41
		Wounds.rng.seed = 41
		Civilian.rng.seed = 43
		Civilian.flirt_rng.seed = 127
		litter_rng.seed = 47
		rise_rng.seed = 61
		Hanging.rng.seed = 53
		Brass.rng.seed = 73
		Captive.rng.seed = 59
		Smoulder.rng.seed = 67
		Cargo.rng.seed = 71
		Enemy.assault_rng.seed = 73
		MGun.rng.seed = 79
		Minefield.rng.seed = 83
		Strongbox.rng.seed = 101
		Snowfall.rng.seed = 103
		Enemy.feud_rng.seed = 107
		Enemy.peso_rng.seed = 109
		Enemy.habit_rng.seed = 131
		peso_rng.seed = 113
	_parse_args()
	_setup_input()
	meta = _load_json(META_PATH)
	enemy_data = _load_json(ENEMIES_PATH)
	_load_level()
	size = int(level["size"])
	if level.has("haze"):
		haze = Vector2(level["haze"][0], level["haze"][1])
	tex_scale = float(meta.get("tex_scale", 1.0))
	_build_world()
	_spawn_actors()
	if (level_entry.has("waves") and not Engine.has_meta("no_waves")) or level.has("sleepers") \
			or (level.has("camps") and not Engine.has_meta("no_camps")):   # (tests of the cargo leave the army out)
		director = Director.new()
		director.setup(self, level_entry.get("waves", []), level_entry.get("waves_from", "") == "first_shot")
		add_child(director)
	if DisplayServer.get_name() == "headless":
		get_tree().root.size = Vector2i(1280, 720)   # (no window to fit: a test plays in the one the game was made for)
	_build_overlay()
	start_time = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_setup_audio()
	for k in meta["sfx"]:
		_streams[k] = _takes(k)   # all up front: a first load mid-fight stalls the frame
	if DisplayServer.get_name() != "headless":
		_preload(meta)   # every sprite too, for the same reason (a crate's wreck, a pool of blood...)
	var wind := AudioStreamPlayer.new()
	wind.stream = load(meta["sfx"]["wind"])
	wind.volume_db = -12.0
	add_child(wind)
	wind.finished.connect(wind.play)
	wind.process_mode = Node.PROCESS_MODE_ALWAYS   # (it blows on under the menu)
	wind.play()
	wind_player = wind
	sfx("bell", null, -4.0, 0.0)
	if _args.has("guns"):
		start_guns = Array(_args["guns"].split(",")).filter(func(k): return Player.SLOT.has(k))
	if _args.has("skip-title"):
		begin()
	elif _args.has("freeze"):
		hud.hide_title()   # debug: look around town with everyone standing still
	elif open_on == "loadout":
		_to_loadout()
	elif open_on == "levels":
		_to_levels()
	open_on = ""


## The level: the one the tests ask for, or named on the command line (--level=id),
## or picked last, or the first. A shuffled one deals its gang out over the map's
## guard posts, and a smaller or larger gang has a reserve and a posse to match.
func _load_level() -> void:
	var all: Array = _load_json(LEVELS_PATH)["levels"]
	levels = all.filter(func(l): return not l.get("hidden", false))
	var want: String = Engine.get_meta("level", chosen_level if chosen_level != "" else _args.get("level", ""))
	level_entry = all[0]
	for l in all:
		if l["id"] == want:
			level_entry = l
	level_pick = maxi(0, levels.find(level_entry))
	level = _load_json(level_entry["map"])
	if level.has("skin"):   # Silencio's town is San Miguel's under snow: the same things, baked white on top
		for m in meta["objects"].values():
			var sk: Dictionary = m.get("skins", {}).get(level["skin"], {})
			for k in sk:
				m[k] = sk[k]
	if level_entry.has("count"):   # (dealt out once the town's built: see _spawn_actors)
		var n := int(level_entry["count"])
		var gang: Array = level["enemies"]
		posse_size = clampi(roundi(Posse.SIZE * n / float(gang.size())), 3, Posse.SIZE)
		if level.has("reserve"):
			var squad: Array = level["reserve"]["squad"]
			var k := clampi(roundi(squad.size() * n / float(gang.size())), 2, 8)
			level["reserve"]["squad"] = range(k).map(func(i): return squad[i % squad.size()])


## `n` bandits on the map's guard posts, the count the seed: the same count, the
## same town. The mix of men is the map's own gang scaled to `n` (one El Jefe,
## always), each put where he suits (the boss at the boss's post, those passing as
## townsfolk on a porch, riflemen with a view), and kept apart as far as the posts allow.
static func shuffled_gang(lv: Dictionary, n: int, usable := Callable()) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = n
	var classic: Array = lv["enemies"]
	var share := {}
	for e in classic:
		share[e["kind"]] = share.get(e["kind"], 0) + 1
	var kinds: Array = []
	var rest: Array = []   # [fraction left over, kind]
	for k in share:
		var want: float = share[k] * n / float(classic.size())
		if k == "jefe":
			want = 1.0
		for i in int(want):
			kinds.append(k)
		rest.append([want - int(want) + rng.randf() * 0.01, k])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	var i := 0
	while kinds.size() < n:
		if rest[i % rest.size()][1] != "jefe":
			kinds.append(rest[i % rest.size()][1])
		i += 1
	kinds = kinds.slice(0, n)
	var order := {"boss": 0, "porch": 1, "lookout": 2}
	kinds.sort_custom(func(a, b): return order.get(_post_tag(a), 3) < order.get(_post_tag(b), 3))
	var posts: Array = lv["posts"].filter(func(p): return not usable.is_valid() or usable.call(p))
	for j in range(posts.size() - 1, 0, -1):   # shuffled by the count's own dice
		var k := rng.randi_range(0, j)
		var t = posts[j]
		posts[j] = posts[k]
		posts[k] = t
	var out: Array = []
	for kind in kinds:
		var tag := _post_tag(kind)
		var pick: Dictionary = {}
		for spacing in [6.0, 4.0, 2.0, 0.0]:
			for pass_ in 2:   # a post of his own kind first, then any (but the boss's or a porch)
				for p in posts:
					var fits: bool = p["tag"] == tag if pass_ == 0 else not p["tag"] in ["boss", "porch"]
					if fits and out.all(func(q): return Vector2(q["x"], q["y"]).distance_to(Vector2(p["x"], p["y"])) >= spacing):
						pick = p
						break
				if not pick.is_empty():
					break
			if not pick.is_empty():
				break
		if pick.is_empty():
			break   # (more bandits than posts)
		posts.erase(pick)
		var e: Dictionary = pick.duplicate()
		e.erase("tag")
		e["kind"] = kind
		out.append(e)
	return out


## A guard post a man can stand at (and walk, if it's a patrol): on open ground.
func usable_post(p: Dictionary) -> bool:
	var pts: Array = [[p["x"], p["y"]]] + p.get("patrol", [])
	return pts.all(func(q): return is_free(Iso.to_screen(Vector2(q[0], q[1]))))


static func _post_tag(kind: String) -> String:
	match kind:
		"jefe", "general":
			return "boss"
		"gambler", "saloon_girl":
			return "porch"
		"rifleman", "poacher", "tirador":
			return "lookout"
	return "street"


## Every texture the asset meta names, loaded now rather than the first time it's
## needed in the middle of a fight.
func _preload(node: Variant) -> void:
	if node is Dictionary:
		for v in node.values():
			_preload(v)
	elif node is Array:
		for v in node:
			_preload(v)
	elif node is String and node.begins_with("res://") and node.ends_with(".png"):
		tex(node)


## Glue and a brick-wall limiter on the master bus: gunfire can be mixed hot and
## stacked shots in a firefight stay punchy instead of clipping.
func _setup_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(bus) > 0:
		return
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	comp.attack_us = 2000.0
	comp.release_ms = 180.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(bus, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.3
	AudioServer.add_bus_effect(bus, lim)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


# ------------------------------------------------------------------ input

func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"crouch": [KEY_C, KEY_CTRL], "reload": [KEY_R], "knife": [KEY_E], "bandage": [KEY_B], "throw": [KEY_G], "toss": [KEY_Q], "take": [KEY_F],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
		"restart": [KEY_ENTER], "quit": [KEY_ESCAPE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "alt": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = buttons[action]
		InputMap.action_add_event(action, mb)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		_escape()
		get_viewport().set_input_as_handled()
	elif state == "title" and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		if Time.get_ticks_msec() - start_time > 600:
			_to_levels()
			get_viewport().set_input_as_handled()
	elif state == "levels" and event.is_pressed():
		_levels_input(event)
		get_viewport().set_input_as_handled()
	elif state == "loadout" and event.is_pressed():
		_loadout_input(event)
		get_viewport().set_input_as_handled()
	elif (state == "won" or state == "lost") and event.is_action_pressed("restart"):
		if state == "lost":
			ride_to(level_entry["id"], "loadout")   # (straight back to the guns: try it another way)
		elif not next_level().is_empty():
			ride_to(next_level()["id"], "loadout")
		else:
			ride_to(level_entry["id"], "levels")   # the last of them: choose where to ride
	elif event is InputEventMouseButton and event.pressed and player and state == "play":
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.cycle_weapon(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.cycle_weapon(-1)


func begin() -> void:
	if state != "title" and state != "loadout" and state != "levels":
		return
	if not start_guns.is_empty():
		player.arm(start_guns)
	if kit_chosen:
		player.bandages = 1 if "bandage" in start_kit else 0
		player.sticks = 1 if "dynamite" in start_kit else 0
	player.pesos = PESO_START
	state = "play"
	hud.hide_title()


## The title card gives way to choosing where to ride.
func _to_levels() -> void:
	state = "levels"
	hud.hide_title()


## Up and down (or W S) move the cursor, 1-9 or a click picks, Enter or Space
## takes the one under the cursor.
func _levels_input(event: InputEvent) -> void:
	if event is InputEventKey:
		match event.keycode:
			KEY_UP, KEY_W:
				level_pick = posmod(level_pick - 1, levels.size() + 1)
				sfx("close", null, -14.0)
			KEY_DOWN, KEY_S:
				level_pick = posmod(level_pick + 1, levels.size() + 1)
				sfx("close", null, -14.0)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				pick_level(level_pick)
			_:
				var i: int = event.keycode - KEY_1
				if i >= 0 and i < mini(9, levels.size()):
					pick_level(i)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var i: int = hud.level_hit(hud.get_local_mouse_position())
		if i >= 0:
			pick_level(i)


## This one: on to the guns if it's the town already loaded, else load it (the
## scene comes back up at the loadout). The row under the towns leaves the game.
func pick_level(i: int) -> void:
	if i >= levels.size():
		get_tree().quit()
		return
	var l: Dictionary = levels[i]
	sfx("close", null, -8.0)
	if l["id"] == level_entry["id"]:
		_to_loadout()
		return
	ride_to(l["id"], "loadout")


## The scene comes back up with town `id`, at "loadout" or "levels".
func ride_to(id: String, at: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	chosen_level = id
	open_on = at
	get_tree().reload_current_scene()


## The next town on the picker, or {} after the last (or a hidden one, in the tests).
func next_level() -> Dictionary:
	var i := levels.find(level_entry)
	return levels[i + 1] if i >= 0 and i + 1 < levels.size() else {}


## Esc goes back a step: the title to the picker, the guns to the picker, and the
## picker to its last row (leaving: Enter on it). In town it brings up the menu.
func _escape() -> void:
	match state:
		"title":
			_to_levels()
		"levels":
			level_pick = levels.size()
			sfx("close", null, -14.0)
		"loadout":
			_to_levels()
			sfx("close", null, -14.0)
		_:
			open_menu()


## The town stops where it is under the menu: back to it, the guns again, another
## town, or out of the game; after a win, on to the next town too.
func open_menu() -> void:
	menu.assign(["resume"])
	if state == "won" and not next_level().is_empty():
		menu.append("next")
	menu.append_array(["again", "levels", "quit"])
	menu_pick = 0
	get_tree().paused = true
	sfx("close", null, -10.0)


func close_menu() -> void:
	menu.clear()
	get_tree().paused = false


## The menu's keys (the hud hands them on: the game's paused under it). Up and down
## and Enter, a number, or a click; Esc closes it.
func menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		close_menu()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_W:
				menu_pick = posmod(menu_pick - 1, menu.size())
				sfx("close", null, -14.0)
			KEY_DOWN, KEY_S:
				menu_pick = posmod(menu_pick + 1, menu.size())
				sfx("close", null, -14.0)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				menu_choose(menu[menu_pick])
			_:
				var i: int = event.keycode - KEY_1
				if i >= 0 and i < menu.size():
					menu_choose(menu[i])
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i: int = hud.menu_hit(hud.get_local_mouse_position())
		if i >= 0:
			menu_choose(menu[i])


func menu_choose(k: String) -> void:
	sfx("close", null, -8.0)
	match k:
		"resume":
			close_menu()
		"next":
			ride_to(next_level()["id"], "loadout")
		"again":
			ride_to(level_entry["id"], "loadout")
		"levels":
			ride_to(level_entry["id"], "levels")
		"quit":
			get_tree().quit()


## What Enter does at the end of a town, on the end screen's last line.
func onward() -> String:
	if state == "lost":
		return "Enter: ride it again      Esc: the menu"
	if next_level().is_empty():
		return "Enter: choose where to ride      Esc: the menu"
	return "Enter: ride on to %s      Esc: the menu" % next_level()["name"]


## The title card (or the level picker) gives way to choosing his guns.
func _to_loadout() -> void:
	state = "loadout"
	_fit_budget()
	hud.hide_title()


## The points he has to spend on guns and kit: the level's, else BUDGET.
func budget() -> int:
	return int(level_entry.get("budget", BUDGET))


## The kit on sale: a bandage and a stick, in every town (the budget decides).
func kit_offered() -> Array:
	return Player.KIT.keys()


## What he's chosen costs: the guns, and the kit this level sells.
func spent() -> int:
	return Player.cost(picked, kit.filter(func(k): return k in kit_offered()))


## Whether he could swap what's in `slot` for `k` ("" to empty it) and stay in budget.
func affords(slot: String, k: String) -> bool:
	var now := picked_for(slot)
	var change := (Player.cost([k]) if k != "" else 0) - (Player.cost([now]) if now != "" else 0)
	return spent() + change <= budget()


## A choice kept from a richer level may cost more than this one gives: the dearest
## thing goes back first, kit before a gun of the same price, until it fits.
func _fit_budget() -> void:
	while spent() > budget():
		var dear := ""
		var price := -1
		for k in kit.filter(func(k): return k in kit_offered()):
			if Player.KIT[k] > price:
				dear = k
				price = Player.KIT[k]
		for k in picked:
			if Player.cost([k]) > price:
				dear = k
				price = Player.cost([k])
		if dear in kit:
			kit.erase(dear)
		else:
			picked.erase(dear)


## One gun a slot, or none. 1 2 3 (or a click on the card) goes through a slot's
## guns and then none; a click on a gun's name takes it, or puts it back if taken.
## Enter, Space or "ride in" starts with them.
func _loadout_input(event: InputEvent) -> void:
	var k := ""
	if event is InputEventKey:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				k = "slot:" + Player.ORDER[event.keycode - KEY_1]
			KEY_B:
				k = "kit:bandage"
			KEY_G:
				k = "kit:dynamite"
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_ride_in()
				return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: String = hud.loadout_hit(hud.get_local_mouse_position())
		if hit == "ride":
			_ride_in()
			return
		k = hit
	_loadout_pick(k)


## `k`: a gun's name clicked, "slot:<slot>" to go on to that slot's next gun he can
## afford, or "kit:<thing>" to buy it or give it back. Too dear: a dry click.
func _loadout_pick(k: String) -> void:
	if k == "":
		return
	if k.begins_with("slot:"):
		var slot := k.trim_prefix("slot:")
		var options: Array = Player.choices(slot) + [""]
		var now := options.find(picked_for(slot))
		for step in range(1, options.size() + 1):
			var o: String = options[(now + step) % options.size()]
			if affords(slot, o):
				_take_for_slot(slot, o)
				break
	elif k.begins_with("kit:"):
		var thing := k.trim_prefix("kit:")
		if not thing in kit_offered():
			return
		if thing in kit:
			kit.erase(thing)
		elif spent() + Player.KIT[thing] <= budget():
			kit.append(thing)
		else:
			sfx("dry", null, -6.0)
			return
	elif k in picked:
		picked.erase(k)
	elif affords(Player.SLOT[k], k):
		_take_for_slot(Player.SLOT[k], k)
	else:
		sfx("dry", null, -6.0)
		return
	sfx("close", null, -10.0)


## The gun taken for this slot on the loadout screen, or "".
func picked_for(slot: String) -> String:
	for k in picked:
		if Player.SLOT.get(k, "") == slot:
			return k
	return ""


func _take_for_slot(slot: String, k: String) -> void:
	picked.erase(picked_for(slot))
	if k != "":
		picked.append(k)
	picked.sort_custom(func(a, b): return Player.ORDER.find(Player.SLOT[a]) < Player.ORDER.find(Player.SLOT[b]))


func _ride_in() -> void:
	if picked.is_empty():
		sfx("dry", null, -6.0)
		return
	start_guns = picked.duplicate()
	start_kit = kit.filter(func(k): return k in kit_offered())
	kit_chosen = true
	begin()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var ground := Sprite2D.new()
	var gm: Dictionary = meta.get(level.get("ground", "ground"), meta["ground"])   # (a map may bake its own)
	ground.texture = tex(gm["file"])
	ground.centered = false
	ground.position = Vector2(gm["origin"][0], gm["origin"][1])
	ground.scale = Vector2.ONE * tex_scale
	ground.z_index = -20
	add_child(ground)

	decals = Decals.new()
	decals.z_index = -15
	add_child(decals)
	rubble = Wounds.Rubble.new()
	rubble.z_index = -14
	add_child(rubble)
	brass = Brass.new()
	brass.z_index = -14
	add_child(brass)
	cone_layer = Node2D.new()
	cone_layer.z_index = -10
	add_child(cone_layer)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	statics = Node2D.new()
	add_child(statics)
	ghost_layer = Node2D.new()
	ghost_layer.z_index = 40   # silhouettes of hidden characters, above everything in the world
	add_child(ghost_layer)

	astar.region = Rect2i(0, 0, size * 2, size * 2)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	for o in level["objects"]:
		var spr := _place_object(o["type"], Vector2(o["x"], o["y"]))
		var og := Vector2(o["x"], o["y"])
		if o.has("worn"):   # shot up before the stranger ever got here
			for prop in props:
				if prop["sprite"] == spr:
					prop["hp"] = 0 if int(o["worn"]) >= 2 else int(PROP_HP[prop["kind"]] * 0.5)
					_prop_state(prop, int(o["worn"]), true)
		if o.get("ours", false):   # the breastwork: the mines round it were laid to spare it
			for prop in props:
				if prop["sprite"] == spr:
					prop["ours"] = true
		if o["type"] == "open_grave":
			open_graves.append({"g": og, "sprite": spr, "at": Iso.to_screen(og + Vector2(1.1, 1.55)),
				"dug": 0.0, "filled": 0.0, "in": false, "done": false, "digger": null})
		elif o["type"] in GRAVES and _on_boot_hill(og):
			old_graves.append(Iso.to_screen(og + Vector2(0.25, 0.12)))
	_litter()
	for item in fragile:
		if item["kind"] == "coop":
			for i in HENS_OUT:
				_add_hen(item["at"], 34.0)

	# map boundary
	var edge := StaticBody2D.new()
	edge.collision_layer = Iso.LAYER_WALL
	edge.collision_mask = 0
	var corners := Iso.rect_poly(0.2, 0.2, size - 0.2, size - 0.2)
	for i in 4:
		var cs := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = corners[i]
		seg.b = corners[(i + 1) % 4]
		cs.shape = seg
		edge.add_child(cs)
	statics.add_child(edge)

	# doorsteps, nudged onto open ground
	for o in level["objects"]:
		for d in meta["objects"][o["type"]].get("doors", []):
			var p := Iso.to_screen(Vector2(o["x"] + d[0], o["y"] + d[1]))
			doors.append(p if is_free(p) else free_point_near(p, 20.0))

	if den.has("sprite"):
		var d0: Array = meta["objects"][level["reserve"]["den"]]["doors"][0]
		var dp := Iso.to_screen(den["corner"] + Vector2(d0[0], d0[1]))
		den.merge({"door": dp if is_free(dp) else free_point_near(dp, 20.0), "squad": level["reserve"]["squad"],
			"heat": 0.0, "rallied": false, "cause": "", "spawn_t": -1.0, "runner": null, "runner_cd": 0.0,
			"fight_t": 0.0, "alarm": dp})

	# keep only cover points that are reachable and off obstacles
	var good := PackedVector2Array()
	for p in cover_points:
		var c := _cell(p)
		if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
			good.append(p)
	cover_points = good

	for i in (0 if level.get("weather", "") == "snow" else 5):   # (no tumbleweed blows through the snow)
		var tw := Tumbleweed.new()
		tw.setup(self, Iso.to_screen(Vector2(randf_range(0, size), randf_range(0, size))))
		world.add_child(tw)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	var origin := Vector2(meta["ground"]["origin"][0], meta["ground"]["origin"][1])
	var gsize: Vector2 = tex(meta["ground"]["file"]).get_size() * tex_scale
	camera.limit_left = int(origin.x)
	camera.limit_top = int(origin.y)
	camera.limit_right = int(origin.x + gsize.x)
	camera.limit_bottom = int(origin.y + gsize.y)


func _add_enemy(kind: String, pos: Vector2, patrol: PackedVector2Array, facing_deg: float, overrides := {}) -> Enemy:
	var en := Enemy.new()
	world.add_child(en)
	en.setup(self, kind, pos, patrol, facing_deg, overrides)
	if not gangs.has(en.gang):
		gangs[en.gang] = _gang_state()
	en.died.connect(_on_enemy_died)
	enemies.append(en)
	return en


func _place_object(type: String, g: Vector2) -> Sprite2D:
	var m: Dictionary = meta["objects"][type]
	var fp := Vector2(m["footprint"][0], m["footprint"][1])
	var spr := Sprite2D.new()
	spr.texture = tex(m["file"])
	spr.centered = false
	spr.position = Iso.to_screen(g + fp * 0.5)
	spr.scale = Vector2.ONE * tex_scale
	spr.offset = ((Iso.to_screen(g) - spr.position) / tex_scale - Vector2(m["anchor"][0], m["anchor"][1])).round()
	if type in FLAT:
		spr.z_index = -1   # low enough to walk over: under whoever's crossing it
	world.add_child(spr)
	if level.has("reserve") and type == level["reserve"]["den"] and not den.has("sprite") \
			and not Engine.has_meta("no_reserve"):   # (tests of the street fight leave them indoors)
		den["sprite"] = spr
		den["corner"] = g
	if m.has("shutters"):
		var paints: Array = meta["shutter_paint"][m["paint"]]
		var c: Array = paints[Shutter.rng.randi() % paints.size()]
		for s in m["shutters"]:
			var sh := Shutter.new()
			sh.setup(self, spr, m, s, g, Color(c[0] / 226.0, c[1] / 226.0, c[2] / 226.0))
			spr.add_child(sh)
			shutters.append(sh)

	var made: Array[Shutter] = []
	for sh in shutters.slice(shutters.size() - m.get("shutters", []).size()):
		made.append(sh)
	_add_fixtures(m, spr, g, made)
	var collide: String = m["collide"]
	var rec := {"type": type, "g": g, "sprite": spr, "body": null, "cells": [], "covers": []}
	placed.append(rec)
	var prop := {}
	if m.get("fragile", false):
		var item := _add_fragile(type, Iso.to_screen(g + fp * 0.5), spr, m["states"].size(), FRAGILE_R[type])
		item["g"] = g
		item["hens"] = HENS_IN.get(type, 0)
		item["look0"] = [spr.texture, spr.offset]   # as it was, for whoever puts it right
	elif m.has("states"):
		prop = {"kind": type, "sprite": spr, "g": g, "fp": fp, "hp": PROP_HP[type], "state": 0,
			"cells": [], "covers": [], "body": null, "look0": [spr.texture, spr.offset]}
		props.append(prop)
	if collide != "none":
		var body := StaticBody2D.new()
		body.collision_layer = {"wall": Iso.LAYER_WALL, "cover": Iso.LAYER_COVER, "post": Iso.LAYER_POST}[collide]
		body.collision_mask = 0
		if collide == "wall":
			body.set_meta("building", spr)   # (for the bullet holes)
			body.set_meta("paint", m.get("paint", "wood"))
		for r in m["colliders"]:
			var x0: float = g.x + r[0]
			var y0: float = g.y + r[1]
			var x1: float = g.x + r[2]
			var y1: float = g.y + r[3]
			var poly := CollisionPolygon2D.new()
			poly.polygon = Iso.rect_poly(x0, y0, x1, y1)
			body.add_child(poly)
			var cells := _block_cells(x0, y0, x1, y1, 0.22)
			var covers: Array[Vector2] = []
			if collide != "post":
				covers = _add_cover_points(x0, y0, x1, y1, collide == "wall")
			rec["cells"].append_array(cells)
			rec["covers"].append_array(covers)
			if not prop.is_empty():
				prop["cells"].append_array(cells)
				prop["covers"].append_array(covers)
		statics.add_child(body)
		rec["body"] = body
		if not prop.is_empty():
			prop["body"] = body
			body.set_meta("prop", prop)
	if m["fade"]:
		if m.has("chunk") and int(m["chunk"][1]) == 0:
			_chunk_groups += 1   # a long thing's pieces fade as one (a boxcar, the engine)
		buildings.append({"sprite": spr, "x0": g.x, "y0": g.y, "x1": g.x + fp.x, "y1": g.y + fp.y,
			"group": _chunk_groups if m.has("chunk") else -buildings.size() - 1})
	return spr


func _block_cells(x0: float, y0: float, x1: float, y1: float, pad: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(int(floor((x0 - pad) * 2.0)), int(ceil((x1 + pad) * 2.0))):
		for j in range(int(floor((y0 - pad) * 2.0)), int(ceil((y1 + pad) * 2.0))):
			var c := Vector2i(i, j)
			if astar.is_in_boundsv(c):
				astar.set_point_solid(c, true)
				_solid[c] = _solid.get(c, 0) + 1
				out.append(c)
	return out


## Take a placed object out of the world's way (its collision, the cells it blocked,
## its cover) and, unless it's to go on being seen (a wagon driving off), its sprite.
func lift_object(rec: Dictionary, keep_sprite := false) -> void:
	if rec["body"] != null:
		rec["body"].queue_free()
		rec["body"] = null
		_unblock_cells(rec["cells"])
		rec["cells"] = []
		for p in rec["covers"]:
			cover_points.erase(p)
	if not keep_sprite and is_instance_valid(rec["sprite"]):
		rec["sprite"].queue_free()
	placed.erase(rec)


## The placed object of a kind with its corner nearest `g` (tiles), within `within`.
func placed_near(type: String, g: Vector2, within := 0.6) -> Dictionary:
	for rec in placed:
		if rec["type"] == type and rec["g"].distance_to(g) <= within:
			return rec
	return {}


## Free cells something no longer blocks (unless something else still does).
func _unblock_cells(cells: Array) -> void:
	for c in cells:
		_solid[c] = _solid.get(c, 1) - 1
		if _solid[c] <= 0:
			_solid.erase(c)
			astar.set_point_solid(c, false)


func _add_cover_points(x0: float, y0: float, x1: float, y1: float, wall: bool) -> Array[Vector2]:
	var o := 0.55
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var pts := [Vector2(cx, y0 - o), Vector2(cx, y1 + o), Vector2(x0 - o, cy), Vector2(x1 + o, cy)]
	if wall:
		pts += [Vector2(x0 - o, y0 - o), Vector2(x1 + o, y0 - o), Vector2(x0 - o, y1 + o), Vector2(x1 + o, y1 + o)]
	var out: Array[Vector2] = []
	for p in pts:
		cover_points.append(Iso.to_screen(p))
		out.append(Iso.to_screen(p))
	return out


func _spawn_actors() -> void:
	player = Player.new()
	world.add_child(player)
	var start := Vector2(level["player"]["x"], level["player"]["y"])
	if _args.has("at"):
		var xy: PackedStringArray = _args["at"].split(",")
		start = Vector2(float(xy[0]), float(xy[1]))
	player.setup(self, Iso.to_screen(start))
	player.sticks = int(level_entry.get("dynamite", 0))
	if level_entry.has("count"):
		level["enemies"] = shuffled_gang(level, int(level_entry["count"]), usable_post)
	for e in level["enemies"]:
		var patrol := PackedVector2Array()
		if e.has("patrol"):
			for p in e["patrol"]:
				patrol.append(Iso.to_screen(Vector2(p[0], p[1])))
		var overrides := {}
		for key in e:
			if not key in ["kind", "x", "y", "patrol", "facing"]:
				overrides[key] = e[key]
		_add_enemy(e["kind"], Iso.to_screen(Vector2(e["x"], e["y"])), patrol, e.get("facing", 90.0), overrides)
	if not Engine.has_meta("no_civilians"):
		for c in level.get("civilians", []):
			var cv := Civilian.new()
			world.add_child(cv)
			var overrides := {}
			for key in c:
				if not key in ["kind", "x", "y", "facing"]:
					overrides[key] = c[key]
			cv.setup(self, c["kind"], Iso.to_screen(Vector2(c["x"], c["y"])), c.get("facing", 90.0), overrides)
			cv.died.connect(_on_civilian_died)
			civilians.append(cv)
		# couples: the first of each pair leads, the other walks on his arm
		var couples := {}
		for cv in civilians:
			if cv.tdata.has("couple"):
				var k: Variant = cv.tdata["couple"]
				if couples.has(k):
					cv.partner = couples[k]
					couples[k].partner = cv
				else:
					couples[k] = cv
					cv.leads = true
	for d in level.get("dead", []):   # killed before he got here
		var body := Corpse.new()
		world.add_child(body)
		body.setup(self, d)
		lay_pool(body)
	for p in level.get("pickups", []):   # lying about for the taking
		_drop_ammo(p["kind"], Iso.to_screen(Vector2(p["x"], p["y"])))
	for d in level.get("smoke", []):
		var sm := Smoulder.new()
		sm.setup(self, d)
		add_child(sm)
	if level_entry.has("hanging") and not Engine.has_meta("no_hanging"):
		hanging = Hanging.new()
		hanging.setup(self, level_entry["hanging"])
		add_child(hanging)
	if level_entry.has("captive") and not Engine.has_meta("no_captive"):
		captive = Captive.new()
		captive.setup(self, level_entry["captive"])
		add_child(captive)
	if level.has("mg"):
		mgun = MGun.new()
		mgun.setup(self, Vector2(level["mg"][0], level["mg"][1]))
		world.add_child(mgun)
	if level.has("plunger"):
		minefield = Minefield.new()
		minefield.setup(self, level)
		world.add_child(minefield)
	if level.has("strongbox"):
		strongbox = Strongbox.new()
		world.add_child(strongbox)
		strongbox.setup(self, Vector2(level["strongbox"][0], level["strongbox"][1]), Vector2(level["horse"][0], level["horse"][1]))
	if level_entry.has("cargo") and level.has("cargo"):
		cargo = Cargo.new()
		add_child(cargo)
		cargo.setup(self, level_entry["cargo"])
	player.died.connect(_on_player_died)
	player.make_ghost(ghost_layer, Color(0.92, 0.95, 1.0, 0.6))
	for en in enemies:
		en.make_ghost(ghost_layer, GHOST_THREAT if en.revealed else GHOST_TOWN)
	for cv in civilians:
		cv.make_ghost(ghost_layer, GHOST_TOWN)
	camera.position = player.global_position


func _build_overlay() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = POST_SHADER
	post.material = mat
	post_layer.add_child(post)
	if level.get("weather", "") == "snow":   # Silencio: cloud, cold and flat, and the snow coming down out of it
		mat.set_shader_parameter("tint", Vector3(0.97, 1.0, 1.05))
		mat.set_shader_parameter("sat", 0.62)
		mat.set_shader_parameter("contrast", 0.94)
		mat.set_shader_parameter("lift", 0.05)
		snowfall = Snowfall.new()
		snowfall.setup(self)
		add_child(snowfall)
		footprints = Footprints.new()
		footprints.setup(self)
		add_child(footprints)
		drifts = Drifts.new()
		drifts.setup(self)
		add_child(drifts)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS   # (the menu's drawn and heard over a paused town)
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud_layer.add_child(hud)
	fit_view()
	if not get_viewport().size_changed.is_connected(fit_view):
		get_viewport().size_changed.connect(fit_view)


## The camera's zoom and the HUD's scale for a window `px` big: whole numbers both,
## the zoom the least that keeps the view inside VIEW_CAP (but not under VIEW_ZOOM,
## unless the window's too small to show anything at that), the HUD the most that
## still fits its page.
static func view_fit(px: Vector2) -> Vector2i:
	var zoom := ceili(maxf(px.x / VIEW_CAP.x, px.y / VIEW_CAP.y))
	zoom = maxi(zoom, clampi(floori(px.y / 240.0), 1, VIEW_ZOOM))
	var page := maxi(1, floori(minf(px.x / HUD_PAGE.x, px.y / HUD_PAGE.y)))
	return Vector2i(zoom, page)


## The window's been opened or resized: zoom the camera and lay out the HUD to it.
func fit_view() -> void:
	if camera == null or hud == null:
		return
	var px := get_viewport_rect().size
	var fit := view_fit(px)
	camera.zoom = Vector2.ONE * fit.x
	hud_layer.scale = Vector2.ONE * fit.y
	hud.page = (px / fit.y).floor()
	(post.material as ShaderMaterial).set_shader_parameter("grain", hud.page)


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	_sway(delta)
	if state == "title":
		title_t += delta   # frame time, not the wall clock: a slow load doesn't skip the title
		if title_t > 5.5 and not _args.has("freeze"):
			_to_levels()
	if down_slow > 0.0:
		down_slow -= delta / maxf(Engine.time_scale, 0.01)
		if down_slow <= 0.0 and state == "play":
			Engine.time_scale = 1.0
	if closeup_left > 0.0:
		closeup_left -= delta / maxf(Engine.time_scale, 0.01)
		if closeup_left <= 0.0:
			closeup_left = 0.0
			if state == "play":
				Engine.time_scale = 1.0
			hud.hide_eyes()

	if player:
		var look := (get_global_mouse_position() - player.global_position) * 0.35
		var target := player.global_position + look.limit_length(130.0) + Vector2(0, -12)
		camera.position = camera.position.lerp(target, clamp(delta * 4.0, 0.0, 1.0))
	shake = max(0.0, shake - delta * 18.0)
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round()

	hurt_fx = max(0.0, hurt_fx - delta * 2.0)
	var mat := post.material as ShaderMaterial
	mat.set_shader_parameter("time_s", now / 1000.0)
	if snowfall:   # a squall: the white closing in, and the wind howling
		mat.set_shader_parameter("fog", snowfall.storm)
		wind_player.volume_db = -12.0 + 9.0 * snowfall.storm
	mat.set_shader_parameter("hurt", hurt_fx)
	if player and player.down:
		# the colour going out of it as he bleeds, and his heart, slowing
		var bled: float = player.down_t / Player.STAND_BLEED
		mat.set_shader_parameter("desat", 0.35 + 0.5 * bled)
		heart_t -= delta
		if heart_t <= 0.0 and state == "play":
			heart_t = lerpf(0.9, 1.7, bled)
			sfx("heart", null, -4.0, 0.0)
			hurt_fx = maxf(hurt_fx, 0.45)
	elif state == "play" and player:
		mat.set_shader_parameter("desat", 0.0)
	if state == "lost":
		var t: float = clamp((now - end_time) / 1500.0, 0.0, 1.0)
		mat.set_shader_parameter("desat", t * 0.8)
		if now - end_time > 1500:
			Engine.time_scale = 1.0

	_update_fades(delta)
	_opening_line()
	if state == "play":
		for sh in shutters:
			sh.tick(delta)
	_maybe_screenshot(now)


## The level's line (its "line": the stranger's, from "Vamos a matar, compañeros"),
## said once, a moment into the fight, the title gone.
func _opening_line() -> void:
	if said_line or state != "play" or not level_entry.has("line"):
		return
	var l: Dictionary = level_entry["line"]
	if clock < float(l.get("at", 2.5)):
		return
	said_line = true
	if l.get("who", "stranger") == "stranger":
		player.say(l["text"])


func _update_fades(delta: float) -> void:
	if not player:
		return
	# A building fades when it hides the hero or when he's aiming at it. Anyone else
	# it hides shows through as a silhouette.
	var g := Iso.to_grid(player.global_position)
	var cursor := get_global_mouse_position()
	var targets := {}   # by group: one piece of a car seen through, the whole car
	for b in buildings:
		var behind: bool = g.x < b["x1"] and g.y < b["y1"] and not (g.x > b["x0"] and g.y > b["y0"])
		var hides_hero := behind and _covers(b, player.global_position)
		var target := 0.35 if hides_hero or (state == "play" and _covers_point(b, cursor)) else 1.0
		targets[b["group"]] = minf(targets.get(b["group"], 1.0), target)
	for b in buildings:
		var spr: Sprite2D = b["sprite"]
		spr.modulate.a = move_toward(spr.modulate.a, targets[b["group"]], delta * 4.0)
	_fade_frame += 1
	if _fade_frame % 3 != 0:
		return   # who's hidden behind what: 20 times a second is plenty for a silhouette
	var actors: Array = [player]
	actors.append_array(enemies)
	for c in civilians:
		if not c.gone():
			actors.append(c)
	for a in actors:
		a.occluded = false
		if not a.alive:
			continue
		var ag := Iso.to_grid(a.global_position)
		for b in buildings:
			var spr: Sprite2D = b["sprite"]
			if spr.modulate.a < 0.6:
				continue   # already see-through
			if ag.x < b["x1"] and ag.y < b["y1"] and not (ag.x > b["x0"] and ag.y > b["y0"]) \
					and _covers(b, a.global_position):
				a.occluded = true
				break


## Is this point on the building's artwork (not its shadow)?
func _covers_point(b: Dictionary, p: Vector2) -> bool:
	var spr: Sprite2D = b["sprite"]
	if not b.has("image"):
		b["image"] = spr.texture.get_image()
	var img: Image = b["image"]
	var ip := Vector2i(((p - (spr.position + spr.offset * tex_scale)) / tex_scale))
	return ip.x >= 0 and ip.y >= 0 and ip.x < img.get_width() and ip.y < img.get_height() \
		and img.get_pixelv(ip).a > 0.9


## Does the building's actual artwork (not its shadow) cover the hero's body?
func _covers(b: Dictionary, feet: Vector2) -> bool:
	var spr: Sprite2D = b["sprite"]
	if not b.has("image"):
		b["image"] = spr.texture.get_image()
	var img: Image = b["image"]
	var origin := spr.position + spr.offset * tex_scale
	for dy in [-4.0, -14.0, -26.0]:
		var p: Vector2 = ((feet + Vector2(0, dy)) - origin) / tex_scale
		var ip := Vector2i(p)
		if ip.x >= 0 and ip.y >= 0 and ip.x < img.get_width() and ip.y < img.get_height():
			if img.get_pixelv(ip).a > 0.9:
				return true
	return false


func _maybe_screenshot(now: int) -> void:
	if _shot_done or not _args.has("shot"):
		return
	if _args.has("alert") and state == "play" and not alerted_once and now - start_time > 800:
		on_enemy_alert(enemies[0], true)
	if _args.has("rattle") and state == "play" and now - start_time > 600 and not _rattled:
		_rattled = true
		for e in enemies:
			e.near_miss(player.global_position)
	if now - start_time > float(_args.get("shot-time", "2.5")) * 1000.0:
		_shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args["shot"])
		get_tree().quit()


# ------------------------------------------------------------------ queries

var counts := {"rays": 0, "paths": 0, "path_us": 0}
var _fade_frame := 0
const PLANS_A_FRAME := 2   # hunts planned in one frame; the rest wait their turn (a frame or two)
var plans_left := PLANS_A_FRAME
var rescue_cd := 0.0
# The gang's alarm: sustained gunfire, men going down and survivors' news build it
# up, and the men far from the fight (who can't know where the stranger is) answer
# by stages: uneasy at their posts; then each group sends a pair to look (and more
# later); then, once a third of the gang is down, the rest fall back to a holdout
# away from the fight and dig in.
const UNEASY := 12.0
const SEND := 35.0
const SEND_EVERY := 30.0       # s before each group sends another pair
const FORTIFY_LOSS := 0.33     # of the gang down: time to fall back
const GROUP := 220.0           # px: men this close together are one post
const FAR := 350.0             # px from the fight: out of it
# Two gangs in one town (Silencio's hunters and outlaws: a type's "gang") keep
# each their own alarm, their own losses, their own holdout and their own head.
# Trouble at the other end of town puts a gang on edge, no more: it watches its
# own ground (OTHER_END: uneasy, never sending men out or falling back), and a
# leader's death breaks only his own. Everywhere else there's the one gang, "",
# whose state these names below are.
const OTHER_END := SEND - 5.0
var gangs := {"": _gang_state()}
var alarm_cd := 0.0
var alarm: float:
	get: return gangs[""]["alarm"]
	set(v): gangs[""]["alarm"] = v
var alarm_stage: int:
	get: return gangs[""]["stage"]
	set(v): gangs[""]["stage"] = v
var send_cd: float:
	get: return gangs[""]["send_cd"]
	set(v): gangs[""]["send_cd"] = v
var fallen: int:               # dead or downed
	get: return gangs[""]["fallen"]
	set(v): gangs[""]["fallen"] = v
var holdout: Dictionary:
	get: return gangs[""]["holdout"]
	set(v): gangs[""]["holdout"] = v


static func _gang_state() -> Dictionary:
	return {"alarm": 0.0, "stage": 0, "send_cd": 0.0, "fallen": 0, "holdout": {}, "leaderless": false,
		"seen": false, "his_guns": {}, "dug_in": false, "push_cd": 0.0}


## The gang a man's in ("" if the level has the one).
static func gang_of(a: Node) -> String:
	return a.gang if a is Enemy else ""


## The gang whose men are nearest this spot: whose trouble it is.
func gang_near(at: Vector2) -> String:
	var best := ""
	var best_d := INF
	for e in enemies:
		if e.alive and e.global_position.distance_to(at) < best_d:
			best_d = e.global_position.distance_to(at)
			best = e.gang
	return best


# ------------------------------------------------------------------ the truce

# Silencio's two gangs keep a truce till the thaw. Break it and they're at war: each
# shoots the other's men on sight and pushes for the middle of town (see
# Enemy._feuding), till a gang that's lost a third of its men falls back to its
# holdout and digs in. The stranger's still everyone's enemy. It isn't only a fight
# down main street: each gang's "lines" are its own edge of nobody's ground on main
# street and, round the backs, a flank on the north and the south streets, pushed
# deep towards the other gang's end; a gang sends its pushes up each in turn, so
# the fighting spreads, and one flank getting round can turn it.
#
# What breaks it: the outlaws missing their gold (it can only be the hunters), or a
# gang finding one of its own dead with a reason to think the others did it: he's
# lying on their ground (the map's "turf"), or he was shot with a gun only they
# carry and the gang hasn't seen the stranger with one, or nobody else is in town
# to have done it (they haven't seen the stranger at all). Seen, and with nothing
# pointing elsewhere, it's the stranger they blame. Trigger happy: once is enough.
# And the other gang's men seen on their ground with guns out (chasing the stranger
# in there, say): if the gang hasn't seen him, it can only be an attack.
var war := false
const DIG_IN := 0.33        # of a gang down: it falls back to its holdout and holds it
const PUSH_EVERY := 12.0    # s between a gang sending men up to the middle
const PUSH_MEN := 3


## Where a gang pushes up to, by turns: main street, then each flank (the map's
## "lines": one [x, y] or a list of them). `dice` picks one at random instead.
func war_line(g: String, dice: RandomNumberGenerator = null) -> Vector2:
	var lines: Array = level.get("lines", {}).get(g, [level["center"]["x"], level["center"]["y"]])
	if not lines[0] is Array:
		lines = [lines]
	var i := 0
	if dice:
		i = dice.randi_range(0, lines.size() - 1)
	else:
		i = gangs[g].get("push_i", 0) % lines.size()
		gangs[g]["push_i"] = i + 1
	return Iso.to_screen(Vector2(lines[i][0], lines[i][1]))


## Would these two shoot each other? Only at war, and of different gangs.
func at_war(a: Actor, b: Actor) -> bool:
	return war and is_instance_valid(a) and is_instance_valid(b) and a is Enemy and b is Enemy \
		and a.gang != b.gang and a.gang != "" and b.gang != ""


func other_gang(g: String) -> String:
	for o in level.get("gangs", []):
		if o != g:
			return o
	return ""


## Guns only this gang carries (what its men took the field with), not the other.
func gang_guns(g: String) -> Array:
	var mine := {}
	var theirs := {}
	for e in enemies:
		for k in e.loadout:
			if e.gang == g:
				mine[k] = true
			elif e.gang != "":
				theirs[k] = true
	return mine.keys().filter(func(k): return not theirs.has(k))


func on_turf(at: Vector2, g: String) -> bool:
	var r: Array = level.get("turf", {}).get(g, [])
	if r.is_empty():
		return false
	var gp := Iso.to_grid(at)
	return gp.x >= r[0] and gp.y >= r[1] and gp.x <= r[2] and gp.y <= r[3]


## A man of this gang has the stranger in sight: they know there's someone else in
## town now, and what he's carrying.
func gang_sees_him(g: String) -> void:
	var gs: Dictionary = gangs[g]
	gs["seen"] = true
	if player and player.weapon:
		gs["his_guns"][player.weapon.kind] = true


## One of their own found dead: whose doing was it?
func weigh_death(finder: Enemy, dead: Enemy) -> void:
	if war or not level.has("turf") or dead.gang == "" or finder.gang != dead.gang:
		return
	var g := dead.gang
	var them := other_gang(g)
	var gs: Dictionary = gangs[g]
	var why := ""
	if on_turf(dead.global_position, them):
		why = "the %s find their man dead on the %s' ground!  They blame the %s!" % [g, them, them]
	elif dead.killed_with in gang_guns(them) and not gs["his_guns"].has(dead.killed_with):
		why = "Shot with %s gun!  The %s blame the %s for murder!" % [
			"a hunter's" if them == "hunters" else "an outlaw's", g, them]
	elif not gs["seen"]:
		why = "Nobody else in town to do it!  The %s blame the %s for murder!" % [g, them]
	if why != "":
		stats["blamed"] = why
		start_war(why[0].to_upper() + why.substr(1))


## Men of one gang on the other's ground, hunting (fighting, searching, going to look,
## in a hurry about something), seen there by one of the other gang: if that gang
## hasn't seen the stranger, they've no idea who it is they're after. It's an attack.
func _trespass_tick() -> void:
	for h in enemies:
		if not h.alive or h.gang == "" or not (h.st in [Enemy.St.COMBAT, Enemy.St.SEARCH, Enemy.St.INVESTIGATE] or h.reaction != ""):
			continue
		var them := other_gang(h.gang)
		if them == "" or gangs[them]["seen"] or not on_turf(h.global_position, them):
			continue
		for o in enemies:
			if o.alive and o.gang == them and o.visibility_of(h.global_position, false) > 0.0:
				stats["blamed"] = "trespass"
				o.foe = h
				start_war("%s on the %s' ground, guns out!  The %s take it for an attack!" % [
					h.gang[0].to_upper() + h.gang.substr(1), them, them])
				return


func start_war(why: String) -> void:
	if war:
		return
	war = true
	stats["war"] = 1
	hud.banner(why)
	hud.toast("The truce is broken: the street war is on!")
	sfx("sting", null, -6.0, 0.0)
	for g in gangs:
		gangs[g]["push_cd"] = 2.0
	var named: Array = level.get("gangs", [])
	for i in named.size():
		gangs[named[i]]["push_i"] = 1 + i   # (round a flank first, each gang its own: then main street)


## The war, every half second: a gang that's lost too many digs in; one that hasn't
## sends a few men up towards the middle of town.
func _war_tick(delta: float) -> void:
	for g in level.get("gangs", []):
		var gs: Dictionary = gangs[g]
		var men: Array = enemies.filter(func(e): return e.gang == g)
		var up: Array = men.filter(func(e): return e.alive and not e.downed and e.st != Enemy.St.COMBAT)
		if not gs["dug_in"] and gs["fallen"] >= maxi(3, ceili(men.size() * DIG_IN)):
			gs["dug_in"] = true
			var holdouts: Array = level.get("holdouts", []).filter(func(h): return h.get("gang", "") == g)
			if gs["holdout"].is_empty() and not holdouts.is_empty():
				var h: Dictionary = holdouts[0]
				gs["holdout"] = {"name": h["name"], "at": Iso.to_screen(Vector2(h["x"], h["y"])), "taken": []}
			if not gs["holdout"].is_empty():
				hud.banner("The %s fall back to the %s and dig in!" % [g, gs["holdout"]["name"]])
				for e in up:
					if e.alarm_role != "fortified":
						e.fortify(_holdout_spot(e, gs["holdout"]), Iso.to_screen(Vector2(level["center"]["x"], level["center"]["y"])))
			continue
		if gs["dug_in"]:
			continue
		gs["push_cd"] -= delta
		if gs["push_cd"] > 0.0:
			continue
		gs["push_cd"] = PUSH_EVERY
		var line := war_line(g)   # (where it goes up to: main street, or round a flank)
		var free: Array = up.filter(func(e): return e.foe == null and e.reaction == "" and e.alarm_role == "" \
			and not e.tdata.get("boss", false) and not e.kind in ["sharpshooter", "woodsman"])
		free.sort_custom(func(a, b): return a.global_position.distance_to(line) < b.global_position.distance_to(line))
		for e in free.slice(0, PUSH_MEN):
			e.start_investigate(free_point_near(line, 50.0, Enemy.feud_rng), true)


## Living men of this gang.
func alive_in(g: String) -> int:
	return enemies.filter(func(e): return e.alive and e.gang == g).size()

# (for tools/profile: how hard the queries are worked)


func ray(from: Vector2, to: Vector2, mask: int, exclude: Array[RID] = [], areas := false) -> Dictionary:
	counts["rays"] += 1
	var q := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	q.collide_with_areas = areas
	q.collide_with_bodies = true
	return get_world_2d().direct_space_state.intersect_ray(q)


## True if `to` can be seen from `from`. Walls always block; low cover blocks only a
## crouched (or lying) target, and is ignored right next to the viewer.
func line_of_sight(from: Vector2, to: Vector2, target_low: bool) -> bool:
	var exclude: Array[RID] = []
	for i in 6:
		var hit := ray(from, to, Iso.LAYER_WALL | Iso.LAYER_COVER, exclude)
		if hit.is_empty():
			return true
		var col: CollisionObject2D = hit["collider"]
		if col.collision_layer & Iso.LAYER_WALL:
			return false
		var hp: Vector2 = hit["position"]
		if target_low and hp.distance_to(from) > 20.0:
			return false
		exclude.append(col.get_rid())
	return true


func clear_path(a: Vector2, b: Vector2) -> bool:
	var mask := Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST
	var side := (b - a).orthogonal().normalized() * 4.0
	return ray(a + side, b + side, mask).is_empty() and ray(a - side, b - side, mask).is_empty()


func _cell(p: Vector2) -> Vector2i:
	var g := Iso.to_grid(p) * 2.0
	return Vector2i(clampi(int(floor(g.x)), 0, size * 2 - 1), clampi(int(floor(g.y)), 0, size * 2 - 1))


func _cell_center(c: Vector2i) -> Vector2:
	return Iso.to_screen(Vector2(c.x + 0.5, c.y + 0.5) * 0.5)


func _nearest_free(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
					return n
	return c


## A walkable route. `avoid` is a list of routes to steer clear of: cells along them
## (away from both ends) cost more, so the pathfinder prefers another way round.
func find_path(from: Vector2, to: Vector2, avoid: Array = [], penalty := 3.5) -> PackedVector2Array:
	counts["paths"] += 1
	var a := _nearest_free(_cell(from))
	var b := _nearest_free(_cell(to))
	var touched: Array[Vector2i] = []
	for route in avoid:
		_weigh_route(route, from, to, touched, penalty)
	var t_path := Time.get_ticks_usec()
	var ids := astar.get_id_path(a, b)
	counts["path_us"] += Time.get_ticks_usec() - t_path
	for c in touched:
		astar.set_point_weight_scale(c, 1.0)
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(_cell_center(id))
	if pts.size() > 0 and b == _cell(to):
		pts[pts.size() - 1] = to
	# string-pull: only the turns of the grid path matter; from each point we keep
	# going on to the next turn while it can be walked to directly (one pass, so a
	# long route costs a ray or two a turn, not a ray for every later point)
	var turns := PackedVector2Array()
	for k in pts.size():
		if k == 0 or k == pts.size() - 1:
			turns.append(pts[k])
		elif (pts[k] - pts[k - 1]).normalized().dot((pts[k + 1] - pts[k]).normalized()) < 0.99:
			turns.append(pts[k])
	var out := PackedVector2Array()
	var cur := from
	var i := 0
	while i < turns.size():
		var j := i
		while j + 1 < turns.size() and clear_path(cur, turns[j + 1]):
			j += 1
		out.append(turns[j])
		cur = turns[j]
		i = j + 1
	return out


func _weigh_route(route: PackedVector2Array, from: Vector2, to: Vector2, touched: Array[Vector2i], penalty: float) -> void:
	# the cells along it first (the samples overlap a lot), then each one weighed once
	var along := {}
	var prev := from
	for p in route:
		var steps := int(prev.distance_to(p) / 6.0) + 1
		for k in steps:
			var q := prev.lerp(p, float(k) / steps)
			if q.distance_to(from) < 40.0 or q.distance_to(to) < 50.0:
				continue
			along[_cell(q)] = true
		prev = p
	# a wide band, so a parallel lane down the same street still counts as taken
	var w := size * 2
	var seen := PackedByteArray()
	seen.resize(w * w)
	for c in along:
		for x in range(maxi(c.x - 3, 0), mini(c.x + 4, w)):
			for y in range(maxi(c.y - 3, 0), mini(c.y + 4, w)):
				if seen[x * w + y]:
					continue
				seen[x * w + y] = 1
				var n := Vector2i(x, y)
				if not astar.is_point_solid(n) and astar.get_point_weight_scale(n) < 2.0:
					astar.set_point_weight_scale(n, penalty)
					touched.append(n)


# Who is hunting the stranger, by which route: {target, path, hunter, role, at}.
var hunts: Array = []


## A bandit setting off after the stranger's last position. If comrades who set
## off from near him are already going in the way he would, he may (by his type's
## `flank` chance) go round to come in from another side, to a point just past the
## spot, cutting off the escape, rather than follow them in single file. Detours much
## longer than the straight route aren't worth it.
func plan_hunt(e: Enemy, target: Vector2) -> Dictionary:
	hunts = hunts.filter(func(h): return is_instance_valid(h["hunter"]) and h["hunter"].alive \
		and h["hunter"] != e and clock - float(h["at"]) < 12.0)
	var me := e.global_position
	var direct := find_path(me, target)
	var my_side := approach_dir(direct, target)
	var ahead := hunts.filter(func(h): return h["target"].distance_to(target) < 100.0 \
		and h["from"].distance_to(me) < 220.0 \
		and abs(my_side.angle_to(approach_dir(h["path"], target))) < deg_to_rad(50.0))
	var route := direct
	var role := "direct"
	var goal := target
	if not ahead.is_empty() and randf() < float(e.tdata.get("flank", 0.6)):
		goal = target - my_side.rotated(randf_range(-0.5, 0.5)) * 65.0   # the far side
		var g := Iso.to_grid(goal)
		if g.x < 1.0 or g.y < 1.0 or g.x > size - 1.0 or g.y > size - 1.0 or not is_free(goal):
			goal = free_point_near(goal, 30.0)
		var avoid: Array = [direct]
		for h in ahead:
			avoid.append(h["path"])
		# a gentle nudge first, then harder; only a way in from another side counts
		for penalty in [3.5, 9.0]:
			var round_ := find_path(me, goal, avoid, penalty)
			if abs(approach_dir(round_, target).angle_to(my_side)) > deg_to_rad(50.0) \
					and _length(me, round_) < _length(me, direct) * 1.8 + 60.0:
				route = round_
				role = "flank"
				break
		if role != "flank":
			goal = target
	hunts.append({"target": target, "from": me, "path": route, "hunter": e, "role": role, "at": clock})
	return {"path": route, "role": role, "goal": goal}


## The direction a route closes in on its target from.
func approach_dir(route: PackedVector2Array, target: Vector2) -> Vector2:
	for k in range(route.size() - 1, -1, -1):
		if route[k].distance_to(target) > 55.0:
			return (route[k] - target).normalized()
	return Vector2.ZERO


func _length(from: Vector2, route: PackedVector2Array) -> float:
	var total := 0.0
	var prev := from
	for p in route:
		total += prev.distance_to(p)
		prev = p
	return total


func free_point_near(p: Vector2, radius: float, dice: RandomNumberGenerator = null) -> Vector2:
	for i in 12:
		var q := p + (Vector2.from_angle(dice.randf() * TAU) * dice.randf_range(radius * 0.3, radius) if dice
			else Vector2.from_angle(randf() * TAU) * randf_range(radius * 0.3, radius))
		var c := _cell(q)
		if not astar.is_point_solid(c):
			return q
	return p


func find_cover(from: Vector2, threat: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := 1e9
	for c in cover_points:
		var d := from.distance_to(c)
		if d > 170.0 or d >= bd or c.distance_to(threat) < 70.0:
			continue
		if line_of_sight(threat, c, true):
			continue
		bd = d
		best = c
	return best


func enemy_under(screen_point: Vector2) -> Enemy:
	var best: Enemy = null
	var bd := 1e9
	for e in enemies:
		if not e.alive and not e.downed:
			continue
		var d := e.global_position.distance_to(screen_point)
		if e.downed:   # lying in the dirt: anywhere along him
			var l: PackedVector2Array = e.lie_line()
			var p := screen_point + Vector2(0, 2)   # (the body has a little height to it)
			d = Geometry2D.get_closest_point_to_segment(p, l[0], l[1]).distance_to(p)
			if d > 9.0:
				continue
		elif not Rect2(e.global_position + Vector2(-8, -36), Vector2(16, 38)).has_point(screen_point):
			continue
		if d < bd:
			bd = d
			best = e
	return best


# ------------------------------------------------------------------ events

const FLANKS := [0.0, 0.7, -0.7, 1.2, -1.2, 0.35, -0.35, 0.95, -0.95]
var _flank_i := 0


## Flank angles handed out in turn, so bandits joining a fight fan out to the sides.
func next_flank() -> float:
	_flank_i += 1
	return FLANKS[(_flank_i - 1) % FLANKS.size()]


func ally_in_line(shooter: Enemy, a: Vector2, b: Vector2) -> bool:
	return blocking_ally(shooter, a, b) != null


## The comrade (or townsman) standing in the line of fire from a to b, if any.
func blocking_ally(shooter: Enemy, a: Vector2, b: Vector2) -> Actor:
	var people: Array[Actor] = []
	people.append_array(enemies)
	for c in civilians:
		if not c.gone():
			people.append(c)
	for e in people:
		if e == shooter or not e.alive:
			continue
		var p := Geometry2D.get_closest_point_to_segment(e.global_position, a, b)
		if p.distance_to(e.global_position) < 12.0 and p.distance_to(b) > 8.0:
			return e
	return null


## A reachable spot about `dist` away from the threat, for a bandit running off.
func point_away(from: Vector2, threat: Vector2, dist: float) -> Vector2:
	var away := (from - threat).normalized()
	if away == Vector2.ZERO:
		away = Vector2.from_angle(randf() * TAU)
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var p := from + away.rotated(a + randf_range(-0.2, 0.2)) * dist
		var g := Iso.to_grid(p)
		if g.x > 1.0 and g.y > 1.0 and g.x < size - 1.0 and g.y < size - 1.0 and is_free(p):
			return p
	return free_point_near(from, dist * 0.5)


## A cover point near `near` that hides a crouching man from `threat` but lets
## him shoot standing up: the place to duck behind and pop up from.
func find_fighting_cover(me: Vector2, threat: Vector2, near: Vector2, keep: Vector2, taken: Array) -> Vector2:
	var best := Vector2.INF
	var bd := 1e9
	for c in cover_points:
		var dt := c.distance_to(threat)
		if dt < keep.x * 0.8 or dt > keep.y * 1.2:
			continue
		var score := c.distance_to(near) + c.distance_to(me) * 0.5
		if score > 220.0 or score >= bd:
			continue
		var clash := false
		for o in taken:
			if o.distance_to(c) < 24.0:
				clash = true
				break
		if clash:
			continue
		if line_of_sight(threat, c, true) or not line_of_sight(c, threat, false):
			continue
		bd = score
		best = c
	return best


func taken_positions(except: Enemy) -> Array:
	var out := []
	for e in enemies:
		if e != except and e.alive and e.fight_pos != Vector2.INF:
			out.append(e.fight_pos)
	return out


func report_sighting(pos: Vector2) -> void:
	seen_at = clock
	seen_pos = pos


## The man the stranger's come to cut loose, if the level has one: the gallows' or
## the pole's (both take the knife the same way).
func rescue() -> Node:
	return hanging if hanging else captive


## Held to his place by a man to kill: the hangman at the lever, the captor counting.
func holding(e: Enemy) -> bool:
	return hanging != null and hanging.holds(e) or captive != null and captive.holds(e)


## Seconds since anyone in the gang saw or heard the stranger.
func staleness() -> float:
	return clock - seen_at


func _physics_process(delta: float) -> void:
	if state != "play":
		return
	clock += delta
	plans_left = PLANS_A_FRAME
	rescue_cd -= delta
	if rescue_cd <= 0.0:
		rescue_cd = 0.5
		_send_rescuers()
	alarm_cd -= delta
	if alarm_cd <= 0.0:
		alarm_cd = 0.5
		_gang_alarm(0.5)
		if war:
			_war_tick(0.5)
		elif level.has("turf"):
			_trespass_tick()
	if player.down:
		finish_cd -= delta
		if finish_cd <= 0.0:
			finish_cd = 3.0
			call_finishers()
	innocent_t = maxf(0.0, innocent_t - delta)
	dyn_cd = maxf(0.0, dyn_cd - delta)
	_pick_up_guns()
	_update_den(delta)
	_quiet = clock - last_gunfire
	for e in enemies:
		if e.alive and e.st == Enemy.St.COMBAT:
			_quiet = 0.0
			break
	if posse:
		posse.update(delta)
	# Knowledge gone stale: the shooting dies down to the odd harassing shot at his
	# last known position from one bandit at a time, then stops altogether.
	var stale := staleness()
	if stale < FRESH or stale > HARASS_UNTIL:
		return
	harass_cd -= delta
	if harass_cd > 0.0:
		return
	harass_cd = HARASS_EVERY * randf_range(0.8, 1.3)
	var shooters: Array[Enemy] = []
	for e in enemies:
		if e.alive and e.st == Enemy.St.COMBAT and e.reaction == "" and not e.weapon.is_reloading() \
				and e.global_position.distance_to(seen_pos) < e.weapon.d["range"] * 0.8 \
				and not ally_in_line(e, e.global_position, seen_pos) \
				and line_of_sight(e.global_position, seen_pos, false):
			shooters.append(e)
	if not shooters.is_empty():
		shooters.pick_random().harass(seen_pos)


func is_free(p: Vector2) -> bool:
	return not astar.is_point_solid(_cell(p))


## A townsfolk type, the same way; 'palettes_from' borrows a bandit type's palettes.
func civilian_type(kind: String, overrides := {}) -> Dictionary:
	var c: Dictionary = enemy_data["civilians"]
	var t: Dictionary = c["defaults"].duplicate(true)
	t.merge(c["types"][kind], true)
	t.merge(overrides, true)
	if t.has("palettes_from"):
		t["palettes"] = enemy_data["types"][t["palettes_from"]]["palettes"]
	return t


## Where a frightened townsman runs: the nearest doorway that doesn't take him
## towards the shooting, or the edge of town if that's nearer.
func refuge_for(from: Vector2, threat: Vector2) -> Vector2:
	var away := (from - threat).normalized()
	var best := Vector2.INF
	var best_score := INF
	var haven := Vector2.INF   # the sister in the chapel doorway, calling folk in
	for c in civilians:
		if c.sister and c.alive and c.st == Civilian.St.SHELTER:
			haven = c.home
	for d in doors:
		var to := d - from
		var score := to.length()
		if haven != Vector2.INF and d.distance_to(haven) < 30.0 and from.distance_to(d) < SANCTUARY:
			score -= 150.0
		if to.length() > 8.0 and to.normalized().dot(away) < -0.3 and threat.distance_to(d) < from.distance_to(d):
			score += 400.0   # past the gunman: only if there's nothing else
		score += maxf(0.0, 90.0 - threat.distance_to(d)) * 4.0
		if score < best_score:
			best_score = score
			best = d
	var g := Iso.to_grid(from)
	var edge := g
	var m := minf(minf(g.x, g.y), minf(size - g.x, size - g.y))
	if m == g.x:
		edge.x = 0.6
	elif m == g.y:
		edge.y = 0.6
	elif m == size - g.x:
		edge.x = size - 0.6
	else:
		edge.y = size - 0.6
	var e := Iso.to_screen(edge)
	if is_free(e) and from.distance_to(e) + maxf(0.0, 90.0 - threat.distance_to(e)) * 4.0 < best_score:
		return e
	return best if best != Vector2.INF else point_away(from, threat, 200.0)


const SANCTUARY := 300.0   # px: townsfolk this near the chapel run to the sister's door


## A bandit type: the defaults, then the type, then any per-placement overrides.
func enemy_type(kind: String, overrides := {}) -> Dictionary:
	var t: Dictionary = enemy_data["defaults"].duplicate(true)
	t.merge(enemy_data["types"][kind], true)
	t.merge(overrides, true)
	return t


## Seconds since the last shot, as long as nobody is fighting.
## The quiet business of a town that isn't at war (the saloon girls out to the men on
## guard; the calls of nature): not in a fight's towns (the level's "action": Cruz
## Verde, Paso Esperanza).
func flirting_ok() -> bool:
	return not level_entry.get("action", false) and not Engine.has_meta("no_flirts")


func quiet_for() -> float:
	return _quiet


## The dead bandit an undertaker sees to next, now claimed by him: the nearest one
## the padre has blessed, or else the nearest he isn't about to bless, or else any.
func claim_body(by: Civilian) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	if level.get("boothills", []).is_empty():
		return null   # (a town with no boot hill: nowhere to take them)
	for e in enemies:
		if e.alive or e.downed or e.dying() or e.has_meta("buried") or _held(e, "claimed_by") or e.has_meta("dragged"):
			continue
		var score := by.global_position.distance_to(e.global_position)
		if not e.has_meta("blessed"):
			score += 2.0e6 if _held(e, "blessing_by") else 1.0e6   # anywhere in town, the blessed come first
		if score < best_score:
			best_score = score
			best = e
	if best:
		best.set_meta("claimed_by", by)
	return best


## The nearest of the dead the padre hasn't blessed yet, townsfolk or bandit.
func blessing_for(by: Civilian) -> Actor:
	var dead: Array[Actor] = []
	dead.append_array(enemies)
	dead.append_array(civilians)
	var best: Actor = null
	var best_d := INF
	for a in dead:
		if a.alive or (a is Enemy and a.downed) or a.dying() or a.has_meta("buried") or a.has_meta("blessed") \
				or _held(a, "blessing_by") or in_hand(a):
			continue
		var d := by.global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best:
		best.set_meta("blessing_by", by)
	return best


## Someone (still about, still on it) has this body.
func _held(a: Actor, key: String) -> bool:
	if not a.has_meta(key):
		return false
	var who: Civilian = a.get_meta(key)
	return who != null and who.alive and who.body == a


## The undertaker already has his tape on him, or has him in tow.
## A dead man within reach for the stranger to haul off (not one being buried).
func body_to_drag(from: Vector2, reach: float) -> Enemy:
	var best: Enemy = null
	var best_d := reach
	for e in enemies:
		if e.alive or e.downed or e.dying() or e.has_meta("buried") or in_hand(e):
			continue
		var d := e.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = e
	return best


func in_hand(a: Actor) -> bool:
	if not a.has_meta("claimed_by"):
		return false
	var who: Civilian = a.get_meta("claimed_by")
	return who != null and who.alive and who.body == a and who.st in [Civilian.St.MEASURE, Civilian.St.DRAG]


## Their general down: the gang's lost its head.
func lose_the_head(who: Enemy) -> void:
	var gs: Dictionary = gangs[who.gang]
	if gs["leaderless"]:
		return
	gs["leaderless"] = true
	if who.gang == "":
		hud.banner("¡Mataron al general!  The garrison's lost its head!")
	else:
		hud.banner("%s is dead!  The %s have lost their head!" % [who.tdata["name"], who.gang])
	sfx("sting", null, -6.0, 0.0)
	stats["lost its head"] = stats.get("lost its head", 0) + 1
	for e in enemies:
		if e.alive and e != who and e.gang == who.gang:   # (the other gang's only glad of it)
			e.lose_heart()


## The machine gun's cut a man down: the men by him who the stranger can see take
## fright (only those: a rout starting somewhere off down the line where he can't
## see it would be no use to anyone). What he can see is the 1280x720 window's view
## round the middle of the screen, whatever the window: a big monitor shows more of
## the line, but doesn't break more of it.
func _gun_fright(at: Vector2) -> void:
	var seen := HUD_PAGE * 2.0 / VIEW_ZOOM
	var view := Rect2(camera.get_screen_center_position() - seen / 2.0, seen)
	for o in enemies:
		if o.alive and o.assault and not o.deserting and o.flag_at == Vector2.INF \
				and o.global_position.distance_to(at) < GUN_FEAR_NEAR \
				and (view.has_point(o.global_position) or (o.global_position.distance_to(player.global_position) < GUN_FEAR_SEEN
					and line_of_sight(player.global_position, o.global_position, false))):
			o.gun_fright(at)   # (on his screen, or near enough him to see plainly)


## A deserter off the edge of the map: gone, not dead (nobody to bury, no gun dropped).
func gone_off(e: Enemy) -> void:
	enemies.erase(e)
	e.set_physics_process(false)   # (out of the reckoning; freed at the frame's end)
	e.visible = false
	if e.ghost:
		e.ghost.queue_free()
	e.cone.queue_free()
	e.queue_free()


## Their capitán down: every man on the field shaken, the faint-hearted off; the
## companies still on the road haven't heard, and come on as before.
func _commander_down(who: Enemy) -> void:
	hud.banner("¡Mataron al capitán!  They've lost their commander!")
	sfx("sting", null, -6.0, 0.0)
	stats["commander down"] = stats.get("commander down", 0) + 1
	for e in enemies:
		if e.alive and e != who:
			e.lose_heart()


## The colours down in the dirt: a blow to every man who sees them go (the levas
## lose heart; the rest are shaken). The first time, the nearest regular runs to
## raise them again; the second, they stay down.
func _flag_down(bearer: Enemy) -> void:
	stats["colours down"] = stats.get("colours down", 0) + 1
	var at := bearer.global_position - bearer.facing * 8.0
	var fp: Array = meta["objects"]["flag_down"]["footprint"]
	_place_object("flag_down", Iso.to_grid(at) - Vector2(fp[0], fp[1]) * 0.5)
	flags.append({"at": at, "rec": placed[-1]})
	hud.toast("Their colours are down")
	for o in enemies:
		if o.alive and o != bearer and o.global_position.distance_to(at) < FLAG_SEEN:
			if o.kind == "leva" and Enemy.assault_rng.randf() < FLAG_BREAKS:
				o.lose_heart()   # (some of the levas: the rest stay, shaken)
			else:
				o.shaken = minf(1.0, o.shaken + 0.5)
	if bearer.has_meta("raised"):
		return   # (raised once, and down again: they stay down)
	var best: Enemy = null
	for o in enemies:
		if o.alive and o != bearer and o.tdata.get("flag", "") == "raise" and o.flag_at == Vector2.INF \
				and not o.posted() and o.reaction != "flee" and o.global_position.distance_to(at) < FLAG_RAISE \
				and (best == null or o.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = o
	if best:
		best.raise_flag(at)


## A man at the fallen colours: up they go, if they're still there.
func take_up_flag(o: Enemy) -> void:
	for f in flags:
		if f["at"].distance_to(o.global_position) < 24.0:
			flags.erase(f)
			lift_object(f["rec"])
			o.take_flag()
			stats["colours raised"] = stats.get("colours raised", 0) + 1
			for e in enemies:
				if e.alive and e != o and e.global_position.distance_to(o.global_position) < FLAG_SEEN:
					e.shaken = maxf(0.0, e.shaken - 0.3)
			return


## A free plot on boot hill, a little apart from the other new graves.
func grave_spot() -> Vector2:
	var r: Array = level["boothills"][0]
	var p := Vector2.ZERO
	for i in 30:
		p = Iso.to_screen(Vector2(randf_range(r[0] + 1.0, r[2] - 1.0), randf_range(r[1] + 1.0, r[3] - 1.0)))
		if not is_free(p):
			continue
		var apart := true
		for g in graves:
			apart = apart and g.distance_to(p) > 16.0
		if apart:
			break
	graves.append(p)
	return p


## The blood under a body, laid on the ground as he comes to rest and spreading a
## little. It's apart from the body's sprite, so it stays put if he's dragged off.
func lay_pool(a: Actor) -> void:
	var pools: Dictionary = meta.get("pools", {})
	if not pools.has(a._death):
		return
	var info: Dictionary = pools[a._death][Iso.dir8(a.facing)]
	var s := Sprite2D.new()
	s.texture = tex(info["file"])
	s.centered = false
	s.offset = -Vector2(info["anchor"][0], info["anchor"][1])
	s.position = a.global_position
	s.scale = Vector2.ONE * tex_scale * 0.4
	s.modulate.a = 0.0
	decals.add_child(s)
	if a is Enemy:
		blood_pools.append({"at": a.global_position, "body": a, "known": [], "sprite": s})
	var land := a.anim("full/" + a._death)
	var t: float = land["frames"][0].size() / float(land["fps"]) * 0.8
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_property(s, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(s, "scale", Vector2.ONE * tex_scale, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Into the ground: the body's gone (no longer anything for the bandits to find)
## and a fresh cross marks the spot.
func bury(body: Actor, at: Vector2) -> void:
	body.visible = false
	body.set_meta("buried", true)
	body.remove_meta("claimed_by")
	stats["burials"] = stats.get("burials", 0) + 1
	_fresh_grave(at)


## Last night's broken bottles (the level's "litter"), lying where they were dropped:
## green and brown glass and a dark stain of what was in them. On their own dice.
func _litter() -> void:
	for p in level.get("litter", []):
		var at := Iso.to_screen(Vector2(p[0], p[1]))
		var col: Color = [Color(0.4, 0.66, 0.4), Color(0.68, 0.44, 0.2), Color(0.86, 0.94, 0.98)][litter_rng.randi() % 3]
		decals.add(at + Vector2(litter_rng.randf_range(-3, 3), 2), litter_rng.randf_range(5.5, 7.5), Color(0.2, 0.12, 0.07, 0.4))
		for i in litter_rng.randi_range(8, 11):
			decals.add(at + Vector2(litter_rng.randf_range(-8, 8), litter_rng.randf_range(-4, 4)),
				litter_rng.randf_range(1.1, 1.9), Color(col.r, col.g, col.b, 0.95))


func _on_boot_hill(g: Vector2) -> bool:
	for r in level.get("boothills", []):
		if g.x >= r[0] and g.x <= r[2] and g.y >= r[1] and g.y <= r[3]:
			return true
	return false


## The grave digger's done: the pit filled in over the coffin, and a fresh grave.
func fill_grave(gr: Dictionary) -> void:
	gr["done"] = true
	gr["sprite"].visible = false
	stats["graves dug"] = stats.get("graves dug", 0) + 1
	_fresh_grave(gr["at"])


## The coffin let down into the hole: the pit now shows its lid.
func lower_coffin(gr: Dictionary) -> void:
	gr["in"] = true
	var m: Dictionary = meta["objects"]["open_grave_in"]
	var spr: Sprite2D = gr["sprite"]
	spr.texture = tex(m["file"])
	spr.offset = ((Iso.to_screen(gr["g"]) - spr.position) / tex_scale - Vector2(m["anchor"][0], m["anchor"][1])).round()


## A heap of fresh earth with the cross at its head, unlike the old graves, and one
## for the mourners to come to.
func _fresh_grave(at: Vector2) -> void:
	var g := Iso.to_grid(at)
	var mf: Array = meta["objects"]["mound"]["footprint"]
	_place_object("mound", g - Vector2(mf[0], mf[1]) * 0.5)
	var cf: Array = meta["objects"]["cross"]["footprint"]
	_place_object("cross", g - Vector2(mf[0] * 0.5 + cf[0] * 0.6, cf[1] * 0.5))
	to_mourn.append({"at": at, "mourners": 0, "done": false})


## The oldest fresh grave nobody has wept over yet, with room for one more at it
## (two at most), now hers to go to; or none.
func grave_to_mourn() -> Dictionary:
	for g in to_mourn:
		if not g["done"] and g["mourners"] < 2:
			g["mourners"] += 1
			return g
	return {}


func make_noise(pos: Vector2, radius: float, kind: String, source: Node) -> void:
	if kind in ["shot", "enemy_shot", "blast"]:
		last_gunfire = clock
		last_gunfire_at = pos
		for sh in shutters:
			sh.hear_shot(pos, radius)
		if den.has("door") and not den["rallied"] and pos.distance_to(den["door"]) < DEN_EAR:
			den["heat"] += 3.0 if kind == "blast" else 1.0
			den["alarm"] = pos
			if den["heat"] >= DEN_HEAT:
				rally("gunfire")
	if kind == "shot" and source == player:
		_note_fire(player.global_position)
	raise_alarm({"shot": 1.0, "enemy_shot": 0.3, "blast": 6.0}.get(kind, 0.0), pos)
	if kind == "shot":
		player_fired = true
		report_sighting(pos)   # his muzzle flash and the crack give him away
	for e in enemies:
		if e.alive:
			e.hear(pos, radius, kind, source)
	for c in civilians:
		if c.alive:
			c.hear(pos, radius, kind, source)
	if kind in ["shot", "enemy_shot", "blast"]:
		for h in hens:
			if h.position.distance_to(pos) < radius * 0.7:
				h.scare(pos)


func alert_allies(caller: Enemy, radius: float, target: Vector2) -> void:
	for e in enemies:
		if e != caller and e.alive and e.gang == caller.gang and e.global_position.distance_to(caller.global_position) < radius:
			e.alert_to(target)


## The close-up is the stand-off moment: a bandit lays eyes on the stranger before a
## single shot has been fired. Alerts caused by the hero's own gunfire skip it.
func on_enemy_alert(_e: Enemy, spotted: bool) -> void:
	var now := clock
	if not alerted_once and spotted and not player_fired:
		alerted_once = true
		Engine.time_scale = 0.3
		closeup_left = 1.7
		hud.show_eyes()
		sfx("sting", null, -2.0, 0.0)
		last_twang = now
	elif now - last_twang > 7.0:
		last_twang = now
		sfx("twang", null, -6.0, 0.0)


func _on_enemy_died(e: Actor) -> void:
	var side := gang_of(e)
	gangs[side]["fallen"] += 1
	# a knife in the dark (Enemy.silent_death): nobody hears a thing, and only a man
	# who has him in view at the time knows it's happened; the rest find out from
	# the body
	var silent: bool = e is Enemy and e.silent_death
	var saw := func(o: Enemy) -> bool:
		return o.global_position.distance_to(e.global_position) < 180.0 and \
			(o.visibility_of(e.global_position, false, false) > 0.0 if silent else true)
	if e.killer == player:
		stats["his kills"] = stats.get("his kills", 0) + 1
		if player.down:   # from the dirt: and a man coming to finish him, or an officer, is a blow to them
			stats["kills while down"] = stats.get("kills while down", 0) + 1
			player.dropped_one()
			if e is Enemy and (e.finishing or e.rank >= 2):
				for o in enemies:
					if o.alive and o.global_position.distance_to(e.global_position) < 200.0:
						o.shaken = minf(1.0, o.shaken + 0.4)
	if not silent or enemies.any(func(o): return o.alive and o != e and saw.call(o)):
		raise_alarm(5.0, e.global_position, side)
	if e is Enemy and e.tdata.get("coordinator", false):
		lose_the_head(e)
	elif e is Enemy and e.tdata.get("commander", false):
		_commander_down(e)
	if e is Enemy and e.carries_flag():
		_flag_down(e)
	if e is Enemy and e.killer == player and player.gun:
		_gun_fright(e.global_position)
	if e.has_meta("scout") and e.alarm_role == "scout":
		raise_alarm(10.0, e.global_position, side)   # sent to look, and never came back
		stats["scouts lost"] = stats.get("scouts lost", 0) + 1
	if e.killer == player and not spot_at(player.global_position).is_empty():
		spot_at(player.global_position)["kills"] += 1
	for o in enemies:
		if o.alive and o != e and saw.call(o):
			o.witness_death(e.global_position, e.killer.global_position if is_instance_valid(e.killer) and e.killer is Enemy else player.global_position, e)
	if e is Enemy and level.has("turf") and not war:   # one of theirs saw him go down: whose doing?
		for o in enemies:
			if o.alive and o.gang == e.gang and saw.call(o) and line_of_sight(o.global_position, e.global_position, false):
				weigh_death(o, e)
				break
	for c in civilians:
		c.witness_death(e.global_position)
	if _args.has("bot"):
		print("%.1fs  %s down, %d left" % [(Time.get_ticks_msec() - start_time) / 1000.0, e.kind, alive_enemies()])
	_drop_kit(e)
	var ammo: String = e.weapon.ammo()
	if Pickup.AMOUNT.has(ammo):   # nothing to take from a derringer
		# (the poacher's Sharps rounds, new to the table, fall where he lies: no dice,
		# so the fights the tests replay stay as they were)
		var off := Vector2(3, 4) if ammo == "sharps" else Vector2(randf_range(-6, 6), 4)
		var p := _drop_ammo(ammo, e.global_position + off)
		for g in loose_guns:
			if g["under"] == e:
				g["ammo"] = p   # it goes with his gun
				g["ammo_kind"] = ammo
				break
	if posse == null and level.get("posse", true) and alive_enemies() <= posse_size and alive_enemies() > 0 \
			and (director == null or director.done()):
		posse = Posse.new(self)
		posse.form()
	var coming: bool = den.has("door") and den["rallied"] and not den["squad"].is_empty() \
		or director != null and not director.done()   # (more on the way: it isn't over)
	if alive_enemies() == 0 and state == "play" and not coming and cargo == null:   # (the cargo's won at the wagon)
		state = "won"
		ridden[level_entry["id"]] = true
		end_time = Time.get_ticks_msec()
		hud.show_message("THE TOWN IS QUIET" if not player.down else "FROM THE DIRT", _tally().trim_suffix("   -   "), onward())
		sfx("win", null, -2.0, 0.0)


## The end screen's count: how many of them he put down (and how many of those from
## the dirt), and any townsfolk.
func _tally() -> String:
	var n: int = stats.get("his kills", 0)
	var line := "%d of the gang by your hand" % n if n > 0 else "not one of the gang by your hand"
	if stats.get("kills while down", 0) > 0:
		line += " (%d from the dirt%s)" % [stats["kills while down"], ", and up again" if stats.has("rose from the dirt") else ""]
	return line + "   -   " + (hanging.line() if hanging else "") + (captive.line() if captive else "") \
		+ (cargo.line() if cargo else "") + (strongbox.line() if strongbox else "") \
		+ _innocents_line() + _padre_line()


## The sister took him in: nobody's saying more than that.
func _padre_line() -> String:
	return "the padre: in God's hands   -   " if stats.has("padre taken in") else ""


func _innocents_line() -> String:
	if innocents == 0:
		return ""
	return "innocents shot: %d   -   " % innocents


## A townsman down. If the hero did it, the town takes note (and so do we).
func _on_civilian_died(c: Actor) -> void:
	if c is Civilian and c.carried:
		spill_guns(c)
	var murder: bool = c.killer != null and c.killer.is_player
	if murder:
		innocents += 1
		innocent_t = 3.5
		stats["innocents"] = innocents
	for o in civilians:
		if o != c:
			if murder:
				o.witness_murder(c.global_position)
			else:
				o.witness_death(c.global_position)


## A level won or lost by something other than the gang or the stranger dying (the
## cargo away, or nobody left to carry it).
func end_level(won: bool, title: String) -> void:
	if state != "play":
		return
	state = "won" if won else "lost"
	end_time = Time.get_ticks_msec()
	if won:
		ridden[level_entry["id"]] = true
	else:
		Engine.time_scale = 0.35
	hud.show_message(title, _tally().trim_suffix("   -   "), onward())
	sfx("win" if won else "lose", null, -2.0, 0.0)


func _on_player_died(_p: Actor) -> void:
	if state != "play":
		return
	state = "lost"
	end_time = Time.get_ticks_msec()
	Engine.time_scale = 0.35
	hud.show_message("ADIOS, AMIGO", _tally().trim_suffix("   -   "), onward())
	sfx("lose", null, -2.0, 0.0)


## The shot that should have killed him has put him down instead: the moment
## slowed, a sting, the gang calling it, and the boldest of them walking up.
func on_player_down(shooter: Actor) -> void:
	stats["last stand"] = 1
	hurt_fx = 1.0
	add_shake(6.0)
	sfx("sting", null, -2.0, 0.0)
	Engine.time_scale = 0.5
	down_slow = 0.6
	heart_t = 0.8
	hud.toast("Down! Drop three from the dirt, or B to bandage")
	var caller: Enemy = null
	for e in enemies:
		if e.alive and e.revealed and line_of_sight(e.global_position, player.global_position, false) and \
				(caller == null or e.global_position.distance_to(player.global_position) < caller.global_position.distance_to(player.global_position)):
			caller = e
	if caller:
		caller.say_line("down", ["¡Ya cayó!", "He's down!", "¡Lo tenemos!", "Finish him!"])
	call_finishers()


## Up out of the dirt with three of them lying round him: anyone who sees it loses
## his nerve a little, and the nearest says what they're all thinking.
func on_player_rise() -> void:
	stats["rose from the dirt"] = 1
	hud.toast("Up from the dirt")
	add_shake(3.0)
	sfx("sting", null, -4.0, 0.0, rise_rng)
	var caller: Enemy = null
	for e in enemies:
		e.finishing = false
		if e.alive and line_of_sight(e.global_position, player.global_position, false):
			e.shaken = minf(1.0, e.shaken + 0.5)
			if caller == null or e.global_position.distance_to(player.global_position) < caller.global_position.distance_to(player.global_position):
				caller = e
	if caller:
		caller.say_line("rise", ["¡No se muere!", "He's getting up!", "¡Es el diablo!", "Madre de Dios..."], rise_rng)


## The bold ones who can see him lying there walk up to finish it (no more than a
## couple at once; when one falls, another may try).
func call_finishers() -> void:
	if not player.down:
		return
	var n := enemies.filter(func(e): return e.alive and e.finishing).size()
	var near: Array = enemies.filter(func(e): return e.alive and not e.finishing and e.revealed and not e.panic \
		and e.st == Enemy.St.COMBAT and line_of_sight(e.global_position, player.global_position, false))
	near.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	for e in near:
		if n >= FINISHERS:
			break
		if randf() < float(e.tdata["finish"]):
			e.finishing = true
			n += 1
			stats["walk up to finish"] = stats.get("walk up to finish", 0) + 1
			e.say_line("finish", ["Stay down, gringo.", "Adiós, amigo.", "¡Ahora sí!", "I'll do it."])


func on_player_hurt() -> void:
	if _args.has("bot"):
		print("%.1fs  hero hit, hp %d" % [(Time.get_ticks_msec() - start_time) / 1000.0, player.hp])
	hurt_fx = 1.0
	add_shake(4.0)


func alive_enemies() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n


# ------------------------------------------------------------------ effects

func add_shake(amount: float) -> void:
	shake = max(shake, amount)


func spawn_bullet(origin: Vector2, vel: Vector2, range_px: float, damage: int, shooter: Actor, height: float,
		pellet: bool, pierce := 0, own_cover := 26.0) -> void:
	var b := Bullet.new()
	b.setup(self, origin, vel, range_px, damage, shooter, height, pellet)
	b.pierce = pierce
	b.own_cover = own_cover
	if shooter and shooter.weapon:   # (the Sharps: through a wall, and through a man)
		b.walls = shooter.weapon.d.get("walls", {})
		b.men = int(shooter.weapon.d.get("men", 0))
	world.add_child(b)


func muzzle_flash(holder: Actor, dir: Vector2) -> void:
	var m: Dictionary = meta["muzzle"]
	var s := Sprite2D.new()
	s.texture = tex(m["file"])
	s.hframes = int(m["frames"])
	s.frame = randi() % 2
	s.centered = true
	s.position = holder.global_position + Vector2(0, 1)
	s.scale = Vector2.ONE * tex_scale
	var tip: Vector2 = holder.muzzle_offset() + dir * 2.0
	s.offset = (tip / tex_scale).round()
	world.add_child(s)
	get_tree().create_timer(0.05, false).timeout.connect(s.queue_free)
	# Black powder: every shot leaves a cloud that hangs and drifts off on the wind.
	var puff := Puff.new()
	puff.position = holder.global_position + Vector2(0, 2)
	var base := tip + Vector2(0, -1)
	var n: int = holder.weapon.d.get("smoke", 9)
	var push: float = holder.weapon.d.get("smoke_push", 1.0)
	for i in n:
		var shade := randf_range(0.78, 0.95)
		puff.smoke(base + dir * randf_range(0, 8), dir.rotated(randf_range(-0.5, 0.5)) * randf_range(10, 50) * push + Vector2(0, -randf_range(2, 10)),
			randf_range(2.5, 4.5), randf_range(1.5, 3.0), Color(shade, shade * 0.97, shade * 0.93, 0.42), randf_range(2.5, 4.5),
			WIND + Vector2(randf_range(-3, 3), randf_range(-3, 0)))
	world.add_child(puff)


## A dead man's gun falls from his hand and lands in the dirt beside him (or a
## living one throws his empty long gun down).
func drop_gun(a: Actor) -> void:
	var drops: Array = a.weapon.d.get("drops", [a.weapon.kind])
	for kind in drops:
		var side := a.facing.orthogonal() * randf_range(-10.0, 10.0) - a.facing * randf_range(2.0, 8.0)
		var g := _place_gun(kind, a.global_position + side + Vector2(0, 2), a.gun_height())
		g["under"] = null if a.alive else a
		if drops.size() == 1:   # loaded as he left it (a pair: some of each fired off, picked up)
			var w := Weapon.new(kind, null)
			w.copy_load(a.weapon)
			g["weapon"] = w


func _place_gun(kind: String, at: Vector2, fall: float) -> Dictionary:
	var g: Dictionary = meta["guns"][kind].pick_random()
	var s := Sprite2D.new()
	s.texture = tex(g["file"])
	s.centered = false
	s.scale = Vector2.ONE * tex_scale
	s.offset = -Vector2(g["anchor"][0], g["anchor"][1])
	s.position = at
	world.add_child(s)
	var spr_offset := s.offset
	s.offset = spr_offset + Vector2(0, -fall / tex_scale)
	var tw := create_tween()
	tw.tween_property(s, "offset", spr_offset, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var gun := {"kind": kind, "sprite": s, "at": at, "under": null, "ammo": null, "ammo_kind": "", "claimed_by": null}
	loose_guns.append(gun)
	return gun


## Cartridges for the stranger's guns, dropped by the dead (or spilled).
## What else he had on him for the stranger to take: now and then the bandage he
## never used, and the stick of dynamite he never threw (most of the time). Its own
## dice, so the fights the tests replay stay as they were.
func _drop_kit(e: Actor) -> void:
	if not e is Enemy:
		return
	if e.bandages > 0 and loot_rng.randf() < BANDAGE_DROP:
		_drop_ammo("bandage", e.global_position + Vector2(loot_rng.randf_range(-8, 8), 6))
	if e.sticks > 0 and e.stick == null and loot_rng.randf() < STICK_DROP:
		_drop_ammo("dynamite", e.global_position + Vector2(loot_rng.randf_range(-8, 8), -2))
	if peso_rng.randf() < PESO_DROP:
		_drop_ammo("peso", e.global_position + Vector2(peso_rng.randf_range(-8, 8), 2))


func _drop_ammo(kind: String, at: Vector2) -> Pickup:
	var p := Pickup.new()
	p.setup(self, at, kind)
	world.add_child.call_deferred(p)
	return p


## A gun the gunsmith may have: not lying under a body still waiting on the
## undertaker (once he's buried or dragged off, it's free), and nobody else's.
func gun_free(g: Dictionary, by: Civilian) -> bool:
	var who = g["claimed_by"]
	if who != null and who != by and is_instance_valid(who) and who.alive and who.gun == g:
		return false
	var under = g["under"]
	return under == null or not is_instance_valid(under) or under.has_meta("buried") \
		or under.global_position.distance_to(g["at"]) > 40.0


## The nearest free gun (within `within` of `from`, if given), now claimed by him.
func claim_gun(by: Civilian, from: Vector2, within := INF) -> Dictionary:
	var best: Dictionary = {}
	var best_d := within
	for g in loose_guns:
		var d: float = from.distance_to(g["at"])
		if d < best_d and gun_free(g, by):
			best_d = d
			best = g
	if not best.is_empty():
		best["claimed_by"] = by
	return best


# ------------------------------------------------------------------ the den

func _update_den(delta: float) -> void:
	if not den.has("door"):
		return
	if den["rallied"]:
		_spill_out(delta)
		return
	den["heat"] = maxf(0.0, den["heat"] - DEN_COOL * delta)
	den["runner_cd"] = maxf(0.0, den["runner_cd"] - delta)
	var fighting := false
	for e in enemies:
		if e.alive and e.st == Enemy.St.COMBAT:
			fighting = true
			break
	den["fight_t"] = den["fight_t"] + delta if fighting else 0.0
	var r = den["runner"]
	if r != null and (not is_instance_valid(r) or not r.alive):
		den["runner"] = null
		den["runner_cd"] = RUNNER_CD
		r = null
	if r == null and fighting and den["fight_t"] > RUNNER_AFTER and den["runner_cd"] <= 0.0:
		_send_runner()


## Someone breaks off from the fight and runs for the saloon: the least use in it
## (the weak types first), nearest the door, and not the one with the stranger in
## his sights.
func _send_runner() -> void:
	var best: Enemy = null
	var best_score := INF
	for e in enemies:
		if not e.alive or e.st != Enemy.St.COMBAT or e.in_posse or e.rank >= 2 or e.sees_player or e.posted():
			continue
		var score: float = e.global_position.distance_to(den["door"])
		score += 0.0 if e.kind in ["bandido", "pistolero", "drunkard"] else 300.0
		if score < best_score:
			best_score = score
			best = e
	if best:
		den["runner"] = best
		best.run_for_help(den["door"])
		stats["runners"] = stats.get("runners", 0) + 1


## The reserve comes out: a shout from inside, the den's shutters slam, and a
## moment later they spill out of the door one after another, spoiling for a fight.
func rally(cause: String) -> void:
	if den.is_empty() or den["rallied"] or state != "play":
		return
	den["rallied"] = true
	den["cause"] = cause
	den["spawn_t"] = 2.5   # chairs scrape: a moment's warning
	if seen_pos != Vector2.ZERO and staleness() < 10.0:
		den["alarm"] = seen_pos
	for sh in shutters:
		if sh.get_parent() == den["sprite"] and not sh.shut:
			sh._slam_in(randf_range(0.0, 0.6))
	hud.banner("¡Vámonos, muchachos!  The saloon empties!")
	sfx("sting", null, -6.0, 0.0)
	stats["rally"] = cause


func _spill_out(delta: float) -> void:
	if den["squad"].is_empty() or state != "play":
		return
	den["spawn_t"] -= delta
	if den["spawn_t"] > 0.0:
		return
	den["spawn_t"] = 0.7
	var kind: String = den["squad"].pop_front()
	var door: Vector2 = den["door"]
	var at := door + Vector2(randf_range(-6.0, 6.0), randf_range(0.0, 6.0))
	var en := _add_enemy(kind, at, PackedVector2Array(), rad_to_deg((den["alarm"] - door).angle()))
	# after the fight: back out front of the den, each to his own spot, out in the
	# open towards where the trouble was (all on one, or one they can't reach, and
	# they'd jostle there for good, blocking the way past)
	var fwd: Vector2 = (den["alarm"] - door).normalized()
	var homes: Array = den.get_or_add("homes", [])
	var angles: Array = range(12).map(func(k): return k * TAU / 12.0)
	angles.sort_custom(func(a, b): return Vector2.from_angle(a).dot(fwd) > Vector2.from_angle(b).dot(fwd))
	en.home = door + fwd * 40.0
	var found := false
	for r in [36.0, 56.0, 76.0]:
		for a in angles:
			var spot: Vector2 = door + Vector2.from_angle(a) * r
			if is_free(spot) and clear_path(door, spot) and homes.all(func(h): return h.distance_to(spot) > 18.0):
				en.home = spot
				found = true
				break
		if found:
			break
	homes.append(en.home)
	en.enter_combat(den["alarm"], false, false)
	if randf() < 0.5:
		en.say_line("spot", ["¡Vámonos!"])
	stats["reinforcements"] = stats.get("reinforcements", 0) + 1


# ------------------------------------------------------------------ firing spots

func spot_at(at: Vector2) -> Dictionary:
	for s in fire_spots:
		if at.distance_to(s["centre"]) < SPOT_SPAN:
			return s
		for p in s["points"]:
			if at.distance_to(p) < SPOT_LINK:
				return s
	return {}


func _note_fire(at: Vector2) -> void:
	fire_spots = fire_spots.filter(func(s): return clock - s["last_t"] < SPOT_FORGET)
	var s := spot_at(at)
	if s.is_empty():
		s = {"centre": at, "points": [], "peeks": 0, "kills": 0, "last_t": -100.0}
		fire_spots.append(s)
	if clock - s["last_t"] > PEEK_GAP:
		s["peeks"] += 1
	s["last_t"] = clock
	var pts: Array = s["points"]
	for i in pts.size():
		if pts[i].distance_to(at) < 14.0:
			pts.remove_at(i)
			break
	pts.push_front(at)
	if pts.size() > 4:
		pts.pop_back()
	var c := Vector2.ZERO
	for p in pts:
		c += p
	s["centre"] = c / pts.size()


func spot_hot(s: Dictionary) -> bool:
	return s["peeks"] >= SPOT_HOT and clock - s["last_t"] < SPOT_FORGET


## A place for him to keep his gun on: the newest firing place he can see of a
## spot the stranger keeps shooting from, within his gun's reach, if the spot
## hasn't got its watchers already.
func watch_post(e: Enemy) -> Dictionary:
	var best: Dictionary = {}
	for s in fire_spots:
		if not spot_hot(s) or (not best.is_empty() and s["last_t"] < best["spot"]["last_t"]):
			continue
		var n := 0
		for o in enemies:
			n += 1 if o.alive and o != e and o.watch_spot == s else 0
		if n >= WATCHERS:
			continue
		for p in s["points"]:
			var d := e.global_position.distance_to(p)
			if d > 30.0 and d < e.weapon.d["range"] * 0.9 and line_of_sight(e.global_position, p, false):
				best = {"spot": s, "at": p}
				break
	return best


# ------------------------------------------------------------------ dynamite

## Where this bandit would throw a stick, or INF: the stranger was just seen at a
## spot he's killed from more than once and still fires from, in throwing range
## and with no wall in the way, and none of the gang standing near it. Only one
## stick lit at a time, and a while between blasts.
func dynamite_target(e: Enemy) -> Vector2:
	if Engine.has_meta("no_dynamite") or dyn_cd > 0.0 or not lit.is_empty() or staleness() > FRESH:
		return Vector2.INF
	var s := spot_at(seen_pos)
	if s.is_empty() or s["kills"] < DYN_KILLS or clock - s["last_t"] > DYN_FRESH:
		return Vector2.INF
	var d := e.global_position.distance_to(seen_pos)
	if d < THROW_MIN or d > THROW_MAX or not line_of_sight(e.global_position, seen_pos, false):
		return Vector2.INF
	for o in enemies:
		if o != e and o.alive and o.global_position.distance_to(seen_pos) < Dynamite.R + 12.0:
			return Vector2.INF
	return seen_pos


func light_stick(by: Enemy) -> Dynamite:
	var d := Dynamite.new()
	world.add_child(d)
	d.setup(self, by)
	lit.append(d)
	stats["dynamite lit"] = stats.get("dynamite lit", 0) + 1
	return d


## A peso of the stranger's comes down in the street with a clink, and lies there to
## be had. The nearest of the gang in earshot with nothing better to do goes for it
## (only the one); nobody near, and it's still his to pick up. The gang remembers
## money falling from the sky by the same spot (see Enemy.go_for_peso).
func peso_landed(at: Vector2) -> void:
	sfx("clink", at, -6.0, 0.08, peso_rng)
	stats["pesos tossed"] = stats.get("pesos tossed", 0) + 1
	var c := _drop_ammo("peso", at)
	c.set_meta("tossed", true)
	var taker: Enemy = null
	var best := PESO_EAR
	for e in enemies:
		var d := e.global_position.distance_to(at)
		if d < best and e.can_be_lured():
			best = d
			taker = e
	if taker == null:
		return
	var times := 0
	for h in pesos_heard:
		if clock - h["t"] < PESO_MEMORY and at.distance_to(h["at"]) < PESO_SPOT:
			times += 1
	pesos_heard.append({"at": at, "t": clock})
	taker.go_for_peso(c, times)


## It's down and fizzing: anyone close who knows what that is gets clear of it. One
## of their own, they all know; the stranger's, mostly only the officers see it in
## time (the rest blunder about, or spot it too late).
func stick_landed(d: Dynamite) -> void:
	var at := d.global_position
	var his: bool = d.by == player
	if player.gun and not his and player.global_position.distance_to(at) < Dynamite.R + 20.0:
		# bolted to the gun he'd never see it for the smoke: they shout it for him
		hud.banner("¡Dinamita! Off the gun, compañero!")
		sfx("sting", null, -4.0, 0.0)
	for e in enemies:
		if e.alive and e.global_position.distance_to(at) < Dynamite.R + 20.0:
			if not his or e.rank >= RUNS_FROM or loot_rng.randf() < SPOT_STICK:
				e.dodge(at, d.fuse)
	for c in civilians:
		if c.alive and c.global_position.distance_to(at) < Dynamite.R + 40.0:
			c.alarm(at, true)


## The bang. Everyone in reach not behind a wall is hurt (killed, near the middle),
## a crate or barrel between them and it taking some of it; cover nearby is blown
## apart (but a mine's spares the breastwork it was laid round); and the whole town
## hears it.
func blast(at: Vector2, by: Actor, r := Dynamite.R, core := Dynamite.CORE, mine := false) -> void:
	dyn_cd = DYN_CD
	stats["blasts"] = stats.get("blasts", 0) + 1
	var hurt: Array[Actor] = []
	hurt.append(player)
	hurt.append_array(enemies)
	hurt.append_array(civilians)
	for a in hurt:
		if not a.alive or not a.visible:
			continue
		var d := a.global_position.distance_to(at)
		if d > r or not line_of_sight(at, a.global_position, false):
			continue
		if captive and a == captive.man and d > Captive.BLAST_ON:
			continue   # (an old hand at this: only a stick right on top of him)
		var dmg := 8 if d < core else (3 if d < r * 0.7 else 1)
		if d >= core and not line_of_sight(at, a.global_position, true):
			dmg -= 2   # behind a crate: it takes the worst of it
		if dmg <= 0:
			continue
		var dir := (a.global_position - at).normalized() if d > 0.5 else Vector2.from_angle(randf() * TAU)
		a.blasted = true
		a.take_hit(dmg, dir, by)
		a.blasted = false
		if a is Enemy:
			a.killed_with = "dynamite"   # (not the gun in the thrower's other hand)
		if a.alive:
			a.stagger_t = maxf(a.stagger_t, 0.6)
		elif a != player:
			stats["blown up"] = stats.get("blown up", 0) + 1
	for prop in props:
		if prop["state"] >= 2 or (mine and prop.get("ours", false)):
			continue
		var d := maxf(0.0, prop_centre(prop).distance_to(at) - 8.0)
		if d < r and prop["kind"] in EXPLOSIVE:
			arm(prop, by, randf_range(CHAIN.x, CHAIN.y))   # the next one along goes up too
		elif d < r:
			hit_prop(prop, int(lerpf(40.0, 8.0, d / r)), 0, prop_centre(prop))
	for item in fragile:
		var near: Vector2 = item["at"] + (at - item["at"]).normalized() * 6.0   # (the near side of a pane)
		if item["at"].distance_to(at) < r * 1.3 and line_of_sight(at, near, false):
			var sh = item.get("shutter")
			if sh == null or not sh.shut:
				while item["state"] < item["last"]:
					hit_fragile(item, item["at"])
	_wound_walls(at, r)
	for e in enemies:
		if e.alive and e.global_position.distance_to(at) < r * 2.2:
			e.shaken = minf(1.0, e.shaken + 0.3)
	var big := r / Dynamite.R
	_blast_fx(at, big)
	_scar(at, {})
	sfx("boom", at, 2.0 + 3.0 * (big - 1.0), 0.08)
	add_shake(lerpf(10.0, 2.0, clampf(player.global_position.distance_to(at) / 500.0, 0.0, 1.0)) * big)
	make_noise(at, 650.0 * big, "blast", by)


## The walls a blast reaches are marked for good where it struck them: soot, and
## close enough a hole knocked in them, the worse the bigger the bang. Only the faces
## you can see (as with the bullet holes), and nothing about the wall changes but
## its look. Rays fanned out along the ground find the nearest place on each face.
func _wound_walls(at: Vector2, r: float) -> void:
	var near := {}   # building wall face -> its nearest hit
	for i in WOUND_RAYS:
		var hit := ray(at, at + Vector2.from_angle(TAU * i / WOUND_RAYS) * r, Iso.LAYER_WALL)
		if hit.is_empty() or not hit["collider"].has_meta("building") or hit["normal"].y <= 0.05:
			continue
		var key := "%d %d" % [hit["collider"].get_instance_id(), signf(hit["normal"].x)]
		var d: float = hit["position"].distance_to(at)
		if not near.has(key) or d < near[key]["d"]:
			near[key] = {"d": d, "hit": hit}
	for key in near:
		var hit: Dictionary = near[key]["hit"]
		var col: Object = hit["collider"]
		var spr: Sprite2D = col.get_meta("building")
		var w: Wounds = spr.get_node_or_null("Wounds")
		if w == null:
			w = Wounds.new()
			w.name = "Wounds"
			w.setup(spr, tex_scale, col.get_meta("paint") == "adobe")
			spr.add_child(w)
			var over := 0   # (over its holes and shutters: a hole blown in a window; under its signs and lanterns)
			for i in spr.get_child_count():
				if spr.get_child(i) is Shutter or spr.get_child(i) is Holes:
					over = i + 1
			spr.move_child(w, over)
		var d: float = near[key]["d"]
		var size := ((1.0 - d / r) * 0.8 + 0.25) * r / Dynamite.R
		w.add(hit["position"] - spr.position, hit["normal"], size)
		if size >= Wounds.HOLE:
			rubble.heap(hit["position"], hit["normal"], minf(size, Wounds.BIGGEST), w.adobe)
		stats["walls wounded"] = stats.get("walls wounded", 0) + 1


## A keg or a crate of dynamite hit (by a round, or a blast nearby: then `delay`):
## it's going up, and nothing will stop it now. The officers know what a fizzing
## keg means and get clear; the rest of them blunder on; townsfolk run.
func arm(prop: Dictionary, by: Actor, delay := -1.0) -> void:
	if prop.get("lit", false) or prop["state"] >= 2:
		return
	prop["lit"] = true
	var c := Charge.new()
	world.add_child(c)
	c.setup(self, prop, by, delay)
	charges.append(c)
	stats["charges lit"] = stats.get("charges lit", 0) + 1
	var at := c.global_position
	var shouted := false
	for e in enemies:
		if not e.alive or e.global_position.distance_to(at) > c.r + 40.0:
			continue
		if e.rank >= RUNS_FROM:
			e.dodge(at, c.fuse, c.r)
			stats["officers clear"] = stats.get("officers clear", 0) + 1
		elif not shouted and c.fuse > 0.5 and randf() < 0.5:
			shouted = true   # (he knows what it is, for all the good it does him)
			e.say_line("powder", ["¡Pólvora!", "¡Dinamita!", "¡Cuidado!", "Powder!"])
	for cv in civilians:
		if cv.alive and cv.global_position.distance_to(at) < c.r + 60.0:
			cv.alarm(at, true)


## It goes up: the keg or crate is gone, and everything round it takes the blast.
func detonate(c: Charge) -> void:
	charges.erase(c)
	var prop := c.prop
	_prop_state(prop, 2)
	stats["kegs blown" if prop["kind"] == "keg" else "dynamite crates blown"] = \
		stats.get("kegs blown" if prop["kind"] == "keg" else "dynamite crates blown", 0) + 1
	blast(c.global_position, c.by, c.r, c.core)


func _blast_fx(at: Vector2, big := 1.0) -> void:
	var puff := Puff.new()
	puff.position = at
	puff.add(Vector2(0, -6), Vector2.ZERO, 0.12, 20.0, Color(1.0, 0.95, 0.72, 1.0), -60.0)   # the flash
	for i in int(16 * big):   # the fireball
		var v := Vector2.from_angle(randf() * TAU) * randf_range(50, 150) * big
		puff.add(Vector2(randf_range(-4, 4), -randf_range(2, 10)), Vector2(v.x, v.y * 0.5 - randf_range(30, 90)),
			randf_range(0.2, 0.45), randf_range(3.0, 6.0), Color(1.0, randf_range(0.5, 0.8), 0.18, 0.95), -9.0)
	for i in int(34 * big):   # dirt and splinters thrown up
		puff.add(Vector2(randf_range(-6, 6), -2), Vector2(randf_range(-130, 130), -randf_range(80, 240)) * big,
			randf_range(0.8, 1.5), randf_range(0.8, 1.6), [Color(0.42, 0.31, 0.21), Color(0.3, 0.22, 0.15),
			Color(0.62, 0.48, 0.32)].pick_random(), 0.0, 320.0)
	for i in int(30 * big):   # a grimy cloud that hangs and drifts
		var v := Vector2.from_angle(randf() * TAU) * randf_range(15, 70) * big
		var shade := randf_range(0.36, 0.56)
		puff.smoke(Vector2(randf_range(-12, 12), -randf_range(2, 18)), Vector2(v.x, v.y * 0.5 - randf_range(5, 30)),
			randf_range(3.0, 5.5), randf_range(2.5, 4.5), Color(shade, shade * 0.93, shade * 0.86, 0.4),
			randf_range(1.5, 3.0), WIND + Vector2(randf_range(-3, 3), randf_range(-4, 0)))
	for i in 18:   # the dust ring rolling out along the street
		var a := TAU * i / 18.0
		puff.smoke(Vector2(cos(a), sin(a) * 0.5) * 6.0, Vector2(cos(a), sin(a) * 0.5) * randf_range(90, 130) * big,
			randf_range(1.5, 2.6), randf_range(3.0, 5.0), Color(0.78, 0.65, 0.48, 0.45), 4.0, WIND * 0.5)
	world.add_child(puff)
	decals.add(at, 24.0 * big, Color(0.1, 0.08, 0.06, 0.5))   # scorched earth
	decals.add(at, 13.0 * big, Color(0.06, 0.05, 0.04, 0.65))
	for i in int(7 * big):
		decals.add(at + Vector2.from_angle(randf() * TAU) * randf_range(14, 30) * big * Vector2(1, 0.5), randf_range(2, 4),
			Color(0.08, 0.06, 0.05, 0.5))


# ------------------------------------------------------------------ cover that wears

func prop_centre(prop: Dictionary) -> Vector2:
	return Iso.to_screen(prop["g"] + prop["fp"] * 0.5)


## A round strikes a prop: it takes the damage, and its look changes as it goes.
## Returns true if the round carries on through (thin enough for the gun).
func hit_prop(prop: Dictionary, dmg: int, pierce: int, at: Vector2, by: Actor = null) -> bool:
	if prop["state"] >= 2:
		return true
	if prop["kind"] in EXPLOSIVE:   # not wear: one round and it's going up
		sfx("wood_hit", at, -6.0, 0.15)
		arm(prop, by)
		return false
	prop["hp"] -= dmg
	sfx("wood_hit", at, -6.0, 0.15)
	var full: int = PROP_HP[prop["kind"]]
	if prop["hp"] <= 0:
		_prop_state(prop, 2)
		return true
	if prop["state"] == 0 and prop["hp"] <= full * 0.55:
		_prop_state(prop, 1)
	return pierce >= PROP_TOUGH[prop["kind"]]


## `quiet`: as the level's laid out, so no sound and nothing counted.
func _prop_state(prop: Dictionary, n: int, quiet := false) -> void:
	prop["state"] = n
	var m: Dictionary = meta["objects"][prop["kind"]]
	var st: Dictionary = m["states"][n - 1]
	var spr: Sprite2D = prop["sprite"]
	var base := (Iso.to_screen(prop["g"]) - spr.position) / tex_scale
	spr.texture = tex(st["file"])
	spr.offset = (base - Vector2(st["anchor"][0], st["anchor"][1])).round()
	var c := prop_centre(prop)
	_scar(c, prop)
	if prop["kind"] == "trough":
		_leak(c + Vector2(0, 10), 14.0 if n == 1 else 24.0)   # the water's getting out, into the street
	if n == 2:
		# down to a heap of boards: no cover, nothing in anyone's way
		if not quiet:
			sfx("wood_break", c, -2.0, 0.1)
		if prop["body"]:
			prop["body"].queue_free()
			prop["body"] = null
		_unblock_cells(prop["cells"])
		for p in prop["covers"]:
			cover_points.erase(p)
		spr.z_index = -1   # it lies flat now: people walk over it
		if not quiet:
			stats["cover wrecked"] = stats.get("cover wrecked", 0) + 1
	elif not quiet:
		stats["cover damaged"] = stats.get("cover damaged", 0) + 1


## The cover the stranger's crouched behind, for a bandit to put rounds into: still
## standing, right by where he was last seen, and in view and reach of this man,
## with no more than two at it already.
func cover_to_break(e: Enemy, near: Vector2) -> Dictionary:
	for prop in props:
		if prop["state"] >= 2 or prop_centre(prop).distance_to(near) > Enemy.BREAK_NEAR:
			continue
		var c := prop_centre(prop)
		if e.global_position.distance_to(c) > e.weapon.d["range"] * 0.8 or not line_of_sight(e.global_position, c, false):
			continue
		var n := 0
		for o in enemies:
			n += 1 if o != e and o.alive and o.suppress_t > 0.0 and o.breaking == prop else 0
		if n < 2:
			return prop
	return {}


## A building's breakable fixtures: its glazed panes (drawn under its shutters,
## shown once shot out) and the lantern hung out front.
func _add_fixtures(m: Dictionary, spr: Sprite2D, corner: Vector2, made: Array[Shutter]) -> void:
	for gl in m.get("glass", []):
		var ov := _overlay(m, gl, spr)
		ov.visible = false   # (drawn over the shutters' frames: they hide it as they close)
		var item := _add_fragile("glass", Vector2.ZERO, ov, 1, 0.0)
		item["a"] = Iso.to_screen(corner + Vector2(gl["span"][0][0], gl["span"][0][1]))
		item["b"] = Iso.to_screen(corner + Vector2(gl["span"][1][0], gl["span"][1][1]))
		item["at"] = (item["a"] + item["b"]) * 0.5
		item["z"] = Vector2(gl["z"][0], gl["z"][1]) * Actor.PZ
		item["shutter"] = made[int(gl["shutter"])] if int(gl["shutter"]) < made.size() else null
		if item["shutter"]:
			item["shutter"].glass = ov
	for la in m.get("lanterns", []):
		var ov := _overlay(m, la, spr)
		_add_fragile("lantern", Iso.to_screen(corner + Vector2(la["at"][0], la["at"][1])), ov, 1, FRAGILE_R["lantern"])
	for sg in m.get("signs", []):
		var ov := _overlay(m, sg, spr)
		ov.frame = SIGN_REST
		var item := _add_fragile("sign", Iso.to_screen(corner + Vector2(sg["at"][0], sg["at"][1])), ov, 1, FRAGILE_R["sign"])
		item.merge({"swing": 0.0, "spin": 0.0, "hits": 0, "frame0": SIGN_REST, "look0": [ov.texture, ov.offset]})
	for la in m.get("laundry", []):
		var ov := _overlay(m, la, spr)
		var item := _add_fragile("laundry", Iso.to_screen(corner + Vector2(la["at"][0], la["at"][1])), ov, 2, FRAGILE_R["laundry"])
		item.merge({"hits": 0, "flap_t": 0.0, "frame0": 0, "look0": [ov.texture, ov.offset], "cloth": la["kind"]})
		laundry.append(item)


func _overlay(m: Dictionary, o: Dictionary, building: Sprite2D) -> Sprite2D:
	var ov := Sprite2D.new()
	ov.texture = tex(o["file"])
	ov.centered = false
	ov.hframes = int(o["frames"])
	ov.offset = building.offset + Vector2(m["anchor"][0] - o["anchor"][0], m["anchor"][1] - o["anchor"][1])
	building.add_child(ov)
	return ov


func _add_fragile(kind: String, at: Vector2, spr: Sprite2D, last: int, radius: float) -> Dictionary:
	var item := {"kind": kind, "at": at, "state": 0, "last": last, "sprite": spr, "body": null}
	if radius > 0.0:
		_fragile_body(item, radius)
	fragile.append(item)
	return item


func _fragile_body(item: Dictionary, radius: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Iso.LAYER_FRAGILE
	body.collision_mask = 0
	body.position = item["at"]
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	body.add_child(cs)
	body.set_meta("fragile", item)
	statics.add_child(body)
	item["body"] = body


## A round strikes a wall: if that's a pane of glass at the height it flew (and
## the shutters aren't shut over it), the pane goes. True if the window took it.
func glass_hit(at: Vector2, height: float) -> bool:
	for item in fragile:
		if item["kind"] != "glass" or item["state"] > 0:
			continue
		var z: Vector2 = item["z"]
		if height < z.x - 3.0 or height > z.y + 3.0:
			continue
		if Geometry2D.get_closest_point_to_segment(at, item["a"], item["b"]).distance_to(at) > 6.0:
			continue
		var sh = item["shutter"]
		if sh != null and sh.shut:
			return true   # the shutters take it
		hit_fragile(item, at, height)
		return true
	return false


## A round into a building's wall leaves a hole in it for good, on the faces you can
## see (one turned away would never show it). False if it left none.
func wall_hole(col: Object, at: Vector2, height: float, normal: Vector2) -> bool:
	if not col.has_meta("building") or normal.y <= 0.05:
		return false
	var spr: Sprite2D = col.get_meta("building")
	var holes: Holes = spr.get_node_or_null("Holes")
	if holes == null:
		holes = Holes.new()
		holes.name = "Holes"
		holes.scale = Vector2.ONE / tex_scale
		if col.get_meta("paint") == "adobe":
			holes.rim = Color(0.92, 0.84, 0.7, 0.45)   # chipped plaster
		spr.add_child(holes)
		spr.move_child(holes, 0)   # (under its shutters, panes, lanterns and signs)
	holes.add(at - Vector2(0, height * 0.7) - spr.position)
	return true


## Hit: one look further gone, with the glass, crockery or splinters to show it.
func hit_fragile(item: Dictionary, at: Vector2, height := -1.0) -> void:
	if item["state"] >= item["last"]:
		return
	if item["kind"] == "sign":
		_hit_sign(item, at)
		return
	if item["kind"] == "laundry":
		_hit_laundry(item, at)
		return
	item["state"] += 1
	var n: int = item["state"]
	var kind: String = item["kind"]
	var spr: Sprite2D = item["sprite"]
	match kind:
		"glass":
			spr.set_meta("broken", true)
			spr.visible = item["shutter"] == null or item["shutter"].frame <= 1
		"lantern":
			spr.frame = 1
		_:
			var st: Dictionary = meta["objects"][kind]["states"][n - 1]
			var base := (Iso.to_screen(item["g"]) - spr.position) / tex_scale
			spr.texture = tex(st["file"])
			spr.offset = (base - Vector2(st["anchor"][0], st["anchor"][1])).round()
	var h: float = height if height >= 0.0 else {"glass": 24.0, "lantern": 36.0, "table": 13.0, "chair": 8.0,
		"olla": 6.0, "coop": 10.0, "hencrate": 7.0}[kind]
	var ground: Vector2 = item["at"] + (Vector2(0, 4) if kind == "glass" else Vector2.ZERO)   # (glass: onto the porch)
	match kind:
		"glass", "lantern":
			_shards(ground, h, Color(0.82, 0.9, 0.96), 12)
			sfx("glass", at, -4.0, 0.12)
		"table":
			if n == 1:
				_shards(ground, h, Color(0.5, 0.7, 0.5), 10)   # the bottles
				sfx("glass", at, -4.0, 0.12)
				decals.add(ground + Vector2(4, 2), 4.0, Color(0.24, 0.14, 0.08, 0.4))   # whisky in the dirt
			else:
				impact(ground, h, Vector2.RIGHT.rotated(randf() * TAU), true, false)
				sfx("wood_break", at, -6.0, 0.1)
		"chair":
			impact(ground, h, Vector2.RIGHT.rotated(randf() * TAU), true, false)
			sfx("wood_break" if n == item["last"] else "wood_hit", at, -6.0, 0.12)
		"coop", "hencrate":
			impact(ground, h, Vector2.RIGHT.rotated(randf() * TAU), true, false)
			sfx("wood_break" if n == item["last"] else "wood_hit", at, -6.0, 0.12)
			feathers(ground, 10)
			if item.get("hens", 0) > 0:
				# out they burst, every which way, squawking
				sfx("squawk", ground, -4.0, 0.1)
				for i in item["hens"]:
					_add_hen(ground, 8.0).scare(at)
				stats["hens loose"] = stats.get("hens loose", 0) + item["hens"]
				item["hens"] = 0
		"olla":
			_shards(ground, h, Color(0.69, 0.38, 0.24), 12)
			sfx("crock", at, -4.0, 0.12)
			decals.add(ground + Vector2(0, 2), 7.0, Color(0.16, 0.12, 0.1, 0.35))   # the water in it
	if n >= item["last"] and item["body"]:
		item["body"].queue_free()
		item["body"] = null
	stats["broken"] = stats.get("broken", 0) + 1
	_scar(item["at"], item)


## A round through a hanging sign: it swings away from the shot, splinters flying;
## the third parts a chain and leaves it hanging from one corner.
func _hit_sign(item: Dictionary, at: Vector2) -> void:
	item["hits"] += 1
	var from: float = Iso.to_grid(at).y - Iso.to_grid(item["at"]).y   # (which side the round came in)
	item["spin"] += SIGN_KICK * (-1.0 if from > 0.0 else 1.0)
	if not item in swinging:
		swinging.append(item)
	impact(item["at"], 34.0, Vector2.RIGHT.rotated(randf() * TAU), true, false)
	if item["hits"] < SIGN_HITS:
		sfx("wood_hit", at, -6.0, 0.12)
		return
	item["state"] = 1
	item["sprite"].frame = SIGN_REST + 4   # (askew)
	swinging.erase(item)
	sfx("wood_break", at, -6.0, 0.1)
	_broken(item)


## A round through the washing: it jerks and flaps, holed; the third tears it off
## the line into the dirt.
func _hit_laundry(item: Dictionary, at: Vector2) -> void:
	item["hits"] += 1
	item["flap_t"] = 1.4
	sfx("tear", at, -10.0, 0.15)
	var puff := Puff.new()   # a wisp of lint
	puff.position = item["at"]
	for i in 4:
		puff.add(Vector2(0, -26), Vector2.RIGHT.rotated(randf() * TAU) * randf_range(10, 30), randf_range(0.4, 0.8),
			0.8, Color(0.93, 0.91, 0.86, 0.9), 0.0, 40.0)
	world.add_child(puff)
	if item["state"] == 0:
		item["state"] = 1
	if item["hits"] >= LAUNDRY_HITS:
		item["state"] = 2
		item["flap_t"] = 0.0
		item["sprite"].frame = 6
		_broken(item)


## Gone as far as it goes: no more to hit, and on the mayor's list.
func _broken(item: Dictionary) -> void:
	if item["body"]:
		item["body"].queue_free()
		item["body"] = null
	stats["broken"] = stats.get("broken", 0) + 1
	_scar(item["at"], item)


## Signs swinging back to rest, washing flapping (shot, or now and then in the breeze).
func _sway(delta: float) -> void:
	for i in range(swinging.size() - 1, -1, -1):
		var it: Dictionary = swinging[i]
		it["spin"] += (-SIGN_K * it["swing"] - SIGN_DAMP * it["spin"]) * delta
		it["swing"] = clampf(it["swing"] + it["spin"] * delta, -SIGN_STEP * 3.4, SIGN_STEP * 3.4)
		it["sprite"].frame = SIGN_REST + clampi(roundi(it["swing"] / SIGN_STEP), -3, 3)
		if absf(it["swing"]) < SIGN_STEP * 0.5 and absf(it["spin"]) < 0.25:   # (back on its rest frame)
			it["swing"] = 0.0
			it["sprite"].frame = SIGN_REST
			swinging.remove_at(i)
	for it in laundry:
		if it["state"] >= 2:
			continue
		var base: int = it["state"] * 3
		if it["flap_t"] <= 0.0 and wind_rng.randf() < delta * 0.06:
			it["flap_t"] = wind_rng.randf_range(0.8, 1.6) * -1.0   # (a gust: negative, a lazier flap)
		var t: float = it["flap_t"]
		if t > 0.0:
			it["flap_t"] = maxf(0.0, t - delta)
			it["sprite"].frame = base + 1 + int(t * 9.0) % 2
		elif t < 0.0:
			it["flap_t"] = minf(0.0, t + delta)
			it["sprite"].frame = base + 1 + int(-t * 3.0) % 2
		else:
			it["sprite"].frame = base


## Washing down in the dirt, or shot through: the nearest no one else is seeing to.
func laundry_job(by: Civilian) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for item in laundry:
		if item["state"] == 0:
			continue
		var f = item.get("fixer")
		if f != null and f != by and is_instance_valid(f) and f.alive and not f.gone():
			continue
		var d := by.global_position.distance_to(item["at"])
		if d < best_d:
			best_d = d
			best = item
	if not best.is_empty():
		best["fixer"] = by
	return best


## A hen near `at` (her own dice: the town's stay as seeded).
func _add_hen(at: Vector2, spread: float) -> Chicken:
	var p := at
	for i in 24:   # (wider and wider: a crate on a porch has the boards round it)
		var q := at + Vector2.from_angle(Chicken.rng.randf() * TAU) * Chicken.rng.randf_range(4.0, spread + i * 3.0)
		if is_free(q):
			p = q
			break
	var h := Chicken.new()
	world.add_child(h)
	h.setup(self, p)
	hens.append(h)
	return h


## A few feathers drifting down.
func feathers(at: Vector2, n: int) -> void:
	var puff := Puff.new()
	puff.position = at
	for i in n:
		var c: Color = [Color(0.94, 0.92, 0.88), Color(0.6, 0.36, 0.2), Color(0.25, 0.22, 0.22)][Chicken.rng.randi() % 3]
		puff.add(Vector2(Chicken.rng.randf_range(-4, 4), -Chicken.rng.randf_range(4, 12)),
			Vector2(Chicken.rng.randf_range(-25, 25), -Chicken.rng.randf_range(10, 40)), Chicken.rng.randf_range(1.6, 2.8),
			0.9, c, 0.0, 22.0, WIND * 0.7)
	world.add_child(puff)


func _shards(at: Vector2, height: float, col: Color, n: int) -> void:
	var puff := Puff.new()
	puff.position = at
	for i in n:
		puff.add(Vector2(randf_range(-2, 2), -height), Vector2(randf_range(-50, 50), -randf_range(10, 60)),
			randf_range(0.6, 1.1), randf_range(0.6, 1.1), col * randf_range(0.85, 1.15), 0.0, 300.0)
	world.add_child(puff)
	for i in 4:   # it stays where it fell, glinting
		decals.add(at + Vector2(randf_range(-7, 7), randf_range(-3, 4)), 0.7, Color(col.r, col.g, col.b, 0.8))


## A drop of blood where a wounded man is (or was a moment ago).
func drip(a: Actor, at: Vector2) -> void:
	decals.add(at + Vector2(randf_range(-2, 2), randf_range(-1, 1)), randf_range(1.3, 2.1), Color(0.42, 0.05, 0.04, 0.85))
	trails.append({"at": at, "t": clock, "player": a.is_player})
	if trails.size() > 400:
		trails.pop_front()


# ------------------------------------------------------------------ the gang's alarm

## `at`: where it happened, and `own`: whose trouble it is (else the gang nearest
## it); the other gang only gets uneasy over it.
func raise_alarm(amount: float, at := Vector2.INF, own := "?") -> void:
	if amount <= 0.0 or Engine.has_meta("no_alarm"):
		return
	if gangs.size() == 1:
		alarm += amount
		return
	var theirs := own if own != "?" else (gang_near(at) if at != Vector2.INF else "?")
	for g in gangs:
		var gs: Dictionary = gangs[g]
		if theirs == "?" or g == theirs:
			gs["alarm"] += amount
		elif gs["alarm"] < OTHER_END:
			gs["alarm"] = minf(gs["alarm"] + amount, OTHER_END)


## Men of this gang out of the fight, at their posts (or on their rounds) well away from it.
func _far_from_fight(g := "") -> Array:
	var out := []
	for e in enemies:
		if e.alive and e.gang == g and e.revealed and not e.in_posse and e.st in [Enemy.St.GUARD, Enemy.St.PATROL, Enemy.St.RETURN, Enemy.St.ERRAND] \
				and e.global_position.distance_to(seen_pos) > FAR:
			out.append(e)
	return out


func _gang_alarm(delta: float) -> void:
	for g in gangs:
		_one_gang_alarm(g, gangs[g], delta)


func _one_gang_alarm(g: String, gs: Dictionary, delta: float) -> void:
	if gs["leaderless"]:
		return   # nobody giving the orders now: every man for himself
	if quiet_for() > 30.0:
		gs["alarm"] = maxf(0.0, gs["alarm"] - 0.2 * delta)   # a long quiet: the nerves settle (a little)
	if gs["alarm"] < UNEASY or seen_pos == Vector2.ZERO:
		return
	var far := _far_from_fight(g)
	gs["stage"] = maxi(gs["stage"], 1)
	for e in far:
		e.get_uneasy(seen_pos)
	# losing badly: the rest fall back to a holdout away from the fight
	var holdouts: Array = level.get("holdouts", []).filter(func(h): return h.get("gang", g) == g)
	var men := enemies.filter(func(e): return e.gang == g).size()
	if gs["fallen"] >= maxi(3, ceili(men * FORTIFY_LOSS)) and not holdouts.is_empty():
		if gs["holdout"].is_empty():
			_pick_holdout(g, gs, holdouts)
		for e in far:
			if e.alarm_role != "fortified":   # (scouts back at their posts too)
				e.fortify(_holdout_spot(e, gs["holdout"]), seen_pos)
		gs["stage"] = 3
		return
	# a long fight: each post sends a pair to see what's going on
	gs["send_cd"] -= delta
	if gs["alarm"] >= SEND and gs["send_cd"] <= 0.0:
		gs["send_cd"] = SEND_EVERY
		gs["stage"] = 2
		for group in _posts(far):
			if group.size() < 2:
				continue   # a man alone holds his post
			group.sort_custom(func(a, b): return a.global_position.distance_to(seen_pos) < b.global_position.distance_to(seen_pos))
			for e in group.slice(0, 2):
				e.scout(seen_pos + Vector2(randf_range(-50, 50), randf_range(-25, 25)))


## The men grouped by post: each with whoever's within GROUP of him.
func _posts(men: Array) -> Array:
	var left := men.duplicate()
	var out := []
	while not left.is_empty():
		var g := [left.pop_back()]
		var i := 0
		while i < g.size():
			for o in left.duplicate():
				if o.global_position.distance_to(g[i].global_position) < GROUP:
					g.append(o)
					left.erase(o)
			i += 1
		out.append(g)
	return out


func _pick_holdout(g: String, gs: Dictionary, holdouts: Array) -> void:
	var best: Dictionary = {}
	for h in holdouts:
		var at := Iso.to_screen(Vector2(h["x"], h["y"]))
		if best.is_empty() or at.distance_to(seen_pos) > best["at"].distance_to(seen_pos):
			best = {"name": h["name"], "at": at, "taken": []}
	gs["holdout"] = best
	if g == "":
		hud.banner("¡Al %s, muchachos!  The gang falls back to the %s!" % [best["name"], best["name"]])
	else:
		hud.banner("The %s fall back to the %s!" % [g, best["name"]])
	stats["holdout"] = best["name"]


## A place at the holdout for him: cover near it nobody's taken, else open ground.
func _holdout_spot(e: Enemy, ho: Dictionary) -> Vector2:
	var at: Vector2 = ho["at"]
	var best := Vector2.INF
	for c in cover_points:
		if c.distance_to(at) < 150.0 and not c in ho["taken"] \
				and (best == Vector2.INF or c.distance_to(at) < best.distance_to(at)):
			best = c
	if best == Vector2.INF:
		best = free_point_near(at, 60.0)
	ho["taken"].append(best)
	return best


## A man running from the fight: the nearest of his comrades not in it (and not
## back towards the stranger) to run to with the news; or INF.
func comrades_to_tell(e: Enemy, threat: Vector2) -> Vector2:
	var away := (e.global_position - threat).normalized()
	var best := Vector2.INF
	var best_d := 700.0
	for o in enemies:
		if o == e or not o.alive or not o.revealed or o.st == Enemy.St.COMBAT or o.gang != e.gang:
			continue   # (the news is for his own: the other gang can find out for itself)
		var to: Vector2 = o.global_position - e.global_position
		var d := to.length()
		if d < best_d and d > 60.0 and to.normalized().dot(away) > -0.2:
			best_d = d
			best = o.global_position
	return best


## He's made it to them: they all know now.
func news(from: Enemy, threat: Vector2) -> void:
	raise_alarm(8.0, from.global_position, from.gang)
	for o in enemies:
		if o != from and o.alive and o.revealed and o.st != Enemy.St.COMBAT and o.gang == from.gang \
				and o.global_position.distance_to(from.global_position) < 160.0:
			o.get_uneasy(threat)
	stats["news brought"] = stats.get("news brought", 0) + 1


## A downed man's own gun, back in his hand (if it's still lying by him).
func take_back_gun(e: Enemy) -> void:
	for g in loose_guns:
		if g["under"] == e:
			loose_guns.erase(g)
			g["sprite"].queue_free()
			var ammo = g.get("ammo")
			if ammo != null and is_instance_valid(ammo):
				ammo.queue_free()
			return


## Downed men nobody's gone for yet: the nearest comrade game for it goes (most
## will: they don't leave their own in the dirt).
func _send_rescuers() -> void:
	for d in enemies:
		if not d.downed or d.rescuer != null or d.medic != null or d.gasp != "":
			continue
		var best: Enemy = null
		var best_d := Enemy.RESCUE_NEAR
		for e in enemies:
			if not e.alive or e.reaction != "" or e.runner_to != Vector2.INF or e.stick or not e.revealed \
					or e.posted() or e.gang != d.gang or war:   # (his place is at the gallows, or the pole; the other gang leaves him there; the street war's too hot to go out into)
				continue
			var dist := e.global_position.distance_to(d.global_position)
			if dist < best_d:
				best_d = dist
				best = e
		if best and randf() < 0.9 - 0.4 * best.fear():
			best.start_rescue(d)


## The freshest drop of the stranger's blood this bandit can see, newer than the
## last one he followed (and not too old to be worth it); or none. Once he's on the
## trail he's reading the ground: drops close by count even outside his gaze.
## Where to put rounds at a man you can't see, from `from`: his spot itself if
## there's a view of it; else his freshest blood in view near it; else the nearest
## open ground by it that's in view (the corner he's behind, the edge of the doorway).
## INF if there's nothing within reach of him to aim at.
func corner_near(from: Vector2, spot: Vector2) -> Vector2:
	if line_of_sight(from, spot, false):
		return spot
	for i in range(trails.size() - 1, -1, -1):
		var d: Dictionary = trails[i]
		if clock - d["t"] > 4.0:
			break
		if d["player"] and d["at"].distance_to(spot) < CORNER_NEAR and line_of_sight(from, d["at"], false):
			return d["at"]
	var away := (from - spot).normalized()
	for r in [16.0, 28.0, 42.0, 58.0]:
		var best := Vector2.INF
		for k in 12:
			var p: Vector2 = spot + Vector2.from_angle(k * TAU / 12.0) * r
			if is_free(p) and line_of_sight(from, p, false) and \
					(best == Vector2.INF or (p - spot).dot(away) < (best - spot).dot(away)):
				best = p   # (of those, the furthest round towards him: the edge itself)
		if best != Vector2.INF:
			return best
	return Vector2.INF


func trail_lead(e: Enemy, newer: float) -> Dictionary:
	var on_it := newer >= 0.0 and clock - newer < TRAIL_FRESH
	for i in range(trails.size() - 1, -1, -1):
		var d: Dictionary = trails[i]
		if d["t"] <= newer or clock - d["t"] > TRAIL_FRESH:
			break
		if not d["player"] or d.get("depth", 1.0) < Footprints.LEAD:
			continue   # (a print the snow's half filled is no lead)
		var dist: float = e.global_position.distance_to(d["at"])
		if dist < TRAIL_SEE and e.visibility_of(d["at"], true, false) > 0.0:
			return d
		if on_it and dist < TRAIL_CLOSE and line_of_sight(e.global_position, d["at"], true):
			return d
	return {}


# ------------------------------------------------------------------ the town tidies up

const WOOD := ["crate", "barrel", "coffin", "trough", "wagon", "chair", "table", "coop", "hencrate", "sign",
	"crate_stack", "upturned_n", "upturned_s", "upturned_e", "upturned_w"]
const KEEPS := 160.0   # px round the saloon keeper's door: his tables and chairs, not the carpenter's
const SWEEP_R := 26.0  # px a sweeper's broom clears at a go
const STRAY := 80.0    # px from the nearest coop: a hen this far off wants shooing home
var sweeping := {}     # sweeper -> the spot he's sweeping


## Something broken for this man to put right, now his: the saloon keeper's own
## tables and chairs for him; anything wooden for the carpenter, the ones the mayor
## has tutted over first (like the undertaker and the padre's blessed), then the
## nearest.
func repair_job(by: Civilian) -> Dictionary:
	var keepers: Array = civilians.filter(func(c): return c.keeper and c.alive)
	var best: Dictionary = {}
	var best_d := INF
	for item in props + fragile:
		if item["state"] == 0 or not item["kind"] in WOOD:
			continue
		var f = item.get("fixer")
		if f != null and f != by and is_instance_valid(f) and f.alive and not f.gone():
			continue
		var at: Vector2 = item["at"] if item.has("at") else prop_centre(item)
		var his: bool = keepers.any(func(k): return k.home.distance_to(at) < KEEPS) and item["kind"] in ["table", "chair"]
		if by.keeper != his or (by.keeper and by.home.distance_to(at) >= KEEPS):
			continue
		var d := by.global_position.distance_to(at)
		if not by.keeper and scars.any(func(s): return s["prop"] == item and s["seen"]):
			d -= 100000.0   # on the mayor's list
		if d < best_d:
			best_d = d
			best = item
	if not best.is_empty():
		best["fixer"] = by
	return best


func job_at(item: Dictionary) -> Vector2:
	return item["at"] if item.has("at") else prop_centre(item)


## Somebody standing where it'll be put back: wait.
func in_the_way(item: Dictionary, by: Civilian) -> bool:
	if not item.has("hp"):
		return false   # nothing anyone could be stuck in
	var at := job_at(item)
	var all: Array = [player]
	all.append_array(enemies)
	all.append_array(civilians)
	return all.any(func(a): return a != by and a.alive and a.visible and a.global_position.distance_to(at) < 18.0)


## Good as new: its old look back, and (a wreck) solid again, cover again.
func repair(item: Dictionary) -> void:
	var was: int = item["state"]
	var spr: Sprite2D = item["sprite"]
	spr.texture = item["look0"][0]
	spr.offset = item["look0"][1]
	spr.z_index = 0
	if item.has("frame0"):   # (a sign rehung, the washing pegged out again)
		spr.frame = item["frame0"]
		item["hits"] = 0
	item["state"] = 0
	item["fixer"] = null
	if item.has("hp"):
		item["hp"] = PROP_HP[item["kind"]]
		if was >= 2:
			_rebuild(item)
	elif item["body"] == null:
		_fragile_body(item, FRAGILE_R[item["kind"]])
	scars = scars.filter(func(s): return s["prop"] != item)
	stats["repaired"] = stats.get("repaired", 0) + 1


func _rebuild(prop: Dictionary) -> void:
	var m: Dictionary = meta["objects"][prop["kind"]]
	var g: Vector2 = prop["g"]
	var body := StaticBody2D.new()
	body.collision_layer = Iso.LAYER_COVER
	body.collision_mask = 0
	prop["cells"] = []
	for r in m["colliders"]:
		var poly := CollisionPolygon2D.new()
		poly.polygon = Iso.rect_poly(g.x + r[0], g.y + r[1], g.x + r[2], g.y + r[3])
		body.add_child(poly)
		prop["cells"].append_array(_block_cells(g.x + r[0], g.y + r[1], g.x + r[2], g.y + r[3], 0.22))
	for p in prop["covers"]:
		var c := _cell(p)
		if not astar.is_point_solid(c) and not p in cover_points:
			cover_points.append(p)
	body.set_meta("prop", prop)
	statics.add_child(body)
	prop["body"] = body


## The nearest mess for a sweeper (blood, glass, scorch, spilt water), not under a
## body still lying there and not where the other sweeper's at; or INF.
func dirt_job(by: Civilian) -> Vector2:
	var lying: Array = []
	var all: Array = []
	all.append_array(enemies)
	all.append_array(civilians)
	for a in all:
		if not a.alive and not a.has_meta("buried") and a.visible:
			lying.append(a.global_position)
	var others: Array = []
	for s in sweeping:
		if s != by and is_instance_valid(s) and s.alive:
			others.append(sweeping[s])
	var best := Vector2.INF
	var best_d := INF
	var spots: Array = decals.splats.map(func(s): return s[0])
	for c in decals.get_children():
		spots.append(c.position)
	for p in spots:
		var d: float = by.global_position.distance_to(p)
		if d >= best_d:
			continue
		if lying.any(func(b): return b.distance_to(p) < 24.0) or others.any(func(o): return o.distance_to(p) < 60.0):
			continue
		best_d = d
		best = p
	if best != Vector2.INF:
		sweeping[by] = best
	return best


## Swept into the dirt: every mark within a broom's reach, and the blood trail too.
func sweep_at(at: Vector2, by: Civilian) -> void:
	var n: int = decals.splats.size()
	decals.splats = decals.splats.filter(func(s): return s[0].distance_to(at) > SWEEP_R)
	for c in decals.get_children():
		if c.position.distance_to(at) < SWEEP_R:
			c.queue_free()
			n += 1
	trails = trails.filter(func(d): return d["at"].distance_to(at) > SWEEP_R)
	decals.queue_redraw()
	sweeping.erase(by)
	stats["swept"] = stats.get("swept", 0) + n - decals.splats.size()


## A hen astray (well away from any coop), for a hen woman to shoo home; now hers.
func stray_hen(by: Civilian) -> Chicken:
	var best: Chicken = null
	var best_d := INF
	for h in hens:
		if h.herder != null and h.herder != by and is_instance_valid(h.herder) and h.herder.alive and not h.herder.gone():
			continue
		var coop := coop_for(h.position)
		if coop.is_empty() or h.position.distance_to(coop["at"]) < STRAY:
			continue
		var d := by.global_position.distance_to(h.position)
		if d < best_d:
			best_d = d
			best = h
	if best:
		best.herder = by
	return best


## The coop a hen there belongs back in: the nearest one standing, or any.
func coop_for(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for item in fragile:
		if item["kind"] != "coop":
			continue
		if best.is_empty() or (item["state"] == 0 and best["state"] != 0) \
				or (item["state"] == best["state"] and at.distance_to(item["at"]) < at.distance_to(best["at"])):
			best = item
	return best


## Shooed all the way home: in through the hatch, or (no room, or the coop's in
## pieces) she pecks about outside it.
func hen_home(h: Chicken, coop: Dictionary) -> void:
	h.herder = null
	if coop["state"] == 0 and coop["hens"] < HENS_IN["coop"]:
		coop["hens"] += 1
		hens.erase(h)
		h.queue_free()
		stats["hens cooped"] = stats.get("hens cooped", 0) + 1
	else:
		h.home = coop["at"]   # she pecks about it from now on
		stats["hens home"] = stats.get("hens home", 0) + 1


## Fresh damage (or worse damage to a wreck he's already seen) for the mayor.
func _scar(at: Vector2, prop: Dictionary) -> void:
	for s in scars:
		if not prop.is_empty() and s["prop"] == prop:
			s["seen"] = false
			return
	scars.append({"at": at, "seen": false, "prop": prop})


## The nearest damage the mayor hasn't looked at yet, now looked at; or none.
func scar_to_survey(from: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for s in scars:
		if not s["seen"] and (best.is_empty() or from.distance_to(s["at"]) < from.distance_to(best["at"])):
			best = s
	if not best.is_empty():
		best["seen"] = true
	return best


## A puddle spreading from a holed trough over a few seconds.
func _leak(at: Vector2, r: float) -> void:
	var wet := Color(0.13, 0.15, 0.18, 0.42)
	for i in 5:
		var tw := create_tween()
		tw.tween_interval(i * 1.2)
		tw.tween_callback(func(): decals.add(at + Vector2(randf_range(-8, 8), i * 2.5), r * (0.5 + 0.2 * i), wet))


## The stranger walks over a gun for a slot he hasn't filled: it's his. One for a
## slot he has is a swap he has to mean (F): the gun he could take glints, and the
## HUD names it. The cartridges lying by it are his to pick up as usual.
func _pick_up_guns() -> void:
	var g: Dictionary = player.gun_at_feet() if player.alive and not player.down else {}
	if g != at_feet:
		if not at_feet.is_empty() and is_instance_valid(at_feet["sprite"]):
			at_feet["sprite"].modulate = Color.WHITE
		at_feet = g
	if g.is_empty():
		return
	if not Player.SLOT[g["kind"]] in player.owned and not g.get("his", false):
		_take_up(g)
		return
	g["sprite"].modulate = Color(1, 1, 1).lerp(Color(1.9, 1.6, 1.0), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))


## F: the gun at his feet into his hand, and his own in that slot left lying there.
func swap_gun() -> void:
	if not at_feet.is_empty() and player.alive and not player.down and loose_guns.has(at_feet):
		_take_up(at_feet)


func _take_up(g: Dictionary) -> void:
	var k: String = g["kind"]
	var bandolier := 0
	var ammo = g["ammo"]   # (his cartridges by him: off his belt with the gun)
	if ammo != null and is_instance_valid(ammo) and not ammo.is_queued_for_deletion():
		bandolier = Pickup.AMOUNT[ammo.kind]
		player.belt[ammo.kind] = player.belt.get(ammo.kind, 0) + bandolier
		ammo.queue_free()
	loose_guns.erase(g)
	g["sprite"].queue_free()
	at_feet = {}
	var old: Weapon = player.take_up(k, g.get("weapon"))
	var w: Weapon = player.weapons[Player.SLOT[k]]
	var says := "%s  picked up  [%d]" % [w.d["name"], Player.ORDER.find(Player.SLOT[k]) + 1]
	if old:   # down in the dirt where the other lay, as loaded as it was
		var left := _place_gun(old.kind, g["at"], 6.0)
		var keep := Weapon.new(old.kind, null)
		keep.copy_load(old)
		left["weapon"] = keep
		left["his"] = true
		says = "%s  for the %s" % [w.d["name"], old.d["name"]]
		stats["guns swapped"] = stats.get("guns swapped", 0) + 1
	if bandolier > 0:
		says += "  +%d" % bandolier
	hud.toast(says)
	stats["guns picked up"] = stats.get("guns picked up", 0) + 1


## Picked up: off the ground, and the cartridges lying with it go too.
func take_gun(g: Dictionary) -> void:
	loose_guns.erase(g)
	g["sprite"].queue_free()
	var ammo = g["ammo"]
	if ammo != null and is_instance_valid(ammo):
		ammo.queue_free()
	else:
		g["ammo_kind"] = ""   # the stranger already had those
	stats["guns gathered"] = stats.get("guns gathered", 0) + 1


## The gunsmith goes down with an armful: it all spills round him, cartridges too.
func spill_guns(c: Civilian) -> void:
	for item in c.carried:
		var at := c.global_position + Vector2.from_angle(randf() * TAU) * randf_range(6.0, 16.0)
		var g := _place_gun(item["kind"], at, 14.0)
		if item["ammo_kind"] != "":
			g["ammo_kind"] = item["ammo_kind"]
			g["ammo"] = _drop_ammo(item["ammo_kind"], at + Vector2(randf_range(-5, 5), 4))
	c.carried.clear()


## Animation events: brass flicking out of a Winchester or Colt, shells out of a
## shotgun's barrels; and (from the gun itself) a Schofield's whole cylinder, `n` of them,
## thrown out together and dropping round his feet. Where they land they stay (`brass`).
func anim_event(a: Actor, ev: String, n := 1) -> void:
	if ev == "brass" and a.weapon and a.weapon.action == "lever" and not a.weapon.ejecting:
		return   # working the lever on an empty chamber: nothing to throw out
	var puff := Puff.new()
	puff.position = a.global_position + Vector2(0, 2)
	puff.keep = brass
	var at: Vector2 = a.muzzle_offset() - a.facing * 6.0
	var side := a.facing.orthogonal()
	if ev == "dump":   # out of the gun held up at his chest, straight down round his boots
		var gun := Vector2(a.facing.x * 4.0, -a.gun_height() * 0.8)
		for i in n:
			puff.case(gun + Vector2(randf_range(-1.5, 1.5), randf_range(-1, 1)),
				Vector2(randf_range(-18, 18), -randf_range(0, 15)), randf_range(2.2, 3.0),
				Color(0.9, 0.72, 0.3).darkened(randf_range(0.0, 0.25)), 900.0, Brass.rng.randf_range(-3.0, 3.0))
		world.add_child(puff)
		return
	if ev == "brass" and a.weapon and a.weapon.d.get("pump", false):   # the Spencer's: straight up out of the frame
		puff.case(at + Vector2(0, -2), Vector2(Brass.rng.randf_range(-12, 12), -Brass.rng.randf_range(70, 95)),
			Brass.rng.randf_range(1.5, 2.5), Color(0.72, 0.16, 0.12), 200.0, Brass.rng.randf_range(-6.0, 5.0))
		world.add_child(puff)
		return
	if ev == "shells":   # a shell out of each barrel: two from a double gun, one from the Champion
		n = a.weapon.barrels.size() if a.weapon and not a.weapon.barrels.is_empty() else 2
	for i in n:
		var c := Color(0.72, 0.16, 0.12) if ev == "shells" else Color(0.9, 0.72, 0.3)
		puff.case(at, side * randf_range(15, 35) * (1 if randf() < 0.5 else -1) + Vector2(0, -randf_range(25, 45)),
			randf_range(1.5, 2.5), c, 200.0, Brass.rng.randf_range(-6.0, 5.0))
	world.add_child(puff)


func impact(pos: Vector2, height: float, vel: Vector2, wall: bool, hole := true) -> void:
	var puff := Puff.new()
	var back := -vel.normalized()
	if wall:
		# Splinters and plaster fly off, a dust cloud hangs, and a hole stays in the wall.
		puff.position = pos + Vector2(0, 6)
		var at := Vector2(0, -height * 0.7 - 6)
		for i in 7:
			puff.add(at, back.rotated(randf_range(-0.9, 0.9)) * randf_range(30, 80) + Vector2(0, -randf_range(10, 40)),
				randf_range(0.5, 0.9), randf_range(0.8, 1.2), Color(0.86, 0.74, 0.56), 0.0, 220.0)
		for i in 5:
			puff.smoke(at, back.rotated(randf_range(-0.6, 0.6)) * randf_range(8, 25), randf_range(1.0, 1.8),
				randf_range(1.5, 2.5), Color(0.84, 0.72, 0.56, 0.5), 5.0, WIND * 0.5)
		puff.add(at, back * 20.0, 0.07, 1.6, Color(1, 0.92, 0.6, 1))
		if hole:   # (not in a prop: it'll change, or be gone)
			puff.mark(at, 25.0, 1.4, Color(0.13, 0.09, 0.07, 0.95))
		if randf() < 0.3:
			sfx("ricochet", pos, -8.0, 0.15)
	else:
		# Dirt kicked up where the round strikes the street.
		puff.position = pos
		for i in 9:
			puff.add(Vector2.ZERO, Vector2(randf_range(-18, 18), -randf_range(40, 95)), randf_range(0.5, 0.9),
				randf_range(0.8, 1.3), Color(0.42, 0.31, 0.21), 0.0, 230.0)
		for i in 5:
			puff.smoke(Vector2(randf_range(-2, 2), -randf_range(0, 3)), Vector2(randf_range(-10, 10), -randf_range(6, 18)),
				randf_range(1.0, 2.0), randf_range(1.5, 2.5), Color(0.8, 0.66, 0.48, 0.5), 5.0, WIND * 0.5)
		decals.add(pos, 1.3, Color(0.27, 0.19, 0.13, 0.7))
	world.add_child(puff)


func blood(pos: Vector2, dir: Vector2, height: float) -> void:
	var puff := Puff.new()
	puff.position = pos + Vector2(0, 1)
	for i in 8:
		puff.add(Vector2(0, -height * 0.8), dir.rotated(randf_range(-0.6, 0.6)) * randf_range(20, 60) + Vector2(0, -randf_range(0, 20)),
			randf_range(0.25, 0.5), randf_range(0.8, 1.6), Color(0.55, 0.06, 0.04, 1.0), 0.0, 120.0)
	world.add_child(puff)
	for i in 3:
		decals.add(pos + dir * randf_range(4, 18) + Vector2(randf_range(-4, 4), randf_range(-2, 2)), randf_range(1.0, 2.5), Color(0.38, 0.05, 0.04, 0.85))


## A sound and its alternative takes (name_2 ... name_5).
func _takes(name: String) -> Array[AudioStream]:
	var takes: Array[AudioStream] = [load(meta["sfx"][name])]
	for i in range(2, 6):
		var k := "%s_%d" % [name, i]
		if meta["sfx"].has(k):
			takes.append(load(meta["sfx"][k]))
	return takes


## `dice`: for a sound the seeded tests never had, its own dice rather than the global ones.
func sfx(name: String, pos: Variant = null, vol := 0.0, pitch_var := 0.06, dice: RandomNumberGenerator = null) -> void:
	if not _streams.has(name):
		_streams[name] = _takes(name)
	var takes: Array = _streams[name]
	var stream: AudioStream = takes[dice.randi() % takes.size()] if dice else takes.pick_random()
	var pitch := 1.0 + (dice.randf_range(-pitch_var, pitch_var) if dice else randf_range(-pitch_var, pitch_var))
	var p: Node
	if pos == null:
		var ap := AudioStreamPlayer.new()
		ap.stream = stream
		ap.volume_db = vol
		ap.pitch_scale = pitch
		p = ap
	else:
		var ap2 := AudioStreamPlayer2D.new()
		ap2.stream = stream
		ap2.volume_db = vol
		ap2.pitch_scale = pitch
		ap2.position = pos
		if name in LOUD:
			# gunfire carries right across town
			ap2.max_distance = 4000.0
			ap2.attenuation = 0.5
		else:
			ap2.max_distance = 1200.0
			ap2.attenuation = 1.2
		p = ap2
	if get_tree().paused:
		p.process_mode = Node.PROCESS_MODE_ALWAYS   # (a click on the menu, heard)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
