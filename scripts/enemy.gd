class_name Enemy
extends Actor
## Bandit AI: guard or patrol, grow suspicious of glimpses and noises, fight with a
## reaction delay and aim error, run to cover to reload, search when they lose you.

enum St { GUARD, PATROL, INVESTIGATE, COMBAT, SEARCH, RETURN, POSSE, ERRAND }

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
const LEASH := 140.0   # px: the hangman fights no further than this from his gallows
const LEASH_LOST := 3.0   # s without a sight of the stranger, and he's back to it

var kind := "pistolero"
var foe: Enemy = null    # the other gang's man he's shooting at, the truce broken (see _feuding)
var feud_look := 0.0
var feud_cd := 0.0
var silent_death := false   # knifed unawares: no one hears it (game._on_enemy_died)
var killed_with := ""    # the gun (or "knife", "dynamite") that did for him: who did it? (game.weigh_death)
static var feud_rng := RandomNumberGenerator.new()   # (the street war: its own dice)
# Between the gangs the shooting is slow and wild: they keep their heads down and
# blaze away from cover, so the war drags on and the street stays full of guns.
const FEUD_SPREAD := 3.0   # x his spread, at the other gang's man
const FEUD_PACE := 3.0     # x his time between shots, at the other gang's man
const FEUD_MIN := 20.0     # degrees of spread at the least, whatever his gun: even a rifle misses
const WAR_EAR := 120.0     # px: the war's gunfire this close draws him to it
var gang := ""   # whose side he's on, where a town has two (Silencio's "hunters", "outlaws"): his type's "gang"
var flag_at := Vector2.INF   # the colours in the dirt, and him running to raise them
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
var pool_look := 0.0
var desired := Vector2.DOWN
var repath_t := 0.0
var search_t := 0.0
var strafe_t := 0.0
var strafe_dir := 1.0
var stuck_t := 0.0
var give_way := Vector2.ZERO   # stepping aside for a comrade who can't get past
var give_way_t := 0.0
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
var finishing := false   # the stranger's down: he's walking up to finish him
# The rabble: in the thick of a big fight, with plenty of his own about, a man of the
# rank and file may stand there wasting it: a round loosed at the sky for the noise
# of it, or bawling the others on (data: "rabble", how given he is to it).
const CROWD_R := 240.0       # px round the stranger: his comrades this close make a crowd
const RABBLE_CROWD := 8      # this many and it starts: a big fight, not a posse
const RABBLE_EVERY := 2.0    # s between thinking about it
static var rabble_rng := RandomNumberGenerator.new()
var rabble_cd := 0.0
var rabble_left := 0.0       # s left of it
var rabble_shot := -1.0      # s till the round at the sky (-1: none)
var finish_repath := 0.0
var pinned_t := 0.0      # >0 while rounds are landing near him
# Suppressive fire: blazing away at where the stranger probably is.
var suppress_t := 0.0
var suppress_at := Vector2.ZERO
var covered_t := 0.0     # >0 while comrades cover his move
var hold_t := 0.0        # a beat after calling for cover, before breaking it
var cover_call_cd := 0.0
var blocked_t := 0.0
var single_shot := false   # suppression is a lone harassing shot
# Fire with fire: one of theirs shot at, by a man round a corner none of them can
# see. Those with their wits about them put rounds into the corner he's behind (or
# his blood by it) for a few seconds; not for long, and not again at once.
const RETURN_FOR := Vector2(2.0, 3.5)   # s of it
const RETURN_REST := Vector2(6.0, 9.0)  # s after before he'll do it again
static var return_rng := RandomNumberGenerator.new()
var return_ok_at := 0.0
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
var hangman := false     # keeps to the gallows while there's a man on it (see Hanging)
var captor := false      # stands over the man tied to the pole (see Captive)
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
var break_look := 0.0
var breaking: Dictionary = {}         # he was waiting for him: a moment where nothing pulls him off the shot
# Dynamite: a stick or two for when the stranger keeps killing them from one place
# (see game.dynamite_target). Lit, a moment to wind up, and over it goes.
const THROW_LINES := ["¡Dinamita!", "Duck, you sucker!", "Giù la testa!", "Fire in the hole!"]
const WINDUP := 0.57       # s from lighting it to letting go (matches the "throw" animation)
const FOLLOW := 0.4        # s of follow-through after
var sticks := 0
var stick: Dynamite = null   # lit, in his hand
var throw_at := Vector2.ZERO
var dyn_look := 0.0
var clear_for := 0.0         # how long the fuse he's getting away from has left
var clear_r := Dynamite.R    # and how far it'll reach
# Wounded, he may break off to patch himself up: into cover away from the
# stranger, down on one knee, a bandage round it. One HP back, no more limp or
# bleeding. The stranger walking up on him in plain view breaks it off.
const PATCH_T := 8.0
const PATCH_ABORT := 100.0   # px: the stranger in view this close and he gives it up
const PATCH_LINES := ["I'm hit! Cover me!", "¡Me dieron!", "Just a scratch...", "Damn, I'm bleeding!"]
var bandages := 0
var patching := false
# His blood: a wounded stranger leaves a trail, and a bandit who comes across it
# follows it (see game.trail_lead).
const TRAIL_LINES := ["Blood... he's hit.", "¡Sangre! Por aquí.", "He's bleeding. Follow it."]
const TRACK_LINES := ["Tracks. Fresh ones.", "Somebody came through here...", "Boot prints. Follow 'em."]   # (in the snow: see Footprints)
var trail_t := -1.0          # when the last drop he followed fell
var trail_look := 0.0
# Downed: a hit that would kill may only put him in the dirt instead, out of the
# fight, groaning, bleeding out (BLEED_T) unless a comrade gets to him: dragged into
# cover and bandaged he gets up again (1 HP). While someone has hold of him he
# presses the wound and the clock stops. Another hit, or the knife, finishes him.
const DOWN_CHANCE := 0.35
const BLEED_T := 45.0
const DOWN_LINES := ["¡Ayúdenme!", "Help... me...", "¡Madre de Dios!", "Don't leave me here!", "I'm hit bad..."]
const RESCUE_LINES := ["¡Aguanta, compadre!", "Hang on, amigo!", "Cover me, I'm getting him!", "¡Lo saco yo!"]
const RESCUE_NEAR := 300.0   # px: a comrade this close may go for a downed man
const TREAT_T := 10.0      # s bandaging a downed comrade: long enough for the stranger to spot it
var downed := false
var down_t := 0.0
var groan_t := 0.0
var rescuer: Enemy = null    # who's come for him
var medic: Civilian = null   # the barber-surgeon, if he's come for him instead
var rescuing: Enemy = null   # (as the rescuer) who he's come for
var rescue_phase := ""       # "go", "drag", "treat"
var fetching: Strongbox = null   # (Silencio's trappers) the strongbox he's taking home
var fetch_phase := ""            # "go", "carry"
var smear := Vector2.ZERO
# The last gasp: downed, a pistol to hand and the stranger in sight, he may push
# himself up on an arm and get a shot or three off, slowly, before he sinks back.
const GASP_RANGE := 230.0   # px: the stranger this close, and in sight
const GASP_CLOSE := 120.0   # px: the stranger this close and he doesn't wait for help
const GASP_CLOSE_MULT := 1.6   # (and is that much likelier to try it)
const GASP_HOPE := 0.6      # x the chance while a comrade is near enough to come for him
const GASP_HOLD := 0.8      # s on aim before the first shot
const GASP_EVERY := 2.4     # s between shots: a dying man is slow on the hammer
const GASP_SHOTS := [1, 1, 1, 1, 2, 2, 3]   # how many he gets off (mostly the one)
const GASP_SPREAD := 2.0    # x his usual spread: on his back and bleeding
const GASP_LOST := 3.0      # s the stranger can be out of sight before he gives it up
const GASP_PERISH := 0.5    # chance the effort is the end of him
const GASP_COST := 12.0     # s off his clock if it isn't
const PISTOLS := ["colt", "colts", "schofield", "buntline", "navy", "derringer", "howdah", "pistola"]
# Now and then a man's Colt is a Schofield instead (data "schofield": the chance,
# for his type). Its own dice, so the fights the tests replay stay as they were.
const SCHOFIELD := 0.3
static var schofield_rng := RandomNumberGenerator.new()
# And as many of the gang's Winchesters are the old Henry (data "henry" for his
# type): fifteen rounds, but a slow, awkward gun to keep fed. Its own dice too.
const HENRY := 0.3
static var henry_rng := RandomNumberGenerator.new()
# A man who can afford it may have the new Spencer pump gun for his coach gun (data
# "pump": the chance; El Jefe's). Nobody's does unless his type says. Its own dice.
static var pump_rng := RandomNumberGenerator.new()
# The low end of the gang may carry a Champion single-barrel slung beside the sidearm
# (data "champion": the chance, for his type, or for a wave's arms option). One shot
# from a little further off than a coach gun would reach, and more often than not
# he throws it down and goes to the revolver. Its own dice as well.
const CHAMPION_STYLE := {"range": [50, 180], "draw_sidearm": 0.8, "fires_on_move": false}
static var champion_rng := RandomNumberGenerator.new()
# Now and then a crafty one has a cut-down Rolling Block under his coat beside the
# sidearm (data "rollingblock": the chance). Short, but a rifle's round: one shot
# from the edge of pistol range, then most likely the revolver. Rarer than the
# Champion, and its own dice too.
const ROLLINGBLOCK_STYLE := {"range": [70, 220], "draw_sidearm": 0.7, "fires_on_move": false}
static var rollingblock_rng := RandomNumberGenerator.new()
const FINISH_NEAR := 34.0    # px: as close as a man walking up to finish the stranger comes
const GASP_LINES := ["You first, gringo...", "¡Hasta el infierno!", "Not... alone...", "¡Muere, cabrón!",
	"Come here... stranger..."]
static var gasp_rng := RandomNumberGenerator.new()   # (his own dice: the rest of the fight stays as seeded)

# An army's assault (Paso Esperanza's federales: the map's "assault"): each man comes
# for a spot by the train, not for the stranger. He goes in bounds, cover to cover
# (or to open ground, the less he knows about cover: "cover_use"), and between them
# drops and holds a couple of seconds, shooting if he can see the stranger; pinned
# down, he holds longer. At the train he fights it out from there. Some ("flanker":
# the rurales) make for the train's far side, among the carriers. A cabo or teniente
# now and then has the men about him hold their fire for a volley. A man who's
# lost heart and is given to it ("deserts": the levas) throws it in and runs for the
# road he came by, and is gone. And once, if he's round among the carriers with the
# stranger nowhere near, he may ("hunt", a chance) turn his gun on one of them: one
# kill, and he's back to the stranger. Their own dice.
static var assault_rng := RandomNumberGenerator.new()
const BOUND := Vector2(90.0, 150.0)      # px a bound
const HOLD := Vector2(1.5, 3.2)          # s down between bounds
const HOLD_GREEN := Vector2(0.7, 1.6)    # (a leva hardly stops)
const AT_TRAIN := 30.0                   # px from his spot: he's there
const VOLLEY_WAIT := 1.2                 # s from "¡Apunten!" to "¡Fuego!"
const VOLLEY_NEAR := 200.0               # px: the men he can order
const DESERT_ON_DEATH := 0.04            # chance a man given to it runs, seeing one of his own fall
const HUNT_NEAR := 220.0                 # px: a carrier this near, in sight, the stranger not
const PUSH_CLOSE := 160.0                # px: further than this from the stranger, short of his spot, he pushes in
const PUSH_BOUND := Vector2(150.0, 230.0)   # px a bound, pushing
const PUSH_HOLD := Vector2(0.25, 0.7)    # s down between them, pushing
const FLINCH := 0.15                     # chance a round past him still makes him duck, pushing (a leva twice it)
const GUN_NERVE := 8.0                   # s after the gun's frightened him, before it can again
var gun_nerve := -1.0                    # (the clock till then)
var objective := Vector2.INF             # his spot by the train, till he gets there
var assault := false
var bounding := false
var bound_hold := 0.0
var volley_at := -1.0
var volley_cd := 0.0
var deserting := false
var desert_to := Vector2.INF
var camp_to := Vector2.INF   # his gang's camp, off the map: he's running for more men (Director)
var hunt_rolled := false
var hunting: Civilian = null
var bounds := Vector2i.ZERO              # (bounds made, and how many of them to cover: for the tests)
var gasp := ""               # "", "rise", "aim", "sink"
var gasp_t := 0.0
var gasp_gun := ""
var gasp_left := 0           # shots still in him
var gasp_look := 0.0
var gasp_rolls := 0          # (he makes up his mind once, and once more when it's nearly over)
var gasp_close_rolled := false   # (and once more if the stranger comes right up on him)
var gasp_lost := 0.0
var work_t := 0.0
# The gang's alarm (see game._gang_alarm): how he's answering it, if he is.
const UNEASY_LINES := ["¿Qué pasa allá?", "That's a lot of shooting...", "Hear that?", "Something's wrong."]
const SCOUT_LINES := ["Vamos a ver.", "Come on, let's go look.", "I'll go see."]
const FALLBACK_LINES := ["¡Al refugio!", "Fall back!", "Dig in, boys!", "¡Atrás, todos!"]
const NEWS_LINES := ["He's killing everyone!", "¡Es el diablo!", "They're all dead back there!", "Get ready, he's coming!"]
var alarm_role := ""         # "", "uneasy", "scout", "fortified"
var bearing_news := false    # running from the fight to his comrades

# A peso in the street (the stranger's, tossed with Q: see game.peso_landed): one man
# of the post goes to have it, the others watching him go. He walks over, stoops for
# it with his eyes on the dirt, pockets it and walks back. A second one by the same
# spot and he wonders aloud and has a look round after; a third and it's plain
# somebody's throwing money at them, and the whole post goes to see who. Its own dice.
const PESO_STOOP := 1.4      # s bent over it, his eyes on the ground
const PESO_MATES := 100.0    # px from him: the men of his post, who watch him go
const PESO_HEAR_LINES := ["¿Qué es eso?", "What was that?", "¿Eh?", "Hear that?"]
const PESO_LINES := ["¡Un peso!", "Well, look at that.", "¡Mira nomás!", "Finders keepers."]
const PESO_AGAIN_LINES := ["¿Otra vez?", "Another one?", "Somebody's got a hole in his pocket..."]
const PESO_TRICK_LINES := ["¡Es un truco!", "It's a trick!", "Somebody's throwing money at us."]
static var peso_rng := RandomNumberGenerator.new()
var errand := ""             # "peso": off his post on a little business of his own (St.ERRAND)
var errand_t := 0.0
var errand_peso: Pickup = null
var errand_wise := false     # (the second peso: he'll look about him after)
var watching: Enemy = null   # a mate of his post off on an errand, and him watching him go
var sweetheart: Civilian = null   # a saloon girl at his elbow (Civilian._flirt): eyes only for her

# A man at his post has his habits. Now and then he lights up: a good ten seconds
# fishing in his pockets for a cigar and the matches, head bent to the flame in his
# cupped hand, and he sees little; then he stands there puffing, his eyes his own
# again. And now and then (not in a fight's towns: game.flirting_ok) he has to go:
# off to the nearest wall a short way from his post, his back to the street and his
# gun put by, for a quarter of a minute, then back. A mate of his post (if he has
# one) notices if he's gone too long, and goes to see. Their own dice.
const SMOKE_EVERY := Vector2(60.0, 150.0)   # s at his post between smokes
const SMOKE_LIGHT := 10.0                   # s finding it and getting it lit
const SMOKE_STRIKE := 6.0                   # s in, the match flares
const SMOKE_PUFF := Vector2(30.0, 60.0)     # s he stands there smoking it after
const NATURE_EVERY := Vector2(100.0, 260.0) # s at his post between calls of nature
const NATURE_T := Vector2(12.0, 18.0)       # s at it
const NATURE_FAR := Vector2(40.0, 130.0)    # px from his post: the wall he goes to
const NATURE_MISSED := 40.0                 # s gone, and a mate goes to look for him
const NATURE_LINES := ["Ahorita vuelvo.", "Back in a minute.", "Cover for me.", "Nature calls, amigo."]
const MISSED_LINES := ["¿Pepe?", "Where'd he get to?", "¿Dónde se metió?", "He's taking his time..."]
static var habit_rng := RandomNumberGenerator.new()
var smoke_at := INF          # game.clock of his next smoke
var smoke_t := -1.0          # time into lighting up; < 0 when not
var puff_until := -1.0       # game.clock: smoking it till then
var nature_at := INF         # game.clock of his next call of nature
var errand_at := Vector2.ZERO    # where he's gone (the wall), and how he'll face it
var errand_face := Vector2.DOWN
var errand_since := 0.0      # game.clock he set off
var errand_len := 0.0        # s he'll be at it
var waiting_on: Enemy = null # a mate gone off on a call of nature, and him keeping count
var ember: Node2D            # the match, the cigar's glow and its smoke

# In from the squall (Silencio's: see Snowfall). As one comes down, each man at his
# post or on his rounds makes up his own mind whether to go in out of it: off to the
# nearest door, and inside, the fire lit (Hearth). He stays through it and a while
# after by the stove, then back to his post. Shooting he can hear brings him out, but
# not at once: it takes him 5-10 s, by how cozy he'd got, and then he goes to it.
# Inside he sees nothing and nobody sees him. Their own dice.
const SHELTER := 0.4                        # chance he goes in, each squall
const SHELTER_REACH := 360.0                # px: a door further off than this, and he sticks it out
const SHELTER_LINGER := Vector2(20.0, 60.0) # s by the stove after the squall's blown out
const SHELTER_OUT := Vector2(5.0, 10.0)     # s from hearing the shooting to coming out of the door
const SHELTER_LINES := ["Too damn cold.", "To hell with this, I'm going in.", "I can't feel my feet.", "Back when it lets up."]
static var shelter_rng := RandomNumberGenerator.new()
var indoors := false
var shelter_house: Dictionary = {}
var shelter_door := Vector2.ZERO
var shelter_rolled := -1     # the last squall he made up his mind about
var shelter_until := INF     # game.clock: out again (the squall over, a while by the stove)
var out_at := INF            # game.clock: out to the shooting
var called_to := Vector2.INF # where the shooting was

# Warming up (Silencio's campfires: see Campfire): now and then a man whose post is
# near a fire that's going walks over and holds his hands out to it a while, the gun
# slung and his eyes on the flames, then back to his post. Two at a fire at most. A
# post whose fire has gone out is a cold one: come a squall, its men are the quicker
# to go in out of it. Their own dice.
const WARM_NEAR := 150.0                 # px from his post: the fire he'll go to
const WARM_EVERY := Vector2(60.0, 180.0) # s between warmings
const WARM_T := Vector2(15.0, 25.0)      # s at it
const SHELTER_COLD := 0.65               # chance he goes in out of a squall, his fire out
static var warm_rng := RandomNumberGenerator.new()
var warm_at := INF           # game.clock of his next warming
var warm_fire: Campfire = null


## Everything that makes this bandit who he is comes from his type in
## data/enemies.json (merged over the defaults, then any per-placement overrides).
func setup(g: Node, k: String, pos: Vector2, route: PackedVector2Array, facing_deg: float, overrides := {}) -> void:
	setup_body(g, pos)
	kind = k
	tdata = g.enemy_type(k, overrides)
	gang = tdata.get("gang", "")
	loadout = _pick_loadout()
	var single: float = tdata.get("champion", 0.0)
	if single > 0.0 and loadout.size() == 1 and loadout[0] in PISTOLS and not tdata.get("pistols_only", false) \
			and not tdata["concealed"] and champion_rng.randf() < single:
		loadout = ["champion"] + loadout
		for key in CHAMPION_STYLE:
			tdata[key] = CHAMPION_STYLE[key]
	var cut: float = tdata.get("rollingblock", 0.0)
	if cut > 0.0 and loadout.size() == 1 and loadout[0] in PISTOLS and not tdata.get("pistols_only", false) \
			and not tdata["concealed"] and rollingblock_rng.randf() < cut:
		loadout = ["rollingblock"] + loadout
		for key in ROLLINGBLOCK_STYLE:
			tdata[key] = ROLLINGBLOCK_STYLE[key]
	var top: float = tdata.get("schofield", SCHOFIELD)
	loadout = loadout.map(func(gun): return "schofield" if gun == "colt" and schofield_rng.randf() < top else gun)
	var old: float = tdata.get("henry", HENRY)
	loadout = loadout.map(func(gun): return "henry" if gun == "rifle" and henry_rng.randf() < old else gun)
	var pump: float = tdata.get("pump", 0.0)
	loadout = loadout.map(func(gun): return "spencer82" if gun == "coach" and pump > 0.0 and pump_rng.randf() < pump else gun)
	stats = {"keep": _v2(tdata["range"]) * game.haze.x, "cadence": _v2(tdata["cadence"])}
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
	roll_habits()
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
	sticks = int(tdata["dynamite"])
	bandages = int(tdata["bandages"])
	hangman = tdata.get("hangman", false)
	cone = VisionCone.new()
	cone.enemy = self
	g.cone_layer.add_child(cone)
	if tdata.get("flag", "") == "bearer":
		anim_gun = "banner"   # the colours in the crook of his arm, a Navy in his hand
	if tdata["concealed"]:
		# looks like any other townsman: gun out of sight, no tell-tale view cone
		revealed = false
		anim_gun = "unarmed"
		cone.visible = false


## His guns: the type's loadout, or one of its weighted "loadouts" picked at random.
## Caught indoors ("pistols_only"), he comes out with whatever handgun he had on him:
## his long gun's back in the rack.
func _pick_loadout() -> Array:
	var options: Array = tdata.get("loadouts", [])
	if tdata.get("pistols_only", false):
		if options.is_empty():
			options = [{"guns": tdata["loadout"]}]
		options = options.filter(func(o): return o["guns"][0] in PISTOLS)
		if options.is_empty():
			var short: Array = tdata["loadout"].filter(func(g): return g in PISTOLS)
			tdata["range"] = [60, 170]
			return short if not short.is_empty() else ["navy"]
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


## Carrying the colours?
func carries_flag() -> bool:
	return anim_gun == "banner"


## The colours are down: he's the one to run and get them up again, whatever's
## flying.
func raise_flag(at: Vector2) -> void:
	flag_at = at
	if reaction == "rescue":
		_end_rescue()   # (the man he was going for waits for someone else)
	reaction = ""
	pending = ""
	path_to(at)
	_say(_line("flag", ["¡La bandera!", "¡Levántenla!"]))


func _to_flag() -> void:
	crouched = false
	if global_position.distance_to(flag_at) < 14.0:
		flag_at = Vector2.INF
		game.take_up_flag(self)
		return
	if path.is_empty() or path[path.size() - 1].distance_to(flag_at) > 20.0 or path_i >= path.size():
		path_to(flag_at)   # (whatever else he was about, it's the colours now)
	if follow_path(run):
		velocity = (flag_at - global_position).normalized() * run   # the last step, onto them


## The colours up in his left hand: his long gun dropped, a Navy in the right.
func take_flag() -> void:
	game.drop_gun(self)
	weapon = Weapon.new("navy", self)
	weapon.reserve = 999
	anim_gun = "banner"
	set_meta("raised", true)
	_say(_line("raised", ["¡Arriba la bandera!", "¡Viva México!"]))
	_log("takes up the colours")


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
	return VIEW * (1.2 if wary or st == St.COMBAT else 1.0) * game.sight * eyes().x   # (snow falling, a squall: see Snowfall)


func half_fov() -> float:
	return FOV * 0.5 * (1.4 if wary or st == St.COMBAT else 1.0) * eyes().y


## How much his mind's on watching: (reach, width) of his eyes, cut down while he's
## busy with something else (stooped for a peso, a saloon girl at his elbow,
## lighting up, at the wall, or his hands out to a fire).
func eyes() -> Vector2:
	if st == St.ERRAND and errand == "peso" and errand_t > 0.0:
		return Vector2(0.45, 0.6)
	if sweetheart and st == St.GUARD and sweetheart.st == Civilian.St.FLIRT:
		return Vector2(0.3, 0.45)
	if smoke_t >= 0.0 and st == St.GUARD:
		return Vector2(0.35, 0.5)
	if st == St.ERRAND and (errand == "nature" or errand == "warm") and errand_t > 0.0:
		return Vector2(0.3, 0.45)
	return Vector2.ONE


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
		if gang != "":
			game.gang_sees_him(gang)
	if st == St.COMBAT:
		if sees_player:
			last_known = p.global_position
			lost_t = 0.0
		else:
			lost_t += delta
			var lead := _blood(delta)
			if not lead.is_empty():
				last_known = lead["at"]   # gone to ground, but he's left a trail
				lost_t = minf(lost_t, 3.0)
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
	pool_look -= delta
	if pool_look <= 0.0:
		pool_look = 0.5
		_look_at_pools()
	var lead := _blood(delta)
	if not lead.is_empty():
		_follow_blood(lead)


func hear(pos: Vector2, radius: float, k: String, source: Node) -> void:
	if not alive or game.state != "play" or source == self:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	if indoors:
		if k in ["shot", "enemy_shot", "blast", "struggle", "scream"]:
			call_out(pos)
		return
	match k:
		"shot", "struggle":   # gunfire, or a man yelling as the knife goes in
			if st == St.COMBAT:
				if not sees_player:
					last_known = pos
					lost_t = 0.0
					if k == "shot":
						_return_fire(pos)
			elif d < radius * 0.6:
				enter_combat(pos, false, true)
				queue_reaction(pos, false)
				if k == "shot":
					_return_fire(pos)
			elif not revealed:
				pass   # a distant shot: let someone else go and look
			else:
				suspicion = max(suspicion, 0.6)
				start_investigate(pos, true)
		"blast":   # his own side's dynamite: the fight's there, wherever the stranger is
			if st != St.COMBAT:
				if d < radius * 0.6:
					enter_combat(game.seen_pos if game.staleness() < 15.0 else pos, false, true)
				else:
					start_investigate(pos, true)
		"enemy_shot":
			if st != St.COMBAT and source is Enemy:
				if game.war and (source.gang != gang or source.foe != null):
					if foe == null and revealed and reaction == "":
						# the street war: close by, he goes to it; further off he stays where he
						# is, wary (the gang's pushes do the moving: see game._war_tick)
						if d < WAR_EAR:
							start_investigate(pos, true)
						else:
							wary = true
				else:
					enter_combat(source.last_known, false, false)
		"scream":   # a townsman crying murder at what the stranger's doing, there
			if st != St.COMBAT and revealed:
				wary = true
				suspicion = maxf(suspicion, 0.7)
				start_investigate(pos, true)
		"step":
			if not revealed:
				return   # footsteps are no business of a townsman's
			if st != St.COMBAT and st != St.INVESTIGATE:
				suspicion = min(0.9, suspicion + 0.3)
				desired = (pos - global_position).normalized()
				if suspicion > 0.5:
					start_investigate(pos, false)


func alert_to(pos: Vector2) -> void:
	if indoors:
		call_out(pos)
		return
	if alive and st != St.COMBAT:
		enter_combat(pos, false, false)


func enter_combat(pos: Vector2, spotted: bool, propagate: bool) -> void:
	if indoors:
		call_out(pos)
		return
	reveal()
	smoke_t = -1.0
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
	if indoors:
		call_out(pos)
		return
	reveal()
	if st == St.COMBAT:
		return
	if st == St.ERRAND:
		errand = ""   # (whatever it was can wait)
		errand_t = 0.0
		crouched = false
	smoke_t = -1.0
	st = St.INVESTIGATE
	look_t = 0.0
	running = run
	_mark("?")
	path_to(pos)


# ------------------------------------------------------------------ the gang's alarm

## A fight going on somewhere else: off his rounds, eyes that way, on edge.
func get_uneasy(at: Vector2) -> void:
	if alarm_role != "" or st == St.COMBAT:
		return
	alarm_role = "uneasy"
	wary = true
	if patrol.size() > 1:
		home = global_position   # he stops where he is
		patrol = PackedVector2Array()
		st = St.GUARD
		path = PackedVector2Array()
	home_facing = (at - home).normalized()
	if shout_t <= 0.0 and randf() < 0.4:
		_say(_line("uneasy", UNEASY_LINES))
	_log("uneasy")


## Sent with another to see what the shooting's about.
func scout(at: Vector2) -> void:
	alarm_role = "scout"
	set_meta("scout", true)
	start_investigate(at, true)
	if shout_t <= 0.0 and randf() < 0.6:
		_say(_line("scout", SCOUT_LINES))
	_log("scouts")


## His general's fallen: shaken to the core, the heart gone out of him; one with
## little nerve left turns tail.
func lose_heart() -> void:
	shaken = 1.0
	nerve *= 0.6
	if assault and tdata.get("deserts", false):
		desert()
		return
	if reaction in ["", "point", "flinch"] and randf() < 0.6 * (1.0 - nerve):
		threat = game.seen_pos if game.seen_pos != Vector2.ZERO else global_position
		start_reaction("flee")
		_log("loses heart")
	else:
		_log("wavers at the news")


## Come in down a road with nothing going on that he can hear: on to the middle of
## town, wary, to wait there looking about.
func arrive(spot: Vector2, from: Vector2) -> void:
	wary = true
	home = spot
	home_facing = (spot - from).normalized()
	patrol = PackedVector2Array()
	st = St.RETURN
	path_to(spot)
	_log("arrives")


## Falling back to the holdout: a new post there, facing the way he'll come.
func fortify(spot: Vector2, at: Vector2) -> void:
	alarm_role = "fortified"
	wary = true
	home = spot
	home_facing = (at - spot).normalized()
	patrol = PackedVector2Array()
	st = St.RETURN
	path_to(spot)
	if shout_t <= 0.0 and randf() < 0.5:
		_say(_line("fallback", FALLBACK_LINES))
	_log("falls back")


## Made it to the others with the news?
func _tell_news() -> bool:
	for o in game.enemies:
		if o != self and o.alive and o.revealed and o.st != St.COMBAT and o.gang == gang \
				and o.global_position.distance_to(global_position) < 50.0:
			bearing_news = false
			velocity = Vector2.ZERO
			_say(_line("news", NEWS_LINES))
			game.news(self, threat)
			_log("brings the news")
			reaction_t = minf(reaction_t, 1.5)
			return true
	return false


## Every so often: any fresh drops of the stranger's blood in view?
func _blood(delta: float) -> Dictionary:
	trail_look -= delta
	if trail_look > 0.0 or not revealed:
		return {}
	trail_look = 0.6
	var lead: Dictionary = game.trail_lead(self, trail_t)
	if not lead.is_empty():
		trail_t = lead["t"]
	return lead


## Off along the trail, drop by drop, to where it's freshest.
func _follow_blood(lead: Dictionary) -> void:
	last_known = lead["at"]
	if st != St.SEARCH:
		wary = true
		st = St.SEARCH
		running = false
		_mark("?")
		if shout_t <= 0.0:
			_say(_line("tracks", TRACK_LINES) if lead.get("print", false) else _line("blood", TRAIL_LINES))
		_log("follows the tracks" if lead.get("print", false) else "follows the blood")
	search_t = maxf(search_t, 12.0)
	wait = 0.0
	path_to(lead["at"])


## A pool of blood where a man fell, and nobody lying in it: someone's moved him.
## Not the alarm a body is, but he goes and looks.
func _look_at_pools() -> void:
	for pl in game.blood_pools:
		var b: Enemy = pl["body"]
		if self in pl["known"] or b == self or not is_instance_valid(b) or b.has_meta("buried") \
				or b.global_position.distance_to(pl["at"]) < 40.0:
			continue
		if visibility_of(pl["at"], true, false) > 0.0:
			pl["known"].append(self)
			if st != St.COMBAT and st != St.SEARCH:
				wary = true
				suspicion = maxf(suspicion, 0.5)
				start_investigate(pl["at"], false)
				_mark("?")
				_log("finds a pool")


func _found_corpse(e: Enemy) -> void:
	game.weigh_death(self, e)   # (one of theirs? whose doing?)
	if st == St.COMBAT:
		return
	if game.war and is_instance_valid(e.killer) and e.killer is Enemy and e.killer.gang != gang:
		wary = true   # the street war's: nothing to go and look at, out there in their sights
		return
	wary = true
	st = St.SEARCH
	search_t = 10.0
	last_known = e.global_position
	running = true
	path_to(e.global_position)
	_mark("!")
	for o in game.enemies:
		if o != self and o.alive and o.gang == gang and o.global_position.distance_to(global_position) < 220.0 and o.st != St.COMBAT:
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
	if pushing():
		# far out under the gun: lying there is death, the only way is in
		shaken = min(1.0, shaken + 0.05)
		_engage(from)
		if fear_cd <= 0.0:   # (a chance to flinch every few seconds, not every round)
			if assault_rng.randf() < FLINCH * (2.0 if tdata.get("deserts", false) else 1.0):
				queue_reaction(from, true)
			else:
				fear_cd = 3.0
		return
	shaken = min(1.0, shaken + 0.15 * (1.0 - bold * 0.6))
	pinned_t = 2.5 * (1.0 - bold * 0.7)
	_engage(from)
	queue_reaction(from, true)


## A comrade dropped near him: if he saw it, it shakes him badly and he always
## reacts. Out of sight it only tells him where the fight is.
func witness_death(at: Vector2, killer: Vector2, dead: Enemy = null) -> void:
	if not alive:
		return
	if dead and game.at_war(self, dead.killer) or (dead and is_instance_valid(dead.killer) and dead.killer is Enemy and dead.killer.gang == gang):
		# the street war: the other gang's doing (or his own side's, at one of them),
		# nothing to do with the stranger; his man to shoot back at, if it's theirs
		if dead.killer is Enemy and dead.killer.gang != gang and dead.killer.alive:
			foe = dead.killer
		shaken = min(1.0, shaken + 0.15 * (1.0 - nerve * 0.5))
		return
	if dead and dead.silent_death and visibility_of(game.player.global_position, game.player.low_profile()) <= 0.0:
		# he saw a comrade drop without a sound, and not who did it: as good as
		# finding him dead, no more (no knowing where the stranger is)
		shaken = min(1.0, shaken + 0.25 * (1.0 - nerve * 0.5))
		if not known_corpses.has(dead):
			known_corpses.append(dead)
			_found_corpse(dead)
		return
	if not game.line_of_sight(global_position, at, false):
		_engage(killer)
		return
	shaken = min(1.0, shaken + 0.35 * (1.0 - nerve * 0.5))
	if assault and tdata.get("deserts", false) and assault_rng.randf() < DESERT_ON_DEATH * (0.5 + shaken):
		desert()
		return
	_engage(killer)
	if pushing():
		return   # (no stopping for the fallen, out there)
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
	if not alive or pending != "" or (fear_cd > 0.0 and not forced) or flag_at != Vector2.INF:
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
	if reaction == "rescue" and r != "rescue":
		_end_rescue()   # (cut short: the man he was going for waits for someone else)
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
			# away from him, to the others if he can: they'll want to know
			var to: Vector2 = game.comrades_to_tell(self, threat)
			bearing_news = to != Vector2.INF
			if bearing_news:
				reaction_t = 25.0
				path_to(to)
			else:
				path_to(game.point_away(global_position, threat, 220.0))
			_say(_line("flee", FLEE_LINES))
		"throw":
			reaction_t = WINDUP + FOLLOW
			desired = (throw_at - global_position).normalized()
			play_action("throw")
			stick = game.light_stick(self)
			_say(_line("dynamite", THROW_LINES))
		"rescue", "fetch":
			reaction_t = 30.0
		"patch":
			cover_pos = game.find_cover(global_position, threat)
			patching = cover_pos == Vector2.INF   # nowhere to go: he does it where he is
			if patching:
				reaction_t = PATCH_T
				game.sfx("tear", global_position, -8.0, 0.1)
			else:
				path_to(cover_pos)
				reaction_t = 6.0
			if shout_t <= 0.0:
				_say(_line("patch", PATCH_LINES))
			_log("goes to patch up")
		"clear":
			# a lit stick by his boots: run, anywhere out of its reach, then get down
			reaction_t = clear_for + 0.5
			path_to(game.point_away(global_position, threat, clear_r + 30.0))
			if shout_t <= 0.0 and randf() < 0.6:
				_say(_line("scare", SCARE_LINES))
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
		"throw":
			desired = (throw_at - global_position).normalized()
			aiming = true
			if stick and reaction_t <= FOLLOW:
				_let_fly()
		"patch":
			_patch()
		"rescue":
			_rescue(delta)
		"fetch":
			_fetch()
		"clear":
			if follow_path(run * 1.2):
				crouched = true
				desired = (threat - global_position).normalized()
		"flee":
			if bearing_news and _tell_news():
				return
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
		if reaction == "fetch":
			let_go_of_box()
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
		if downed and game.state in ["play", "won"]:
			_downed_tick(delta)
		if dying() or gasp != "":
			update_anim(delta)
		return
	if game.state != "play" and game.state != "lost":
		velocity = Vector2.ZERO
		update_anim(delta)
		cone.refresh()
		return
	if indoors:
		_indoors()
		return
	if game.snowfall and game.state == "play":
		_think_shelter()
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
	if hangman and game.hanging and game.hanging.holds(self):
		_at_gallows(delta)
	elif deserting:
		_desert_run()
	elif camp_to != Vector2.INF:
		_camp_run(delta)
	elif flag_at != Vector2.INF:
		_to_flag()   # (the colours first, whatever's flying)
	elif game.captive and game.captive.holds(self):
		_at_pole(delta)
	elif is_staggered():
		velocity = Vector2.ZERO   # reeling from the hit
	elif reaction != "":
		_do_reaction(delta)
		_panic_fire()
	elif _feuding(delta):
		pass
	else:
		_run_state(delta)
		if st == St.COMBAT:
			_leader_orders()
	if posted() and not game.holding(self) and not is_staggered():
		_tether()
	velocity *= limp_factor()
	if give_way_t > 0.0:
		give_way_t -= delta
		velocity = give_way
	var own_velocity := velocity
	if st != St.GUARD and not (st == St.ERRAND and errand_t > 0.0 and (errand == "warm" or errand == "nature")):
		_separate()   # (one at a fire or a wall holds his place: the one coming up finds his own)
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
	if ember:
		ember.queue_redraw()


func _run_state(delta: float) -> void:
	if runner_to != Vector2.INF:
		_run_for_help(delta)
		return
	if flag_at != Vector2.INF:
		_to_flag()
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
			if follow_path(run if alarm_role == "fortified" else walk):   # (falling back, he runs)
				st = St.PATROL if patrol.size() > 1 else St.GUARD
		St.POSSE:
			_posse(delta)
		St.ERRAND:
			_errand(delta)


func _check_stuck(delta: float, before: Vector2) -> void:
	if velocity.length() > 10.0 and global_position.distance_to(before) < velocity.length() * delta * 0.25:
		stuck_t += delta
		if stuck_t > 0.6 and path.size() > 0:
			stuck_t = 0.0
			if not _ask_way(velocity.normalized()):
				path_to(path[path.size() - 1])
	else:
		stuck_t = 0.0


## A comrade standing still in the way (in an alley, a gap by a wall): he steps
## aside, off the line, for a moment. (A new path would only run into him again.)
func _ask_way(dir: Vector2) -> bool:
	for e in game.enemies:
		if e == self or not e.alive or e.give_way_t > 0.0 or e.velocity.length() > 15.0:
			continue
		var d: Vector2 = e.global_position - global_position
		if d.length() > 24.0 or d.normalized().dot(dir) < 0.5:
			continue
		var side := dir.orthogonal()
		if side.dot(d) < 0.0:
			side = -side   # (whichever side of the line he's already on)
		for s in [side, -side, dir]:
			if game.is_free(e.global_position + s * 20.0):
				e.give_way = s * e.walk
				e.give_way_t = 0.8
				_log("makes way")
				return true
	return false


func _guard(delta: float) -> void:
	if global_position.distance_to(home) > 6.0:
		smoke_t = -1.0
		if path.is_empty() or path_i >= path.size():
			path_to(home)
		follow_path(walk)
		return
	velocity = Vector2.ZERO
	desired = home_facing.rotated(sin(t * 0.5) * 0.7)
	if _habits(delta):
		return
	if sweetheart:
		if is_instance_valid(sweetheart) and sweetheart.alive and sweetheart.beau == self \
				and sweetheart.st in [Civilian.St.TO_BEAU, Civilian.St.FLIRT]:
			if sweetheart.st == Civilian.St.FLIRT:
				desired = (sweetheart.global_position - global_position).normalized()
			return
		sweetheart = null
	if watching:
		if is_instance_valid(watching) and watching.alive and watching.st == St.ERRAND:
			desired = (watching.global_position - global_position).normalized()
		else:
			watching = null


## The hangman's place is at the foot of the gallows steps till the man's dropped,
## whatever the town gets up to: no running to the fight, no ducking from it. Only
## the stranger in his own sights moves him, and then it's to the lever.
func _at_gallows(delta: float) -> void:
	reaction = ""
	pending = ""
	hiding = false
	crouched = false
	if not path.is_empty() and path[path.size() - 1].distance_to(home) > 6.0:
		path = PackedVector2Array()   # (a fright had him off to cover: not while there's a man to hang)
	if game.hanging.state == "lever":
		velocity = Vector2.ZERO
		desired = (game.hanging.trap - global_position).normalized()
		pose = "point"
		return
	if sees_player and (st == St.COMBAT or suspicion >= 1.0):
		game.hanging.spotted(self)
		return
	if st == St.COMBAT and lost_t > 9.0:
		st = St.GUARD   # it's gone quiet round the gallows: back to watching, a bit warier
		wary = true
	_guard(delta)
	if st == St.COMBAT and velocity == Vector2.ZERO:
		desired = (last_known - global_position).normalized()   # (watching for him where it's coming from)


## Over the man at the pole with his gun at his head, counting (the guard, or El
## General come out to do it himself): he goes straight there, whatever's flying,
## and stays, his gun on nobody but the man. (Captive does the counting.)
func _at_pole(delta: float) -> void:
	if reaction == "throw" and stick:
		_do_reaction(delta)   # (a lit stick in his hand: that first)
		return
	if reaction == "rescue":
		_end_rescue()   # (the man he was going for waits for someone else)
	reaction = ""
	pending = ""
	hiding = false
	crouched = false
	var spot: Vector2 = game.captive.spot_for(self)
	if global_position.distance_to(spot) > 8.0:
		if path.is_empty() or path[path.size() - 1].distance_to(spot) > 6.0:
			path_to(spot)
		follow_path(run)
		return
	velocity = Vector2.ZERO
	desired = (game.captive.man.global_position - global_position).normalized()
	aiming = true


## Kept to one place for the whole level: the hangman by his gallows, the captor by
## his pole. Neither goes with the posse, runs for the reserve or fetches the wounded.
func posted() -> bool:
	return hangman or captor


## The hangman once the hanging's done with, one way or another: still the gallows'
## man (and the captor, the pole's). He fights the stranger while he can see him, but not from further off than
## LEASH; lose him a moment, or be sent anywhere at all (a search, a scout, the
## saloon), and he walks back to his place by the steps.
func _tether() -> void:
	runner_to = Vector2.INF
	if reaction == "flee":
		reaction = ""   # (he doesn't run off and leave it)
	var away := global_position.distance_to(home)
	if st == St.COMBAT and lost_t < LEASH_LOST:
		if away > LEASH and velocity.dot(home - global_position) <= 0.0:
			velocity = (home - global_position).normalized() * run   # (backing up to it, still shooting)
		return
	if reaction != "":
		return   # (ducking a near miss: a moment, then back)
	if st == St.COMBAT:
		wary = true
	if away < 8.0:
		if st != St.GUARD:
			st = St.GUARD
			path = PackedVector2Array()
		return
	if st != St.RETURN or path.is_empty() or path[path.size() - 1].distance_to(home) > 6.0:
		st = St.RETURN
		path_to(home)
	follow_path(run if away > LEASH else walk)


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


## Could a peso clinking down lure him off: at his post or on his rounds, calm, his
## own man (not one passing as townsfolk, not tied to a gallows or a posse).
func can_be_lured() -> bool:
	return alive and revealed and st in [St.GUARD, St.PATROL, St.RETURN] and reaction == "" \
		and not posted() and not in_posse and not deserting and runner_to == Vector2.INF \
		and flag_at == Vector2.INF and not is_staggered()


## A peso clinked down by him (`times`: how many have before, by that spot, lately).
func go_for_peso(c: Pickup, times: int) -> void:
	var mates: Array[Enemy] = []
	for e in game.enemies:
		if e != self and e.can_be_lured() and e.st == St.GUARD \
				and e.global_position.distance_to(global_position) < PESO_MATES:
			mates.append(e)
	if times >= 2:   # money from heaven three times over: someone's having them on
		_say(_line("peso_trick", PESO_TRICK_LINES, peso_rng))
		for e in [self] + mates:
			e.suspicion = maxf(e.suspicion, 0.6)
			e.wary = true
			e.start_investigate(c.global_position, true)
		_log("peso trick")
		return
	smoke_t = -1.0   # (the smoke can wait)
	st = St.ERRAND
	errand = "peso"
	errand_t = 0.0
	errand_peso = c
	errand_wise = times == 1
	c.set_meta("claimed", self)
	_mark("?")
	if peso_rng.randf() < 0.6:
		_say(_line("peso_hear", PESO_HEAR_LINES, peso_rng))
	path_to(c.global_position)
	for e in mates:
		e.watching = self
	_log("peso lure")


func _errand(delta: float) -> void:
	match errand:
		"peso":
			_peso_errand(delta)
		"nature":
			_nature_errand(delta)
		"shelter":
			_shelter_errand()
		"warm":
			_warm_errand(delta)
		_:
			_go_back()


func _peso_errand(delta: float) -> void:
	var c := errand_peso
	if not is_instance_valid(c) or c.is_queued_for_deletion():
		errand = ""   # (picked up from under his nose)
		_go_back()
		return
	if errand_t <= 0.0 and global_position.distance_to(c.global_position) > 10.0 and not follow_path(walk):
		return
	velocity = Vector2.ZERO
	crouched = true
	desired = (c.global_position - global_position).normalized() if global_position.distance_to(c.global_position) > 2.0 else facing
	errand_t += delta
	if errand_t < PESO_STOOP:
		return
	crouched = false
	c.queue_free()
	game.stats["pesos taken"] = game.stats.get("pesos taken", 0) + 1
	errand = ""
	errand_t = 0.0
	if errand_wise:
		_say(_line("peso_again", PESO_AGAIN_LINES, peso_rng))
		wary = true
		start_investigate(global_position, false)   # (and a good look round)
	else:
		if peso_rng.randf() < 0.7:
			_say(_line("peso", PESO_LINES, peso_rng))
		_go_back()


# ------------------------------------------------------------------ habits

## His first smoke and call of nature, some way into the level (game._spawn_actors).
func roll_habits() -> void:
	smoke_at = game.clock + habit_rng.randf_range(SMOKE_EVERY.x * 0.3, SMOKE_EVERY.y)
	nature_at = game.clock + habit_rng.randf_range(NATURE_EVERY.x * 0.3, NATURE_EVERY.y)


## At his post with nothing going on: a smoke, or a call of nature. True while he's
## busy lighting up (nothing else for him to do meanwhile).
func _habits(delta: float) -> bool:
	if waiting_on:
		_count_the_minutes()
	if smoke_t >= 0.0:
		smoke_t += delta
		pose = "smoke"
		desired = home_facing.rotated(0.4)   # (turned a little, out of the wind)
		if smoke_t >= SMOKE_STRIKE and smoke_t - delta < SMOKE_STRIKE:
			game.sfx("match", global_position, -10.0, 0.08, habit_rng)
		if smoke_t >= SMOKE_LIGHT:
			smoke_t = -1.0
			puff_until = game.clock + habit_rng.randf_range(SMOKE_PUFF.x, SMOKE_PUFF.y)
			smoke_at = puff_until + habit_rng.randf_range(SMOKE_EVERY.x, SMOKE_EVERY.y)
		return true
	if not _at_ease():
		return false
	if game.clock >= nature_at and game.flirting_ok() and has_anim(_upper_key("relieve")):
		nature_at = game.clock + habit_rng.randf_range(NATURE_EVERY.x, NATURE_EVERY.y)
		if _go_off_for_nature():
			return true
	if not game.fires.is_empty() and _think_warm():
		return true
	if game.clock >= smoke_at and game.clock > puff_until and has_anim(_upper_key("smoke")):
		smoke_t = 0.0
		game.stats["smokes"] = game.stats.get("smokes", 0) + 1
		_light_ember()
		return true
	return false


## Standing his post, calm, nobody at his elbow, nobody of his post off already.
func _at_ease() -> bool:
	return revealed and st == St.GUARD and alarm_role == "" and not in_posse and not posted() \
		and reaction == "" and suspicion < 0.2 and sweetheart == null and watching == null \
		and waiting_on == null and not sees_player and game.quiet_for() > 20.0


## Off to the nearest wall a little way from his post, his back to the street (or,
## with none handy, a little way off with his back to his post).
func _go_off_for_nature() -> bool:
	var best := INF
	var spot := Vector2.INF
	var face := Vector2.ZERO
	var turn := habit_rng.randf() * TAU
	for i in 16:
		var dir := Vector2.from_angle(turn + TAU * i / 16.0)
		var hit: Dictionary = game.ray(home, home + dir * NATURE_FAR.y, Iso.LAYER_WALL)
		if hit.is_empty():
			continue
		var d := home.distance_to(hit["position"])
		if d < NATURE_FAR.x or d >= best:
			continue
		var at: Vector2 = hit["position"] + hit["normal"] * 9.0
		var way: PackedVector2Array = game.find_path(home, at)
		if way.is_empty() or way[way.size() - 1].distance_to(at) > 8.0:
			continue
		best = d
		spot = at
		face = -hit["normal"]
	if spot == Vector2.INF:   # no wall handy: a little way off, his back to his post
		for i in 8:
			var dir := Vector2.from_angle(turn + TAU * i / 8.0)
			var at: Vector2 = home + dir * habit_rng.randf_range(70.0, 100.0)
			if not game.ray(home, at, Iso.LAYER_WALL | Iso.LAYER_COVER).is_empty():
				continue
			var way: PackedVector2Array = game.find_path(home, at)
			if way.is_empty() or way[way.size() - 1].distance_to(at) > 8.0:
				continue
			spot = at
			face = dir
			break
	if spot == Vector2.INF:
		return false
	for e in game.enemies:
		if e != self and e.alive and e.st == St.GUARD and e.revealed and e.waiting_on == null \
				and e.home.distance_to(home) < PESO_MATES:
			e.waiting_on = self   # (his mate keeps count)
			break
	st = St.ERRAND
	errand = "nature"
	errand_t = 0.0
	errand_at = spot
	errand_face = face
	errand_since = game.clock
	errand_len = habit_rng.randf_range(NATURE_T.x, NATURE_T.y)
	path_to(spot)
	if habit_rng.randf() < 0.5:
		_say(_line("nature", NATURE_LINES, habit_rng))
	game.stats["calls of nature"] = game.stats.get("calls of nature", 0) + 1
	return true


func _nature_errand(delta: float) -> void:
	if errand_t <= 0.0 and global_position.distance_to(errand_at) > 6.0 and not follow_path(walk):
		return
	velocity = Vector2.ZERO
	desired = errand_face
	pose = "relieve"
	errand_t += delta
	if errand_t >= errand_len:
		errand = ""
		errand_t = 0.0
		_go_back()


## A mate of his post off on a call of nature: back, and that's that; gone too long
## (or he's heard him go quiet for good), and he goes to see where he's got to.
func _count_the_minutes() -> void:
	var m := waiting_on
	if not is_instance_valid(m) or (m.alive and not (m.st == St.ERRAND and m.errand == "nature")):
		waiting_on = null
		return
	if game.clock - m.errand_since < NATURE_MISSED:
		return
	waiting_on = null
	_say(_line("missed", MISSED_LINES, habit_rng))
	start_investigate(m.errand_at if m.alive else m.global_position, false)
	_log("missed mate")


## The match, then the cigar's glow and a thread of smoke, at his mouth.
func _light_ember() -> void:
	if ember == null:
		ember = Node2D.new()
		ember.z_index = 1
		ember.draw.connect(_draw_ember)
		add_child(ember)


func _draw_ember() -> void:
	var lighting := smoke_t >= 0.0
	if not alive or (not lighting and game.clock > puff_until) or st != St.GUARD:
		return
	var mouth := Vector2(facing.x * 3.0, -29.0)
	if lighting:
		if smoke_t >= SMOKE_STRIKE and smoke_t < SMOKE_STRIKE + 2.5:   # the match, flaring then steady
			var k := clampf(1.0 - (smoke_t - SMOKE_STRIKE) / 2.5, 0.3, 1.0)
			var flick := 0.5 + 0.5 * sin(t * 37.0)
			ember.draw_circle(mouth + Vector2(facing.x * 2.0, 4.0), 4.0 * k + flick, Color(1.0, 0.75, 0.3, 0.25 * k))
			ember.draw_circle(mouth + Vector2(facing.x * 2.0, 4.0), 1.2 + flick * 0.5, Color(1.0, 0.95, 0.6, 0.9))
		return
	var glow := 0.55 + 0.45 * sin(t * 1.3)
	ember.draw_circle(mouth + Vector2(facing.x * 2.5, 1.0), 0.8, Color(1.0, 0.45, 0.15, glow))
	for i in 4:   # a thread of smoke, drifting up and off
		var f := fposmod(t * 0.35 + i * 0.25, 1.0)
		var at := mouth + Vector2(facing.x * 3.0 + sin(t * 1.7 + i) * 2.0 + f * 5.0, -f * 16.0)
		ember.draw_circle(at, 1.0 + f * 2.2, Color(0.85, 0.85, 0.82, 0.3 * (1.0 - f)))


# ------------------------------------------------------------------ in from the squall

## A squall coming down: does he go in out of it? Once a squall, his own mind, made
## up as soon as he's free to (one busy at a fire or a smoke as it comes down thinks
## about it when he's done, if it's still blowing).
func _think_shelter() -> void:
	var i: int = game.snowfall.squall_at(game.clock)
	if i < 0 or i == shelter_rolled or game.snowfall.storm < 0.3:
		return
	if not can_be_lured() or game.war or suspicion > 0.3 or alarm_role != "" or smoke_t >= 0.0:
		return
	shelter_rolled = i
	if shelter_rng.randf() >= shelter_chance():
		return
	var best := SHELTER_REACH
	for h in game.houses:
		for d in h["doors"]:
			var dist := global_position.distance_to(d)
			if dist < best:
				best = dist
				shelter_house = h
				shelter_door = d
	if best >= SHELTER_REACH:
		return
	smoke_t = -1.0
	st = St.ERRAND
	errand = "shelter"
	errand_t = 0.0
	shelter_until = game.snowfall.squall_over(i) + shelter_rng.randf_range(SHELTER_LINGER.x, SHELTER_LINGER.y)
	out_at = INF
	called_to = Vector2.INF
	path_to(shelter_door)
	if shelter_rng.randf() < 0.5:
		_say(_line("shelter", SHELTER_LINES, shelter_rng))
	_log("shelters")


func _shelter_errand() -> void:
	if global_position.distance_to(shelter_door) > 8.0 and not follow_path(walk * 1.3):   # (hurrying, head down)
		return
	_go_in()


## In at the door: gone from the street, the fire lit.
func _go_in() -> void:
	indoors = true
	shelter_house["in"] += 1
	velocity = Vector2.ZERO
	visible = false
	cone.visible = false
	occluded = false
	_sync_ghost()
	collision_layer = 0
	collision_mask = 0
	hurtbox.collision_layer = 0
	global_position = shelter_house["inside"]   # (in among the walls: nobody's sight or round gets to him)


## Inside: out again when the shooting's brought him (in his own time), the squall's
## done and he's warm, or anything else has called him (the posse, the alarm, a war).
func _indoors() -> void:
	velocity = Vector2.ZERO
	if st != St.ERRAND or errand != "shelter":
		_come_out()
		return
	if game.clock >= out_at or (out_at == INF and game.clock >= shelter_until):
		_come_out()


## How likely he is to go in out of a squall: the quicker, his post's fire out.
func shelter_chance() -> float:
	return SHELTER_COLD if _cold_post() else SHELTER


## A post with a fire by it that's gone out: a cold one.
func _cold_post() -> bool:
	var f := _post_fire()
	return f != null and not f.lit()


## The fire near his post, if there is one.
func _post_fire() -> Campfire:
	for f in game.fires:
		if f.global_position.distance_to(home) < WARM_NEAR:
			return f
	return null


## Time to warm his hands, if there's a fire going by his post with room at it.
func _think_warm() -> bool:
	var f := _post_fire()
	if f == null or not has_anim(_upper_key("warm")):
		return false
	if warm_at == INF:
		warm_at = game.clock + warm_rng.randf_range(WARM_EVERY.x * 0.3, WARM_EVERY.y)
		return false
	if game.clock < warm_at or not f.lit():
		return false
	warm_at = game.clock + warm_rng.randf_range(WARM_EVERY.x, WARM_EVERY.y)
	var at_it := 0
	for e in game.enemies:
		if e.alive and e.st == St.ERRAND and e.errand == "warm" and e.warm_fire == f:
			at_it += 1
	if at_it >= 2:
		return false
	var side := (home - f.global_position).normalized().rotated(warm_rng.randf_range(-0.9, 0.9))
	var spot := f.global_position + side * 20.0
	var way: PackedVector2Array = game.find_path(global_position, spot)
	if way.is_empty() or way[way.size() - 1].distance_to(spot) > 8.0:
		return false   # (no getting to that side of it: another time)
	warm_fire = f
	st = St.ERRAND
	errand = "warm"
	errand_t = 0.0
	errand_len = warm_rng.randf_range(WARM_T.x, WARM_T.y)
	errand_at = spot
	errand_face = -side
	path = way
	path_i = 0
	repath_t = 0.6
	game.stats["warmings"] = game.stats.get("warmings", 0) + 1
	return true


func _warm_errand(delta: float) -> void:
	if not is_instance_valid(warm_fire) or not warm_fire.lit():
		errand = ""   # (gone out on him)
		_go_back()
		return
	if errand_t <= 0.0 and global_position.distance_to(errand_at) > 5.0 and not follow_path(walk):
		return
	velocity = Vector2.ZERO
	desired = (warm_fire.global_position - global_position).normalized()
	pose = "warm"
	errand_t += delta
	if errand_t >= errand_len:
		errand = ""
		errand_t = 0.0
		_go_back()


## Heard something from in by the stove: he'll be out to it, once he's got his coat on.
func call_out(pos: Vector2) -> void:
	called_to = pos
	if out_at == INF:
		out_at = game.clock + shelter_rng.randf_range(SHELTER_OUT.x, SHELTER_OUT.y)


func _come_out() -> void:
	indoors = false
	shelter_house["in"] = maxi(0, shelter_house["in"] - 1)
	global_position = shelter_door
	visible = true
	cone.visible = true
	collision_layer = Iso.LAYER_ACTOR
	collision_mask = Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR
	hurtbox.collision_layer = Iso.LAYER_HURT
	path = PackedVector2Array()
	if st != St.ERRAND or errand != "shelter":
		return   # (called off by something else: on with that)
	errand = ""
	if called_to != Vector2.INF:   # out to the shooting
		var to := called_to
		called_to = Vector2.INF
		wary = true
		suspicion = maxf(suspicion, 0.6)
		start_investigate(to, true)
		_log("out to the shooting")
	else:
		_go_back()


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
	if st in [St.GUARD, St.PATROL, St.RETURN, St.INVESTIGATE, St.ERRAND]:
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
	if reaction in ["cower", "flee", "dash", "hide", "throw", "clear", "patch", "rescue", "fetch"]:
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


func say_line(key: String, stock: Array, dice: RandomNumberGenerator = null) -> void:
	_say(_line(key, stock, dice))


func _combat(delta: float) -> void:
	var p: Player = game.player
	if not p.alive:
		velocity = Vector2.ZERO
		return
	var to := p.global_position - global_position
	var dist := to.length()
	var spec: Dictionary = stats
	if finishing and not (p.down and revealed and not panic and reaction == ""):
		finishing = false
	if finishing and not weapon.is_reloading():
		_finish(delta, p, to, dist)
		return
	if rabble_left > 0.0 or _rabble_roll(delta, p):
		_rabble(delta)
		return

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
	if sticks > 0 and _think_dynamite(delta):
		return
	if suppress_t > 0.0 and ready_t <= 0.0:
		_suppress(delta, spec)
		return
	if assault and _hunt_carrier(delta):
		return
	if objective != Vector2.INF:
		_assault(delta, p, to, dist, spec)
		return
	breaking = {}
	break_look -= delta
	if not sees_player and break_look <= 0.0:
		break_look = 0.4   # a few times a second is plenty to notice he's behind a crate
		if _break_cover():
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
		if (hunt_target == Vector2.INF or hunt_target.distance_to(last_known) > 40.0) and game.plans_left > 0:
			game.plans_left -= 1   # (a whole gang replanning at once would stall the frame)
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


## Every so often a man with a stick asks himself whether it's time for it.
func _think_dynamite(delta: float) -> bool:
	dyn_look -= delta
	if dyn_look > 0.0:
		return false
	dyn_look = randf_range(0.6, 1.2)
	var at: Vector2 = game.dynamite_target(self)
	if at == Vector2.INF or randf() > 0.6:
		return false
	sticks -= 1
	throw_at = at
	pending = ""
	_stop_watching(WATCH_CD)
	start_reaction("throw")
	_log("lights dynamite")
	return true


## Over it goes: at where he last saw the stranger, give or take (a drunk may
## throw it short, or fumble it at his own feet).
func _let_fly() -> void:
	var s := stick
	stick = null
	var to := throw_at
	var r := randf()
	var fumble := float(tdata["fumble"])
	if r < fumble * 0.3:
		reaction_t = 0.0   # done throwing: free to run from it like anyone else
		s.drop()
		_log("fumbles the dynamite")
		return
	if r < fumble:
		to = global_position.lerp(to, randf_range(0.35, 0.6))
		_log("throws it short")
	to += Vector2.from_angle(randf() * TAU) * randf_range(0.0, 16.0) * float(tdata["aim"]) * Vector2(1.0, 0.6)
	s.throw(to)
	_log("throws dynamite")


## Into cover, then down on one knee winding the bandage on, unless the stranger
## walks up on him.
func _patch() -> void:
	if not patching:
		if follow_path(run) or reaction_t <= 0.0:
			patching = true
			reaction_t = PATCH_T
			velocity = Vector2.ZERO
			game.sfx("tear", global_position, -8.0, 0.1)
		return
	velocity = Vector2.ZERO
	crouched = true
	pose = "bandage"
	desired = (threat - global_position).normalized()
	if sees_player and game.player.global_position.distance_to(global_position) < PATCH_ABORT:
		patching = false
		reaction_t = 0.0
		_log("gives up patching")
		return
	if reaction_t <= 0.0:
		hp = mini(max_hp, hp + 1)
		limp_t = 0.0
		bleeding = false
		bandages -= 1
		patching = false
		_log("patches up")


## Hit and still standing: maybe he breaks off to patch himself up (more likely the
## more rattled he is; a bold man fights on).
func _maybe_patch(from: Vector2) -> void:
	if bandages <= 0 or hp >= max_hp or reaction == "throw":
		return
	var chance := float(tdata["patch"]) * (0.6 + 0.6 * fear()) * (1.0 - bold * 0.7)
	if randf() >= chance:
		return
	threat = from
	pending = "patch"
	pending_forced = true
	pending_t = randf_range(0.2, 0.5) * reflex


## A lit stick has come down near him: he'll get clear of it in a moment.
func dodge(at: Vector2, fuse_left: float, reach := Dynamite.R) -> void:
	if not alive or reaction == "throw":
		return
	threat = at
	clear_for = fuse_left
	clear_r = reach
	pending = "clear"
	pending_forced = true
	pending_t = randf_range(0.05, 0.3) * reflex
	_stop_watching(WATCH_CD)
	suppress_t = 0.0


## Hit (not killed) with it lit in his hand: he lets go of it.
func _fumble_stick() -> void:
	var s := stick
	stick = null
	reaction = ""
	reaction_t = 0.0
	s.drop()


func die(from_dir: Vector2, shooter: Actor = null, how := "") -> void:
	var s := stick
	stick = null
	_end_rescue()
	super(from_dir, shooter, how)
	if s:
		s.drop()   # once it's lit, it's lit


# ------------------------------------------------------------------ downed

## Not every killing shot kills: not dynamite, the knife, or a shotgun at arm's
## length, and not a man who's already been down once and got up.
func _goes_down(shooter: Actor) -> bool:
	if blasted or Engine.has_meta("no_downed") or has_meta("was_down"):
		return false
	if shooter and shooter.weapon and shooter.weapon.is_shotgun() \
			and shooter.global_position.distance_to(global_position) < 60.0:
		return false
	return Engine.has_meta("always_downed") or randf() < DOWN_CHANCE


## Into the dirt, alive: out of the fight as far as anyone's counting (his gun
## falls, his comrades see him drop), but he can still be hit, and he can be saved.
func go_down(from_dir: Vector2, shooter: Actor) -> void:
	die(from_dir, shooter)
	downed = true
	down_t = 0.0
	groan_t = randf_range(1.0, 2.5)
	hurtbox.set_deferred("collision_layer", Iso.LAYER_HURT)   # (after die()'s: a man can still shoot him)
	_lay_hurtbox()
	set_meta("was_down", true)
	gasp_look = gasp_rng.randf_range(1.5, 3.0)   # (just hit: it takes him a moment)
	_log("goes down")


## Where to put a round in him: his middle, lying or standing.
func aim_point() -> Vector2:
	if downed:
		var l := lie_line()
		return (l[0] + l[1]) / 2.0
	return global_position


func _downed_tick(delta: float) -> void:
	_lay_hurtbox()   # (dragged, he may come to lie another way)
	shout_t = maxf(0.0, shout_t - delta)
	if gasp != "":
		_gasp_tick(delta)
		if not downed:
			return
	else:
		_think_gasp(delta)
	if rescuer != null and (not is_instance_valid(rescuer) or not rescuer.alive or rescuer.rescuing != self):
		rescuer = null
	if medic != null and (not is_instance_valid(medic) or not medic.alive or medic.patient != self):
		medic = null
	var held := rescuer != null and rescuer.rescue_phase in ["drag", "treat"] \
		or medic != null and medic.st == Civilian.St.TEND
	if not held:
		down_t += delta   # bleeding out (he presses the wound while someone's got him)
	if down_t >= BLEED_T:
		finish(null)
		_log("bleeds out")
		return
	groan_t -= delta
	if groan_t <= 0.0:
		groan_t = randf_range(3.0, 6.0)
		game.sfx("groan", global_position, -10.0, 0.12)
		if shout_t <= 0.0 and randf() < 0.6 and not held and gasp == "":
			_say(_line("downed", DOWN_LINES))


## Is he going to try it? He looks about now and then: a pistol to hand (his own,
## lying by him, or one still holstered), the stranger close and in sight.
func _think_gasp(delta: float) -> void:
	gasp_look -= delta
	if gasp_look > 0.0:
		return
	gasp_look = 1.0
	if rescuer != null and rescuer.rescue_phase in ["drag", "treat"] or medic != null:
		return   # being got clear, or seen to: no call for it
	var gun := _gasp_gun()
	var p: Player = game.player
	var dist := global_position.distance_to(p.global_position)
	if gun == "" or not p.alive or not p.visible or dist > GASP_RANGE \
			or not game.line_of_sight(global_position, p.global_position, p.crouched):
		return
	var close := dist < GASP_CLOSE
	if close and not gasp_close_rolled:
		gasp_close_rolled = true   # the stranger right on him: help or no help, now or never
	elif rescuer != null or gasp_rolls >= 2:
		return   # help's on the way: he'll wait for it
	elif gasp_rolls == 1 and down_t < BLEED_T * 0.6:
		return   # (the second thought comes when nobody's come and it's nearly over)
	else:
		gasp_rolls += 1
	if gasp_rng.randf() < gasp_chance(close):
		if rescuer != null and is_instance_valid(rescuer):
			rescuer._end_rescue()
		rescuer = null
		_start_gasp(gun)


## Not all of them: it's likely to be the end of him, and a man who can hope for a
## comrade to come and drag him clear would rather wait for it, unless the stranger
## is right on him.
func gasp_chance(close := false) -> float:
	if Engine.has_meta("always_gasp") or game._args.has("gasp"):
		return 1.0
	if Engine.has_meta("no_gasp"):
		return 0.0
	var c := float(tdata["gasp"])
	if close:
		return minf(0.95, c * GASP_CLOSE_MULT)
	for e in game.enemies:
		if e.alive and e.revealed and not e.panic and e.global_position.distance_to(global_position) < RESCUE_NEAR:
			return c * GASP_HOPE
	return c


## The pistol he'd use: the one he dropped, if it's still lying by him; else one
## he never drew. Rifles and scatterguns don't count: no man fires those one-handed.
func _gasp_gun() -> String:
	var held: String = weapon.kind if weapon else ""
	if held in PISTOLS and game.loose_guns.any(func(g): return g["under"] == self):
		return held
	for w in loadout:
		if w != held and w in PISTOLS:
			return w
	return ""


func _start_gasp(gun: String) -> void:
	if gun == weapon.kind:
		game.take_back_gun(self)
	gasp_gun = gun
	weapon = Weapon.new("colt" if gun == "colts" else gun, self)
	weapon.reserve = 999
	gasp_left = GASP_SHOTS[gasp_rng.randi() % GASP_SHOTS.size()]
	if not weapon.barrels.is_empty():
		gasp_left = mini(gasp_left, weapon.barrels.size())
	gasp = "rise"
	gasp_t = 0.0
	gasp_lost = 0.0
	facing = (game.player.global_position - global_position).normalized()
	_pose_gasp("gasp_rise")
	game.sfx("groan", global_position, -6.0, 0.12)
	_log("last gasp")


func _pose_gasp(anim_name: String) -> void:
	_death = gasp_gun + "/" + anim_name
	_layers.erase("full")
	lie_dir = -1
	_lay_hurtbox()


func _gasp_tick(delta: float) -> void:
	gasp_t += delta
	var p: Player = game.player
	match gasp:
		"rise":
			if not dying():
				gasp = "aim"
				gasp_t = GASP_EVERY - GASP_HOLD
				_pose_gasp("gasp_aim")
				weapon._snd("cock", -2.0)
				_say(_line("gasp", GASP_LINES))
		"aim":
			var sees: bool = p.alive and p.visible and game.line_of_sight(global_position, p.global_position, p.crouched)
			gasp_lost = 0.0 if sees else gasp_lost + delta
			if sees:
				var to := (p.global_position - global_position).normalized()
				if Iso.dir8(to) != Iso.dir8(facing):
					facing = to
					_lay_hurtbox()
			if gasp_left <= 0 and gasp_t >= 1.0 or gasp_lost > GASP_LOST or not p.alive:
				_end_gasp()
				return
			if _death.ends_with("gasp_fire") and not dying():
				_pose_gasp("gasp_aim")
			if gasp_left > 0 and gasp_t - delta < GASP_EVERY * 0.6 and gasp_t >= GASP_EVERY * 0.6 and gasp_t < GASP_EVERY:
				weapon._snd("cock", -4.0)   # thumbing the hammer back for the next
			if gasp_left > 0 and gasp_t >= GASP_EVERY and sees:
				gasp_t = 0.0
				gasp_left -= 1
				_gasp_shot()
		"sink":
			if not dying():
				gasp = ""
				if gasp_rng.randf() < GASP_PERISH:
					_log("dies of the effort")
					finish(null)
				else:
					down_t += GASP_COST


func _gasp_shot() -> void:
	var d: Dictionary = weapon.d
	var dir := facing
	_pose_gasp("gasp_fire")
	var spread := deg_to_rad(float(d["spread"]) * accuracy_mult() * GASP_SPREAD)
	var a := clampf(gasp_rng.randfn(0.0, spread * 0.5), -spread * 1.5, spread * 1.5)
	game.spawn_bullet(global_position + dir * 5.0, dir.rotated(a) * float(d["speed"]), float(d["range"]),
		int(d["damage"]), self, -muzzle_offset().y, false, int(d.get("pierce", 0)))
	game.muzzle_flash(self, dir)
	weapon._snd(d["sfx"])
	game.make_noise(global_position, d["noise"], "enemy_shot", self)
	_log("last gasp shot")


## Spent: he sinks back into the dirt and lets the gun go.
func _end_gasp() -> void:
	gasp = "sink"
	gasp_t = 0.0
	_pose_gasp("gasp_sink")
	game.drop_gun(self)


## Dead for good, lying where he is.
func finish(by: Actor) -> void:
	if not downed:
		return
	downed = false
	if by:
		killer = by
	hurtbox.set_deferred("collision_layer", 0)
	shout_t = 0.0
	var gasping := gasp in ["rise", "aim"]
	if gasping:   # dropped where he's propped, the gun falling from his hand
		_pose_gasp("gasp_die")
		game.drop_gun(self)
	gasp = ""
	if rescuer and is_instance_valid(rescuer):
		rescuer._end_rescue()
	rescuer = null
	game.sfx("hit", global_position, -6.0)
	if by and by.is_player and gasping:
		_log("shot with his gun up")   # (fair: he was shooting back)
	elif by and by.is_player:
		game.stats["wounded men shot"] = game.stats.get("wounded men shot", 0) + 1   # (hidden, for now)
	_log("finished")


## Patched up and on his feet again: one HP, shaken, gun back in hand.
func revive() -> void:
	if not downed:
		return
	downed = false
	alive = true
	hp = 1
	rescuer = null
	medic = null
	bleeding = false
	limp_t = randf_range(5.0, 8.0)
	shaken = 1.0
	_death = ""
	_layers.erase("full")
	legs_spr.visible = true
	collision_layer = Iso.LAYER_ACTOR
	collision_mask = Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR
	hurtbox.set_deferred("collision_layer", Iso.LAYER_HURT)
	_stand_hurtbox()
	game.take_back_gun(self)
	weapon = Weapon.new(loadout[0], self)
	weapon.reserve = 999
	reaction = ""
	pending = ""
	st = St.GUARD   # (so enter_combat treats it as joining the fight)
	enter_combat(game.seen_pos, false, false)
	stagger_t = 0.8
	_log("gets back up")


# ------------------------------------------------------------------ rescue

## Off to get a downed comrade, the others asked to keep the stranger's head down.
func start_rescue(d: Enemy) -> void:
	rescuing = d
	d.rescuer = self
	threat = game.seen_pos
	pending = ""
	_stop_watching(WATCH_CD)
	start_reaction("rescue")
	rescue_phase = "go"
	path_to(d.global_position)
	if shout_t <= 0.0 or randf() < 0.7:
		_say(_line("rescue", RESCUE_LINES))
	if game.staleness() < game.FRESH:
		for o in game.enemies:
			if o != self and o.alive and o.gang == gang and o.global_position.distance_to(global_position) < 260.0:
				o.suppress(game.seen_pos, randf_range(3.0, 4.5))
	_log("goes to get a downed man")


## Run to him, drag him by the collar into cover away from the stranger, then down
## on one knee bandaging him till he can stand.
func _rescue(delta: float) -> void:
	var d := rescuing
	if d == null or not is_instance_valid(d) or not d.downed or d.rescuer != self:
		_end_rescue()
		reaction_t = 0.0
		return
	reaction_t = 30.0   # (it ends when it's done, not on a clock)
	match rescue_phase:
		"go":
			if follow_path(run) and global_position.distance_to(d.global_position) >= 14.0:
				velocity = (d.global_position - global_position).normalized() * run   # the last few steps
			if global_position.distance_to(d.global_position) < 14.0:
				rescue_phase = "drag"
				var c: Vector2 = game.find_cover(d.global_position, threat)
				path_to(c if c != Vector2.INF else game.point_away(d.global_position, threat, 70.0))
				smear = d.global_position
		"drag":
			pose = "haul"
			var there := follow_path(walk * 0.7)
			if velocity.length() > 1.0:
				var behind := global_position - velocity.normalized() * 13.0
				d.global_position = d.global_position.move_toward(behind, maxf(velocity.length(), 20.0) * delta * 1.5)
			if d.global_position.distance_to(smear) > 9.0:
				smear = d.global_position
				game.decals.add(smear, randf_range(1.2, 2.2), Color(0.38, 0.06, 0.04, 0.5))
			if there:
				rescue_phase = "treat"
				work_t = TREAT_T
				game.sfx("tear", global_position, -8.0, 0.1)
		"treat":
			velocity = Vector2.ZERO
			crouched = true
			pose = "bandage"
			desired = (d.global_position - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				if bandages > 0:
					bandages -= 1
				d.revive()
				_log("patches up a downed man")
				_end_rescue()
				reaction_t = 0.0


# ------------------------------------------------------------------ the street war

## The truce broken (Silencio: see game.war): the nearest of the other gang he can
## see is his to shoot, up to his range and in; further, he closes on him. Not while
## he's fighting the stranger (that comes first), and dug in at his gang's holdout
## only at those who come near it.
func _feuding(delta: float) -> bool:
	if not game.war or gang == "" or st == St.COMBAT:
		foe = null
		return false
	feud_look -= delta
	if feud_look <= 0.0 or foe == null or not foe.alive or foe.downed:
		feud_look = 0.5
		foe = _nearest_foe()
	if foe == null:
		return false
	var to := foe.global_position - global_position
	var d := to.length()
	desired = to.normalized()
	aiming = true
	var keep: Vector2 = stats["keep"]
	var clear: bool = game.line_of_sight(global_position, foe.global_position, false)
	if d > keep.y or not clear:
		if alarm_role == "fortified":
			foe = null   # (dug in: he doesn't leave his place for it)
			return false
		repath_t -= delta
		if repath_t <= 0.0:
			path_to(foe.global_position)
		follow_path(walk)
		return true
	velocity = Vector2.ZERO
	facing = desired
	feud_cd -= delta
	if weapon.is_reloading():
		return true
	if weapon.needs_reload():
		weapon.start_reload()
		return true
	if feud_cd <= 0.0 and weapon.can_fire():
		weapon.trigger()
		since_shot = 0.0
		feud_cd = feud_rng.randf_range(stats["cadence"].x, stats["cadence"].y) * FEUD_PACE
	return true


func _nearest_foe() -> Enemy:
	# (no further than a little past his gun's reach: he doesn't go out across the
	# street after a man he can't hit; the gang's pushes do the moving)
	var reach := minf(view_range() * (0.85 if alarm_role == "fortified" else 1.4), reach() * 1.2)
	var best: Enemy = null
	var best_d := reach
	for o in game.enemies:
		if not o.alive or o.downed or o.gang == gang or o.gang == "" or not o.revealed:
			continue
		var d: float = global_position.distance_to(o.global_position)
		if d < best_d and game.line_of_sight(global_position, o.global_position, false):
			best = o
			best_d = d
	return best


# ------------------------------------------------------------------ the strongbox

## The gold lying out where it shouldn't be: he goes to take it home.
func fetch(b: Strongbox) -> void:
	fetching = b
	start_reaction("fetch")
	fetch_phase = "go"
	path_to(b.global_position)
	if shout_t <= 0.0:
		_say("There's the gold!")
	_log("goes for the strongbox")


## To it, up with it in both arms, and back to the hideout's door with it. The
## stranger in sight, and it's dropped where he stands (see Strongbox).
func _fetch() -> void:
	var b := fetching
	reaction_t = 30.0   # (it ends when it's done, not on a clock)
	if b == null or b.away or (b.holder != null and b.holder != self) or sees_player or st == St.COMBAT:
		reaction_t = 0.0
		return
	match fetch_phase:
		"go":
			var d := global_position.distance_to(b.global_position)
			if follow_path(run) and d >= 12.0:
				velocity = (b.global_position - global_position).normalized() * walk
			if d < 12.0:
				b.take(self)
				anim_gun = "strongbox"
				fetch_phase = "carry"
				path_to(b.home)
		"carry":
			pose = "carry"
			if follow_path(walk * 0.65):
				b.put_down(b.home)   # (back where it was, in the doorway)
				let_go_of_box()
				reaction_t = 0.0
				_log("takes the strongbox home")


## Hands free again: the box set down (or dropped) wherever he is.
func let_go_of_box() -> void:
	var b := fetching
	fetching = null
	fetch_phase = ""
	if anim_gun == "strongbox":
		anim_gun = ""
	if pose == "carry":
		pose = ""
	if b and is_instance_valid(b):
		if b.holder == self:
			b.put_down(global_position + facing * 8.0)
		if b.fetcher == self:
			b.fetcher = null


func _end_rescue() -> void:
	if rescuing and is_instance_valid(rescuing) and rescuing.rescuer == self:
		rescuing.rescuer = null
	rescuing = null
	rescue_phase = ""


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
		and dist < reach() * 0.85 and weapon.can_fire() \
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

	if volley_at > 0.0 and game.clock >= volley_at:
		volley_at = -1.0
		if weapon.can_fire() and abs(facing.angle_to(to)) < 0.3:
			weapon.trigger()   # all together
			since_shot = 0.0
			shot_cd = randf_range(spec["cadence"].x, spec["cadence"].y) * CADENCE_MULT
			return
	if velocity.length() < 1.0:
		aim_t += delta
	# an opportunist the stranger isn't watching wastes no time lining up
	var quick := 0.55 if opportunist > 0.0 and sights_t <= 0.0 else 1.0
	var aimed := aim_t >= 0.35 * reflex * quick or (fires_moving and dist < 70.0 + 70.0 * bold)
	var in_range: bool = dist < reach() * 0.85
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


## Is he going to stand about? Only a man given to it, his gun loaded and nothing
## else on his mind, in a crowd of his own round the stranger.
func _rabble_roll(delta: float, p: Player) -> bool:
	rabble_cd -= delta
	var r := float(tdata.get("rabble", 0.0))
	if r <= 0.0 or rabble_cd > 0.0 or weapon.is_reloading() or reaction != "" or p.down:
		return false
	rabble_cd = RABBLE_EVERY
	var crowd := 0
	for e in game.enemies:
		if e.alive and e.st == St.COMBAT and e.global_position.distance_to(p.global_position) < CROWD_R:
			crowd += 1
	if crowd < RABBLE_CROWD or rabble_rng.randf() >= r * minf(1.0, (crowd - RABBLE_CROWD + 1) / 6.0) * 0.5:
		return false
	rabble_left = rabble_rng.randf_range(1.6, 2.4)
	rabble_cd = rabble_rng.randf_range(6.0, 10.0)
	velocity = Vector2.ZERO
	crouched = false
	if weapon.can_fire() and kind_of_gun() == "pistol" and rabble_rng.randf() < 0.55 and has_anim(_upper_key("salute")):
		rabble_shot = 0.5   # (when the gun's up)
		play_action("salute")
		_say(_rabble_line("rabble", ["¡Viva Villa!", "¡Viva la revolución!", "¡Yaaa-haa!", "¡Ajúa!"]))
		game.stats["rounds at the sky"] = game.stats.get("rounds at the sky", 0) + 1
	else:
		rabble_shot = -1.0
		play_action("point")
		_say(_rabble_line("cheer", ["We got him now!", "¡Ya lo tenemos!", "Get him, boys!", "¡Échenle bala!", "He's finished!"]))
		game.stats["rabble cheers"] = game.stats.get("rabble cheers", 0) + 1
	return true


func _rabble_line(key: String, stock: Array) -> String:
	var lines: Array = tdata.get("shouts", {}).get(key, _tongue(stock))
	return lines[rabble_rng.randi() % lines.size()]


func kind_of_gun() -> String:
	return "pistol" if weapon.kind in PISTOLS else "long"


## Standing there in the open, doing no good at all.
func _rabble(delta: float) -> void:
	velocity = Vector2.ZERO
	crouched = false
	rabble_left -= delta
	if rabble_shot >= 0.0:
		rabble_shot -= delta
		if rabble_shot < 0.0 and alive:
			weapon.salute()


## The stranger's down in the dirt: he walks up (no hurry, no cover, gun on him)
## and puts one in him from close. It's when he's most use to a man lying there
## with a pistol.
func _finish(delta: float, p: Player, to: Vector2, dist: float) -> void:
	desired = to.normalized()
	aiming = true
	crouched = false
	shot_cd -= delta
	finish_repath -= delta
	if dist > FINISH_NEAR:
		if finish_repath <= 0.0 or path_i >= path.size():
			finish_repath = 0.6
			path_to(p.global_position)
		follow_path(walk)
		return
	velocity = Vector2.ZERO
	if weapon.needs_reload():
		weapon.start_reload()
	elif shot_cd <= 0.0 and absf(facing.angle_to(to)) < 0.2 and weapon.can_fire():
		weapon.trigger()
		since_shot = 0.0
		shot_cd = randf_range(0.7, 1.1)
		_log("fires down at the stranger")


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
	var carry: float = reach() * 0.8
	var slot := target + flank_dir * minf(lerpf((keep.x + keep.y) * 0.5, keep.x, bold), carry)
	var c: Vector2 = game.find_fighting_cover(global_position, target, slot, keep, game.taken_positions(self))
	if c != Vector2.INF and c.distance_to(target) > carry:
		c = Vector2.INF
	if c != Vector2.INF and (randf() < bold * 0.6 or (bold > 0.0 and c.distance_to(target) > keep.y)):
		c = Vector2.INF   # scorns cover, or won't hang back for it: he'll shoot it out in the open
	if settled and fight_pos != Vector2.INF and c != Vector2.INF and c.distance_to(fight_pos) < 24.0 and randf() < 0.6:
		# same spot again: work round the flank instead of sitting tight
		flank_dir = flank_dir.rotated([-0.6, 0.6].pick_random())
		slot = target + flank_dir * minf((keep.x + keep.y) * 0.5, carry)
		c = game.find_fighting_cover(global_position, target, slot, keep, game.taken_positions(self))
		if c != Vector2.INF and c.distance_to(target) > carry:
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
		if absf(d.x) > 32.0 or absf(d.y) > 32.0:
			continue   # (most of them, most of the time: no square root needed)
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
	if global_position.distance_to(at) > reach() * 0.8 or not game.line_of_sight(global_position, at, false):
		return false
	single_shot = false
	breaking = {}   # (whoever wants it shot at, it's not his own crate-breaking now)
	suppress_t = seconds
	suppress_at = at + Vector2(randf_range(-14, 14), randf_range(-8, 8))
	shot_cd = randf_range(0.0, 0.5)
	return true


## The stranger's fired from somewhere he can't see: unless it's put the fear into
## him (or he's got other work: watching that corner, reloading, finishing him), he
## answers it, rounds into the corner he's behind.
func _return_fire(pos: Vector2) -> void:
	if not alive or not revealed or sees_player or reaction != "" or pending != "" or finishing \
			or suppress_t > 0.0 or watch_at != Vector2.INF or rabble_left > 0.0 \
			or weapon.is_reloading() or weapon.needs_reload() or game.clock < return_ok_at:
		return
	var at: Vector2 = game.corner_near(global_position, pos)
	if at == Vector2.INF or global_position.distance_to(at) > reach() * 0.8:
		return
	single_shot = false
	breaking = {}
	suppress_t = return_rng.randf_range(RETURN_FOR.x, RETURN_FOR.y)
	suppress_at = at + Vector2(return_rng.randf_range(-6, 6), return_rng.randf_range(-4, 4))
	shot_cd = maxf(0.5, return_rng.randf_range(0.6, 1.2) * reflex)   # (a moment to swing round and find the corner)
	return_ok_at = game.clock + suppress_t + return_rng.randf_range(RETURN_REST.x, RETURN_REST.y)
	game.stats["return fire"] = game.stats.get("return fire", 0) + 1
	if shout_t <= 0.0 and return_rng.randf() < 0.3:
		var lines: Array = tdata.get("shouts", {}).get("return", _tongue(["There! The corner!", "¡Ahí, en la esquina!",
			"Light him up!", "¡Fuego, fuego!"]))
		_say(lines[return_rng.randi() % lines.size()])
	_log("returns fire at the corner")


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
	if assault and rank >= 1:
		_order_volley()
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
		if e.reaction in ["flee", "dash", "cower", "hide", "patch"] or e.weapon.is_reloading():
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


## On to the train: in bounds, cover to cover (if he knows to look for it), down a
## while between them, shooting if he can see the stranger.
func assault_to(spot: Vector2) -> void:
	assault = true
	objective = spot
	bounding = false
	bound_hold = 0.0


## The machine gun's just cut down a man beside him, and the stranger can see it: he
## throws himself into the nearest cover, or gives ground (a leva may turn and run
## back a way). A few seconds and he's up and coming on again, and for a while after
## that the gun doesn't frighten him: they come on in rushes, and go to ground in
## clumps where it finds them.
func gun_fright(at: Vector2) -> void:
	if game.clock < gun_nerve or reaction in ["flee", "hide", "backoff", "dash", "throw"]:
		return   # (a lit stick in his hand: he's got that to see to)
	threat = game.player.global_position
	pending = ""
	var close := global_position.distance_to(at) < 45.0
	var x := assault_rng.randf()
	var r := ""
	if tdata.get("deserts", false):
		r = "flee" if x < (0.6 if close else 0.4) else "hide"
	else:
		r = "backoff" if x < (0.4 if close else 0.2) else "hide"
	start_reaction(r)
	reaction_t = minf(reaction_t, assault_rng.randf_range(2.5, 4.0))
	bounding = false
	gun_nerve = game.clock + reaction_t + GUN_NERVE
	game.stats["gun frights"] = game.stats.get("gun frights", 0) + 1


## The ground's just gone up under the army, charge after charge round the
## breastwork: he thinks the train's going up next, wherever he is, and falls back
## the way he came for a few seconds (a leva may keep going), then comes on again.
func mine_rout(from: Vector2, dice: RandomNumberGenerator) -> void:
	if deserting or reaction == "throw":
		return   # (a lit stick in his hand: he's got that to see to)
	threat = from
	pending = ""
	if reaction == "rescue":
		_end_rescue()
	if assault and tdata.get("deserts", false) and dice.randf() < Minefield.ROUT_DESERTS:
		desert()
		return
	reaction = "flee"
	bearing_news = false
	suppress_t = 0.0
	hold_t = 0.0
	hiding = false
	crouched = false
	bounding = false
	reaction_t = dice.randf_range(Minefield.ROUT_T.x, Minefield.ROUT_T.y)
	var away := global_position - from
	away = away.normalized() if away.length() > 1.0 else Vector2.from_angle(dice.randf() * TAU)
	var g := Iso.to_grid(global_position + away * Minefield.ROUT_RUN)
	var to := Iso.to_screen(g.clamp(Vector2(1.5, 1.5), Vector2(game.size - 1.5, game.size - 1.5)))
	path_to(to if game.is_free(to) else game.free_point_near(to, 60.0, dice))
	gun_nerve = game.clock + reaction_t + GUN_NERVE
	_log("routed")


## Still out in the open, short of the train, with a way to go to the stranger: he
## knows lying out there under a machine gun is death, and the only way is in.
func pushing() -> bool:
	return assault and objective != Vector2.INF and not deserting \
		and global_position.distance_to(game.player.global_position) > PUSH_CLOSE


func _assault(delta: float, p: Player, to: Vector2, dist: float, spec: Dictionary) -> void:
	if global_position.distance_to(objective) < AT_TRAIN:
		objective = Vector2.INF   # at the train: from here he fights it out
		fight_pos = Vector2.INF
		bounding = false
		_log("at the train")
		return
	if bounding:
		crouched = false
		var fire_on: bool = bool(tdata["fires_on_move"]) and sees_player and dist < spec["keep"].y
		if follow_path(run) or global_position.distance_to(fight_pos) < 8.0:
			bounding = false
			velocity = Vector2.ZERO
		elif fire_on and weapon.can_fire() and shot_cd <= 0.0 and abs(facing.angle_to(to)) < 0.25:
			weapon.trigger()   # (a rural shoots on the run)
			shot_cd = randf_range(spec["cadence"].x, spec["cadence"].y) * CADENCE_MULT
		shot_cd -= delta
		if sees_player:
			desired = to.normalized() if fire_on else desired
		return
	bound_hold -= delta
	if pushing():
		pinned_t = 0.0   # (no lying there pinned, out here)
	elif pinned_t > 0.0:
		bound_hold = maxf(bound_hold, 0.6)   # rounds coming in, close in: he stays down
	if sees_player:
		fight_repick = 99.0   # (his place is the bound's end, not one of the fight's)
		_fight(delta, p, to, dist, spec)
	else:
		velocity = Vector2.ZERO
		crouched = at_cover
	if bound_hold <= 0.0 and volley_at < 0.0:
		_next_bound(p)


func _next_bound(p: Player) -> void:
	var to_obj := objective - global_position
	var far := pushing()
	var b: Vector2 = PUSH_BOUND if far else BOUND
	var step := minf(to_obj.length(), assault_rng.randf_range(b.x, b.y))
	var slot := global_position + to_obj.normalized() * step
	var c := Vector2.INF
	if assault_rng.randf() < float(tdata.get("cover_use", 1.0)):
		c = game.find_fighting_cover(global_position, p.global_position, slot, Vector2(0.0, 5000.0), game.taken_positions(self))
		if c != Vector2.INF and c.distance_to(objective) > global_position.distance_to(objective) - 20.0:
			c = Vector2.INF   # (cover back the way he came is no use to him)
	at_cover = c != Vector2.INF
	bounds += Vector2i(1, 1 if at_cover else 0)
	if at_cover:
		fight_pos = c
	elif step >= to_obj.length() - 1.0:
		fight_pos = objective
	else:
		fight_pos = slot if game.is_free(slot) else game.free_point_near(slot, 30.0, assault_rng)
	path_to(fight_pos)
	bounding = true
	settled = false
	var h: Vector2 = PUSH_HOLD if far else (HOLD_GREEN if tdata.get("deserts", false) else HOLD)
	bound_hold = assault_rng.randf_range(h.x, h.y)
	if rank >= 2 and shout_t <= 0.0 and assault_rng.randf() < 0.3:
		_say(_line("advance", ["¡Adelante!", "¡Al tren!"], assault_rng))


## A cabo or teniente, now and then: the men about him who can see the stranger
## hold, aim, and fire together on his word.
func _order_volley() -> void:
	volley_cd -= get_physics_process_delta_time()
	if volley_cd > 0.0 or not sees_player or reaction != "":
		return
	var men: Array[Enemy] = []
	for e in game.enemies:
		if e.alive and e.assault and not e.deserting and e.sees_player and e.reaction == "" and e.volley_at < 0.0 \
				and not e.weapon.is_reloading() and e.weapon.can_fire() \
				and e.global_position.distance_to(global_position) < VOLLEY_NEAR:
			men.append(e)
	if men.size() < 3:
		return
	volley_cd = assault_rng.randf_range(14.0, 22.0)
	_say(_line("volley", ["¡Apunten!"], assault_rng))
	for e in men:
		e.volley_at = game.clock + VOLLEY_WAIT
		e.ready_t = VOLLEY_WAIT + 0.2   # (stood, aiming, waiting on the word)
		e.bound_hold = maxf(e.bound_hold, VOLLEY_WAIT + 0.5)
		e.bounding = false
	game.stats["volleys"] = game.stats.get("volleys", 0) + 1
	get_tree().create_timer(VOLLEY_WAIT, false).timeout.connect(_give_the_word)   # (a method: gone with him if he goes)


func _give_the_word() -> void:
	if alive:
		_say("¡Fuego!")


## He's had enough: off back down the road he came, and gone.
func desert() -> void:
	if deserting:
		return
	deserting = true
	objective = Vector2.INF
	hunting = null
	desert_to = Vector2.INF
	for e in game.level.get("entries", []):   # the nearest road off the map
		var at := Iso.to_screen(Vector2(e["x"], e["y"]))
		if desert_to == Vector2.INF or at.distance_to(global_position) < desert_to.distance_to(global_position):
			desert_to = at
	if desert_to == Vector2.INF:
		desert_to = game.point_away(global_position, threat, 400.0)
	path_to(desert_to if game.is_free(desert_to) else game.free_point_near(desert_to, 40.0, assault_rng))
	_say(_line("flee", FLEE_LINES, assault_rng))
	game.stats["deserted"] = game.stats.get("deserted", 0) + 1
	_log("deserts")


## Down to the last few: he's away to fetch the rest of them from the camp, and
## nothing stops him but a bullet.
func run_to_camp(at: Vector2) -> void:
	camp_to = at
	if stick:
		_fumble_stick()   # (no time to throw it: it falls where he was)
	if fetching:
		let_go_of_box()
	_end_rescue()      # (the man he was going for waits for someone else)
	reaction = ""
	pending = ""
	foe = null
	alarm_role = ""
	st = St.INVESTIGATE
	path_to(at if game.is_free(at) else game.free_point_near(at, 40.0, feud_rng))
	_say(_line("camp", ["I'm going for the others!", "Hold 'em! I'll bring the rest!", "Back to the camp!"], feud_rng))
	_log("runs for the camp")


func _camp_run(_delta: float) -> void:
	crouched = false
	var g := Iso.to_grid(global_position)
	var edge := minf(minf(g.x, g.y), minf(game.size - g.x, game.size - g.y)) < 1.2
	if follow_path(run) or edge:   # (the path's end: the camp's way, or as near it as the ground allows)
		camp_to = Vector2.INF
		game.director.runner_home(self)


func _desert_run() -> void:
	crouched = false
	var g := Iso.to_grid(global_position)
	var edge := minf(minf(g.x, g.y), minf(game.size - g.x, game.size - g.y)) < 1.5
	if follow_path(run) or edge or global_position.distance_to(desert_to) < 40.0:
		game.gone_off(self)   # off the map


## Round among the carriers with the stranger nowhere near: once, maybe, he turns his
## gun on one of them. True while he's at it.
func _hunt_carrier(delta: float) -> bool:
	if hunting != null:
		if not hunting.alive or not hunting.visible:
			if not hunting.alive and hunting.killer == self:
				game.stats["carriers hunted"] = game.stats.get("carriers hunted", 0) + 1
				_log("killed a carrier")
			hunting = null   # one, and he's back to the stranger
			fight_pos = Vector2.INF
			return false
		var to := hunting.global_position - global_position
		var carry: float = reach() * 0.6
		if to.length() > carry or not game.line_of_sight(global_position, hunting.global_position, false):
			if path.is_empty() or path_i >= path.size() or path[path.size() - 1].distance_to(hunting.global_position) > 30.0:
				path_to(hunting.global_position)
			follow_path(run)
			return true
		velocity = Vector2.ZERO
		desired = to.normalized()
		aiming = true
		shot_cd -= delta
		if shot_cd <= 0.0 and weapon.can_fire() and abs(facing.angle_to(to)) < 0.15:
			weapon.trigger()
			shot_cd = assault_rng.randf_range(0.9, 1.6)
		return true
	if hunt_rolled or game.cargo == null:
		return false
	if sees_player and global_position.distance_to(game.player.global_position) < HUNT_NEAR * 1.3:
		return false
	var c: Civilian = null
	for cv in game.cargo.carriers:
		if cv.alive and cv.visible and cv.global_position.distance_to(global_position) < HUNT_NEAR \
				and (c == null or cv.global_position.distance_to(global_position) < c.global_position.distance_to(global_position)) \
				and game.line_of_sight(global_position, cv.global_position, false):
			c = cv
	if c == null:
		return false
	hunt_rolled = true   # (the one chance he gets)
	if assault_rng.randf() >= float(tdata.get("hunt", 0.0)):
		return false
	hunting = c
	shot_cd = 0.6
	_say(_line("hunt", ["¡Los cargadores!", "¡Mátenlos, que se llevan las armas!"], assault_rng))
	game.stats["carrier hunts"] = game.stats.get("carrier hunts", 0) + 1
	_log("goes for a carrier")
	return true


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
func _line(key: String, stock: Array, dice: RandomNumberGenerator = null) -> String:
	var own: Dictionary = tdata.get("shouts", {})
	var lines: Array = own.get(key, _tongue(stock))
	return lines[dice.randi() % lines.size()] if dice else lines.pick_random()


## The stock lines a man of this type can shout. Most of them say some of it in
## Spanish; a type that has none ("tongue": "english": Silencio's hunters and
## outlaws, up in the snow a long way from the border) leaves those lines out. His
## type's own lines are his own, French and all.
const SPANISH := ["¡", "¿", "gringo", "amigo", "compadre", "Giù"]
func _tongue(stock: Array) -> Array:
	if tdata.get("tongue", "") != "english":
		return stock
	var plain := stock.filter(func(l): return SPANISH.all(func(w): return not (l as String).contains(w)))
	return plain if not plain.is_empty() else stock


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _log(what: String) -> void:
	var key := what.split(",")[0]
	game.stats[key] = game.stats.get(key, 0) + 1
	if game._args.has("bot") or game._args.has("rattle"):
		print("%.1fs  %s #%d: %s" % [(Time.get_ticks_msec() - game.start_time) / 1000.0, kind, game.enemies.find(self), what])


## How far his gun carries for him: its reach, less in a battle's smoke (the map's
## "haze": a big fight, black powder everywhere, and he has to get closer).
func reach() -> float:
	return weapon.d["range"] * game.haze.x


func range_mult() -> float:
	return game.haze.x


func accuracy_mult() -> float:
	var m: float = (AIM_SPREAD_SHOTGUN if weapon.is_shotgun() else AIM_SPREAD) * float(tdata["aim"]) * game.haze.y
	if panic:
		return m * 5.0   # wild, over the shoulder
	if foe != null and st != St.COMBAT:
		return maxf(m * FEUD_SPREAD, FEUD_MIN / maxf(0.1, float(weapon.d["spread"])))   # (at the other gang: see _feuding)
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
	if blasted:
		killed_with = "dynamite"   # (not the gun in the thrower's other hand)
	elif shooter != null and is_instance_valid(shooter) and shooter.weapon != null:
		killed_with = shooter.weapon.kind   # (if this is the one that does it: set before
		                                    # he dies, as whoever sees it weighs it there and then)
	if downed:
		finish(shooter)   # in the dirt already: this one's for good
		return
	if alive and hp - dmg <= 0 and _goes_down(shooter):
		hp = 0
		game.blood(global_position, from_dir, gun_height())
		game.sfx("hit", global_position, -2.0)
		go_down(from_dir, shooter)
		return
	super(dmg, from_dir, shooter)
	if alive and stick:
		_fumble_stick()
	if alive and blasted:
		shaken = min(1.0, shaken + 0.4)   # his own side's dynamite: no one to shoot back at
		_maybe_patch(global_position + from_dir * -40.0)
		return
	if alive and shooter is Enemy:   # the other gang's round: he's got his man to shoot back at
		foe = shooter
		shaken = min(1.0, shaken + 0.3)
		queue_reaction(shooter.global_position, true, true)
		_maybe_patch(shooter.global_position)
		return
	if alive:
		on_hurt_alert(shooter)
		shaken = min(1.0, shaken + 0.3)
		queue_reaction(shooter.global_position, true, true)
		if st == St.COMBAT:
			last_known = shooter.global_position
			lost_t = 0.0
		_maybe_patch(shooter.global_position)
