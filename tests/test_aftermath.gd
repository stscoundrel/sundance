extends SceneTree
## The aftermath. Four bandits lie dead with nobody about to see it (the rest held
## still, the hero off the map). Once the town is quiet the undertaker and his
## apprentice claim them, measure them and drag them up to boot hill. A shot
## mid-drag makes the undertaker drop his man and run indoors; when it's quiet again
## he comes back out and finishes the job. Buried men are no longer anything for the
## bandits to find. A townsman lies dead too: the padre blesses anyone, and the
## undertakers take a blessed man before an unblessed one. The quiet period is
## shortened so the test runs quickly. The padre, for his part, never runs:
##   godot --headless --path . --fixed-fps 60 -s tests/test_aftermath.gd

const QUIET := 8.0
const LIMIT := 420.0

var game: Node
var frame := 0
var clock := 0.0
var failures := 0
var dead: Array[Enemy] = []
var townsman: Civilian
var blessed_first := 0   # bandits blessed before they were buried
var crosses_before := 0
var shot_at := -1.0
var dropped: Enemy
var scared: Civilian
var stages := {}   # what happened, and when


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _crosses(kind := "cross") -> int:
	var n := 0
	for c in game.world.get_children():
		if c is Sprite2D and c.texture == game.tex(game.meta["objects"][kind]["file"]):
			n += 1
	return n


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.quiet_after = QUIET
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))   # off the map, unseen
		game.player.hp = 1000000
		_kill_three()
		crosses_before = _crosses()
	if frame <= 3:
		return false
	clock += delta
	if clock >= 3.0 and clock - delta < 3.0:
		_prefers_blessed()   # once they've fallen, before the town is quiet
		_fearless()
	var undertakers: Array[Civilian] = []
	for c in game.civilians:
		if c.undertaker:
			undertakers.append(c)
	for u in undertakers:
		if u.st == Civilian.St.MEASURE and not stages.has("measure"):
			stages["measure"] = clock
		if u.st == Civilian.St.DRAG and not stages.has("drag"):
			stages["drag"] = clock
		# three seconds into his first haul, a shot rings out nearby
		if u.st == Civilian.St.DRAG and shot_at < 0.0 and clock - stages["drag"] > 3.0:
			shot_at = clock
			dropped = u.body
			scared = u
			game.make_noise(u.global_position + Vector2(40, 0), 380.0, "enemy_shot", null)
	if shot_at > 0.0 and clock - shot_at > 1.0 and not stages.has("dropped"):
		stages["dropped"] = clock
		check(scared.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE], "the undertaker kept dragging under fire")
		check(not dropped.has_meta("buried") and not dropped.has_meta("claimed_by"), "he should have let go of the body")
	if scared and scared.st == Civilian.St.GONE and not stages.has("hid"):
		stages["hid"] = clock
	if stages.has("hid") and scared.st != Civilian.St.GONE and not stages.has("back"):
		stages["back"] = clock
	var buried := 0
	for e in dead:
		buried += 1 if e.has_meta("buried") else 0
		if e.has_meta("blessed") and not e.has_meta("counted"):
			e.set_meta("counted", true)
			blessed_first += 0 if e.has_meta("buried") else 1
	if (buried < dead.size() or not townsman.has_meta("blessed")) and clock < LIMIT:
		return false
	print("after %.0f s: %d of %d buried, %d new crosses; stages %s; %s" % [clock, buried, dead.size(),
		_crosses() - crosses_before, stages, game.stats])
	check(buried == dead.size(), "only %d of %d bodies buried" % [buried, dead.size()])
	check(_crosses() - crosses_before == buried, "every burial should leave a cross")
	check(_crosses("mound") == buried, "every new grave should have a fresh mound")
	# the blood stays where each man fell, not under him on boot hill
	for e in dead:
		var pooled := false
		for s in game.decals.get_children():
			pooled = pooled or (s is Sprite2D and s.position.distance_to(e.global_position) > 60.0)
		check(pooled, "no blood pool left behind where the %s fell" % e.kind)
	check(stages.has("measure") and stages["measure"] >= QUIET, "the undertakers went to work before the town was quiet")
	check(stages.has("back"), "the undertaker never came back out after the shot")
	check(townsman.has_meta("blessed"), "the padre never blessed the dead townsman")
	check(not townsman.has_meta("buried"), "the undertakers should leave townsfolk be (for now)")
	print("blessings %d, bandits blessed before burial %d of %d" % [game.stats.get("blessings", 0), blessed_first, dead.size()])
	check(blessed_first >= 1, "the padre never got to a bandit before the undertakers")
	for e in dead:
		check(not e.visible, "a buried body is still lying about")
	# buried men are no evidence: a bandit standing on boot hill finds nothing
	var b: Enemy = null
	for e in game.enemies:
		if e.alive:
			b = e
	b.known_corpses.clear()
	b.st = Enemy.St.GUARD
	for g in game.graves:
		b.global_position = g + Vector2(20, 0)
		b.facing = Vector2.LEFT
		b._perceive(0.1)
	check(b.st != Enemy.St.SEARCH, "a bandit found a buried body")
	print("aftermath test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


## Three bandits go down, the ones nearest the undertakers; nobody makes a fuss.
func _kill_three() -> void:
	var undertakers: Array[Vector2] = []
	for c in game.civilians:
		if c.undertaker:
			undertakers.append(c.global_position)
	var near: Array = []
	for e in game.enemies:
		var d := INF
		for u in undertakers:
			d = minf(d, u.distance_to(e.global_position))
		near.append([d, e])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in 3:
		dead.append(near[i][1])
	# and one up by the church, where the padre gets to him before the undertakers
	var church := Iso.to_screen(Vector2(31.2, 9.0))
	var by_church: Enemy = null
	for e in game.enemies:
		if not e in dead and (by_church == null or e.global_position.distance_to(church) < by_church.global_position.distance_to(church)):
			by_church = e
	dead.append(by_church)
	for e in game.enemies:
		if not e in dead:
			e.process_mode = Node.PROCESS_MODE_DISABLED   # the rest hold still
	for e in dead:
		e.die(Vector2.RIGHT)
	# and a townsman, down by the church (the padre's nearest)
	var best := INF
	for c in game.civilians:
		if not (c.undertaker or c.priest) and c.global_position.distance_to(church) < best:
			best = c.global_position.distance_to(church)
			townsman = c
	townsman.die(Vector2.RIGHT)
	for e in game.enemies:
		if e.alive:
			e.st = Enemy.St.GUARD   # whoever saw it keeps it to himself: this is about the quiet
			e.known_corpses.append_array(dead)
	print("dead: %s" % [dead.map(func(e): return "%s at %s" % [e.kind, Iso.to_grid(e.global_position).round()])])


## An undertaker passes up a nearer unblessed man for a blessed one.
func _prefers_blessed() -> void:
	var u: Civilian = null
	for c in game.civilians:
		if c.undertaker:
			u = c
	var by_dist := dead.duplicate()
	by_dist.sort_custom(func(a, b): return a.global_position.distance_to(u.global_position) < b.global_position.distance_to(u.global_position))
	var far: Enemy = by_dist[by_dist.size() - 1]
	far.set_meta("blessed", true)
	var got: Enemy = game.claim_body(u)
	check(got == far, "the undertaker took %s over the blessed %s" % [got.kind if got else "nobody", far.kind])
	if got:
		got.remove_meta("claimed_by")
	far.remove_meta("blessed")


## The padre fears no man: gunfire, a near miss, a killing in front of him, he
## stays where he is.
func _fearless() -> void:
	for c in game.civilians:
		if c.priest:
			c.hear(c.global_position + Vector2(30, 0), 380.0, "shot", game.player)
			c.near_miss(c.global_position + Vector2(40, 0))
			c.witness_murder(c.global_position + Vector2(20, 0))
			check(not c.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE],
				"the padre ran from the shooting (%s)" % Civilian.St.keys()[c.st])
