class_name Strongbox
extends Node2D
## Silencio's prize: the outlaws' stolen gold in an iron-bound strongbox (the map's
## "strongbox", in the hideout's doorway; and "horse", where the stranger left his).
## He takes it up (E, a second bent to it), carries it in both arms, no gun and no
## knife, slower than walking (slower again crouched, and quiet), and sets it down
## again (E), or lets it drop where he stands to draw. Get it to his horse and he's
## away with it: the level's won.
##
## The outlaws miss it the first time one of them looks at the empty doorway, and
## turn out to look for it: their alarm up, men sent round the hideout and towards
## where the stranger was last seen. A trapper (a type that "fetches") who comes on
## it lying out somewhere carries it home again, unless he's got the stranger to
## deal with first. Who they'll blame for it (the hunters?) is for later.

static var rng := RandomNumberGenerator.new()   # (where the search goes, the thud: its own dice)

const REACH := 18.0      # px: close enough to take it up
const LIFT_T := 1.0      # s bent to it, taking it up
const NOTICE := 200.0    # px: an outlaw this near the empty doorway, looking at it, misses it
const LOOKING := 1.2     # rad either side of where he faces: he's looking that way
const SEE := 170.0       # px: a trapper this near it lying out, in sight, goes for it
const HORSE := 30.0      # px from the horse: up and away
const SEARCHERS := 6     # sent out to look when it's missed

var game: Node
var home := Vector2.ZERO
var horse := Vector2.ZERO
var sprite: Sprite2D
var holder: Actor = null
var fetcher: Enemy = null  # the outlaw on his way to take it home
var missed := false        # the outlaws know it's gone
var away := false          # the stranger rode off with it
var _look_t := 0.0


func setup(g: Node, at: Vector2, horse_at: Vector2) -> void:
	game = g
	var m: Dictionary = g.meta["objects"]["strongbox"]
	var fp := Vector2(m["footprint"][0], m["footprint"][1])
	home = Iso.to_screen(at + fp * 0.5)
	horse = Iso.to_screen(horse_at)
	global_position = home
	sprite = Sprite2D.new()
	sprite.texture = g.tex(m["file"])
	sprite.centered = false
	sprite.scale = Vector2.ONE * g.tex_scale
	sprite.offset = ((Iso.to_screen(at) - home) / g.tex_scale - Vector2(m["anchor"][0], m["anchor"][1])).round()
	add_child(sprite)


func lying() -> bool:
	return holder == null and not away


func at_home() -> bool:
	return lying() and global_position.distance_to(home) < 6.0


func can_take(p: Vector2) -> bool:
	return lying() and p.distance_to(global_position) < REACH


func take(a: Actor) -> void:
	holder = a
	sprite.visible = false   # (in his arms now: his carrying pose shows it)
	game.sfx("wood_hit", global_position, -14.0, 0.1, rng)


## Set down (or dropped) here: somewhere a man can get to it, or (home) right back
## where it was.
func put_down(at: Vector2) -> void:
	holder = null
	global_position = at if at == home or game.is_free(at) else game.free_point_near(at, 20.0, rng)
	sprite.visible = true
	game.sfx("wood_hit", global_position, -10.0, 0.1, rng)


func _physics_process(delta: float) -> void:
	if away:
		return
	if holder:
		var gone: bool = not is_instance_valid(holder) or not holder.alive
		if not gone and holder is Enemy:
			gone = holder.downed or holder.reaction != "fetch"   # (shot at, or the stranger: he lets it fall)
		elif not gone:
			gone = holder.down or holder.box != self
		if gone:
			if is_instance_valid(holder) and holder is Enemy:
				holder.let_go_of_box()   # (sets it down where he is)
			elif is_instance_valid(holder) and holder.alive and holder.box == self:
				holder.set_box_down()    # (the stranger down in the snow: it falls from his arms)
			if holder != null:
				put_down(holder.global_position if is_instance_valid(holder) else global_position)
		else:
			global_position = holder.global_position
			if holder == game.player and game.state == "play" and holder.global_position.distance_to(horse) < HORSE:
				_ride_off()
				return
	_look_t -= delta
	if _look_t > 0.0:
		return
	_look_t = 0.25
	if not missed and not at_home():
		_notice()
	if lying() and not at_home() and (fetcher == null or not is_instance_valid(fetcher) or fetcher.reaction != "fetch"):
		fetcher = null
		_find_fetcher()


## An outlaw who looks at the doorway and sees it empty.
func _notice() -> void:
	for e in game.enemies:
		if not e.alive or e.downed or e.gang != "outlaws" or not e.revealed:
			continue
		var to: Vector2 = home - e.global_position
		if to.length() < NOTICE and absf(e.facing.angle_to(to)) < LOOKING and game.line_of_sight(e.global_position, home, true):
			_missed(e)
			return


func _missed(by: Enemy) -> void:
	missed = true
	game.stats["gold missed"] = 1
	by._say("The gold! It's gone!")
	if game.level.has("turf"):   # (who else would take it but the hunters?)
		game.start_war("The gold's gone!  The outlaws blame the hunters!")
	else:
		game.hud.banner("The gold's gone!  The outlaws turn out to look for it!")
	game.raise_alarm(game.SEND + 10.0, home, "outlaws")
	var near: Array = game.enemies.filter(func(e): return e.alive and not e.downed and e.gang == "outlaws" \
		and e.reaction == "" and e.st != Enemy.St.COMBAT and not e.tdata.get("boss", false))
	near.sort_custom(func(a, b): return a.global_position.distance_to(home) < b.global_position.distance_to(home))
	for i in mini(SEARCHERS, near.size()):
		var e: Enemy = near[i]
		var round_home := home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, 260.0) * Vector2(1.0, 0.6)
		var towards: Vector2 = game.seen_pos if game.seen_pos != Vector2.ZERO else round_home
		e.scout(game.free_point_near(round_home if i % 2 == 0 else towards, 40.0, rng))


## A trapper who sees it lying out goes to take it home.
func _find_fetcher() -> void:
	var best: Enemy = null
	var best_d := SEE
	for e in game.enemies:
		if not e.alive or e.downed or e.gang != "outlaws" or not e.tdata.get("fetches", false) \
				or e.reaction != "" or e.st == Enemy.St.COMBAT or e.sees_player:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d and game.line_of_sight(e.global_position, global_position, true):
			best = e
			best_d = d
	if best:
		fetcher = best
		best.fetch(self)


func _ride_off() -> void:
	away = true
	holder = null
	game.stats["rode off with the gold"] = 1
	game.player.visible = false   # (in the saddle, and gone down the trail)
	game.end_level(true, "AWAY WITH THE GOLD")


## For the end card.
func line() -> String:
	if away:
		return "the outlaws' gold: yours   -   "
	if not at_home() and missed:
		return "the outlaws' gold: lost in the snow   -   "
	return ""
