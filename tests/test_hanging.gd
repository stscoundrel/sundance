extends SceneTree
## San Miguel's hanging (the rest of the gang out of town; no townsfolk but him):
##   setup   - a hangman at the foot of the gallows steps, the condemned man up on
##             the trap, bound; the hour on the clock.
##   rope    - the hour comes, the trap goes and he kicks; the stranger aims at the
##             rope where it's drawn (well up off the trap) from across the plaza,
##             west, north or south: the round flies over the platform's edge and
##             parts it. He's down, runs into a building and stays there. Saved.
##   kick    - nobody comes: a few seconds on the rope and he's hanged; still there.
##             The end card says the stranger failed him.
##   spotted - the hangman sees the stranger with his own eyes and goes for the
##             lever: the trap goes long before the hour.
##   stopped - the hangman shot dead in the moment it takes him: no drop, not even at
##             the hour (there's nobody to pull it). The stranger cuts him loose (hold
##             E at the gallows) and he's off down the steps.
##   stray   - a bandit's round lined up on the man before the drop carries over the
##             platform and kills him; one that isn't lined up on him stops at its edge.
##   aimed   - the stranger's round at the man on the trap, before the drop: it counts
##             as the rope, and he's loose and down the steps.
##   pinned  - gunfire all round him and the hangman keeps his place, and nobody
##             takes him off it to rescue a downed man. Once it stops he calms down
##             (no red cone, the town goes quiet again).
##   tether  - with the man cut down, the hangman is still the gallows' man: sent off
##             to scout he comes back, fighting the stranger he keeps within reach
##             of his post, losing him he walks back to it, and the posse goes
##             without him.
##   godot --headless --path . --fixed-fps 60 -s tests/test_hanging.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var queue := ["setup", "rope", "rope_n", "rope_s", "kick", "spotted", "stopped", "stray", "aimed", "pinned", "tether"]
# where the rope is shot from (tiles): across the plaza from the west, the north and the south
const SIDES := {"rope": Vector2(27, 38), "rope_n": Vector2(32, 33.5), "rope_s": Vector2(31, 42)}
var t := 0.0
var phase := 0
var mark := 0.0
var flown: Node = null


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_alarm", true)
	_fresh()


func _fresh() -> void:
	if game:
		game.queue_free()
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	t = 0.0
	phase = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func h() -> Hanging:
	return game.hanging


## A round from `from` (tiles) at `to` (screen).
func _fire(from: Vector2, to: Vector2, by: Actor) -> Node:
	var a := Iso.to_screen(from)
	return game.spawn_bullet(a, (to - a).normalized() * 900.0, 600.0, 2, by, Iso.GUN_H, false)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		Engine.time_scale = 1.0
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			if not e.hangman:
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.global_position += Vector2(0, -4000)
		step = queue[0]
		return false
	if frame < 3:
		return false
	t += delta
	match step:
		"setup":
			check(h() != null, "no hanging in San Miguel")
			var hm: Enemy = h().hangman
			check(hm.alive and hm.hangman and hm.global_position.distance_to(h().trap) < 70.0, "no hangman by the gallows")
			check(h().man.bound and h().man.alive and h().man.global_position == h().trap, "the man isn't on the trap")
			check(h().man.lift.y < -20.0, "he isn't up on the platform")
			check(h().state == "waiting" and h().seconds_left() > 200.0, "the hour isn't set: %s, %.0f" % [h().state, h().seconds_left()])
			check("condemned man: saved" in game._tally(), "the end card doesn't count him")
			_next()
		"rope", "rope_n", "rope_s":
			if phase == 0:
				h().at = game.clock + 1.0
				phase = 1
			elif phase == 1 and h().state == "hanging":
				check(h().rope != null, "no rope to shoot")
				check(h().man.hurtbox.collision_layer == 0, "he can still be hit, hanging there")
				# the cursor on the rope where it's drawn, between the beam and his neck
				var on_rope := h().trap + Vector2(0, -40)
				check(h().under(on_rope), "the rope isn't under the cursor at %s" % on_rope)
				game.player.global_position = Iso.to_screen(SIDES[step])
				var aim: Vector2 = game.player.aim_ground(on_rope)
				check(aim == h().trap, "aimed at the rope, the shot goes to %s, not the trap" % aim)
				var a: Vector2 = game.player.global_position
				game.spawn_bullet(a, (aim - a).normalized() * 900.0, 600.0, 2, game.player, Iso.GUN_H, false)
				phase = 2
				mark = t
			elif phase == 2 and h().state == "freed":
				check(not h().man.bound and h().man.alive, "he's not loose")
				check(game.stats.get("rope shot", false), "the stranger's round didn't get the credit")
				phase = 3
			elif phase == 2 and t - mark > 1.0:
				check(false, "the rope didn't part: %s" % h().state)
				_next()
			elif phase == 3 and h().man.gone():
				check("condemned man: saved" in game._tally(), "the end card: %s" % game._tally())
				game.quiet_after = 0.5
				phase = 4
				mark = t
			elif phase == 4 and t - mark > 4.0:
				check(h().man.gone(), "he came back out")
				_next()
			elif t > 25.0:
				check(false, "stuck at phase %d (%s, %s)" % [phase, h().state, h().man.st])
				_next()
		"kick":
			if phase == 0:
				h().at = game.clock + 0.5
				phase = 1
			elif phase == 1 and h().state == "hanging":
				phase = 2
				mark = t
			elif phase == 2 and h().state == "hanged":
				check(t - mark > Hanging.KICK_T - 0.5, "he was gone too soon (%.1f s)" % (t - mark))
				check("hanged, you failed him" in game._tally(), "the end card: %s" % game._tally())
				check(h().man.global_position == h().trap, "he's not hanging from the gallows")
				_next()
			elif t > 15.0:
				check(false, "stuck at phase %d (%s)" % [phase, h().state])
				_next()
		"spotted":
			var hm: Enemy = h().hangman
			if phase == 0:
				game.player.global_position = hm.global_position + hm.facing * 100.0
				phase = 1
			elif phase == 1 and h().state == "lever":
				check(hm.global_position.distance_to(hm.home) < 8.0, "he left his place for the lever")
				phase = 2
				mark = t
			elif phase == 2 and h().state == "hanging":
				check(absf(t - mark - Hanging.LEVER_T) < 0.3, "the trap went %.1f s after he saw him" % (t - mark))
				check(h().seconds_left() > 200.0, "it wasn't early")
				_next()
			elif t > 10.0:
				check(false, "stuck at phase %d (%s, saw %s)" % [phase, h().state, hm.sees_player])
				_next()
		"stopped":
			var hm: Enemy = h().hangman
			if phase == 0:
				game.player.global_position = hm.global_position + hm.facing * 100.0
				phase = 1
			elif phase == 1 and h().state == "lever":
				hm.die(Vector2.RIGHT, game.player)
				game.player.global_position = Iso.to_screen(Vector2(-40, -40))
				phase = 2
				mark = t
			elif phase == 2 and t - mark > Hanging.LEVER_T + 0.5:
				check(h().state == "waiting", "the trap went with him dead: %s" % h().state)
				check("hangman's dead" in game.hud.banner_text, "no word that the hangman's dead: %s" % game.hud.banner_text)
				h().at = game.clock + 0.2
				phase = 3
				mark = t
			elif phase == 3 and t - mark > 1.0:
				check(h().state == "waiting", "the hour dropped him with nobody at the lever: %s" % h().state)
				# up to the platform's edge, from the plaza's open side, and the knife out
				game.player.process_mode = Node.PROCESS_MODE_INHERIT
				game.player.global_position = h().trap + (Iso.to_screen(Vector2(30.0, 38.0)) - h().trap)
				check(h().can_cut(game.player.global_position), "the edge isn't close enough to cut him loose (%.0f px)"
					% game.player.global_position.distance_to(h().trap))
				Input.action_press("knife")
				phase = 4
				mark = t
			elif phase == 4 and h().state == "freed":
				Input.action_release("knife")
				check(t - mark > Hanging.CUT_T - 0.1, "cut loose too quickly (%.2f s)" % (t - mark))
				check(h().man.global_position.distance_to(h().steps) < 20.0, "he didn't come down the steps")
				phase = 5
			elif phase == 4 and t - mark > 3.0:
				Input.action_release("knife")
				check(false, "the knife didn't free him")
				_next()
			elif phase == 5 and h().man.gone():
				_next()
			elif t > 25.0:
				Input.action_release("knife")
				check(false, "stuck at phase %d (%s)" % [phase, h().state])
				_next()
		"stray":
			if phase == 0:
				var off := h().trap + Vector2(0, 14)   # (the gallows' front, not him)
				flown = _fire(Vector2(28, 40), off, h().hangman)
				check(not h().over_gallows(Iso.to_screen(Vector2(30.5, 39.0)), off - Iso.to_screen(Vector2(28, 40))),
					"a round wide of him counts as lined up")
				phase = 1
				mark = t
			elif phase == 1 and t - mark > 0.5:
				check(h().man.alive, "a round wide of him killed him")
				_fire(Vector2(28, 38), h().trap, h().hangman)
				phase = 2
				mark = t
			elif phase == 2 and t - mark > 0.5:
				check(not h().man.alive and h().state == "shot", "the round didn't reach him: %s" % h().state)
				check("shot dead, you failed him" in game._tally(), "the end card: %s" % game._tally())
				_next()
		"aimed":
			if phase == 0:
				_fire(Vector2(28, 38), h().trap, game.player)
				phase = 1
				mark = t
			elif phase == 1 and t - mark > 0.5:
				check(h().man.alive and h().state == "freed", "the stranger's round at him: %s, alive %s" % [h().state, h().man.alive])
				check(h().man.global_position.distance_to(h().steps) < 20.0, "he didn't come down the steps")
				_next()
		"tether":
			var hm: Enemy = h().hangman
			var away: float = hm.global_position.distance_to(hm.home)
			if phase == 0:
				h().rope_shot(game.player)
				check(h().state == "freed", "the man isn't loose: %s" % h().state)
				var posse := Posse.new(game)
				posse.form()
				check(not hm in posse.members, "the posse took the hangman along")
				for e in posse.members:
					e.in_posse = false
				hm.st = Enemy.St.GUARD
				hm.scout(Iso.to_screen(Vector2(20, 25)))
				phase = 1
				mark = t
			elif phase == 1:
				check(away < Enemy.LEASH + 15.0, "off scouting, %.0f px from the gallows" % away)
				if t - mark > 6.0:
					# the stranger out in the plaza, in his sights, and the fight on
					game.player.global_position = hm.home + Vector2(-150, 60)
					hm.enter_combat(game.player.global_position, true, true)
					phase = 2
					mark = t
			elif phase == 2:
				check(away < Enemy.LEASH + 15.0, "fighting %.0f px from the gallows" % away)
				if t - mark > 8.0:
					game.player.global_position = Iso.to_screen(Vector2(-40, -40))   # gone
					phase = 3
					mark = t
			elif phase == 3 and t - mark > 15.0:
				check(away < 10.0, "he didn't go back to his place (%.0f px off, st %d)" % [away, hm.st])
				check(hm.st != Enemy.St.COMBAT, "still fighting nobody")
				_next()
		"pinned":
			var hm: Enemy = h().hangman
			if phase == 0:
				hm.enter_combat(Iso.to_screen(Vector2(30, 30)), false, false)
				var downed: Enemy = game.enemies.filter(func(e): return e != hm)[0]
				downed.process_mode = Node.PROCESS_MODE_INHERIT
				downed.global_position = hm.global_position + Vector2(40, 10)
				downed.go_down(Vector2.RIGHT, game.player)
				phase = 1
				mark = t
			elif phase == 1:
				if int(t * 4.0) != int((t - delta) * 4.0):
					var o := Iso.to_screen(Vector2(41, 37))   # (from the east, falling short beside him: not into him or the man)
					var to: Vector2 = hm.global_position + Vector2(25, 22.0 * (1 if randf() < 0.5 else -1))
					game.spawn_bullet(o, (to - o).normalized() * 900.0, o.distance_to(to), 1, game.player, Iso.GUN_H, false)
				check(hm.global_position.distance_to(hm.home) < 10.0, "he left the gallows (%.0f px)" % hm.global_position.distance_to(hm.home))
				check(hm.rescuing == null, "he went off to rescue a man")
				check(hm.alive and h().state == "waiting", "the shooting killed him (or the man: %s)" % h().state)
				if t - mark > 6.0:
					phase = 2
					mark = t
			elif phase == 2:
				if t - mark > 12.0:
					check(hm.st != Enemy.St.COMBAT, "still fighting nothing at the gallows")
					check(game.quiet_for() > 5.0, "the town never went quiet (%.1f)" % game.quiet_for())
					_next()
	return false


func _next() -> void:
	queue.pop_front()
	if queue.is_empty():
		print("hanging test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures > 0 else 0)
		return
	_fresh()
