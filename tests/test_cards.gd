extends SceneTree
## The loadout screen's cards hold every gun the stranger can buy, however many
## there come to be: each new gun has tended to break this screen, its name cut
## off at the card's edge or its line sunk under the kit below.
##   order  - each card lists its guns from the dearest down.
##   fit    - every gun's line lies inside its card, clear of the next, with its
##            name and price in full; the name and blurb under the picture fit the
##            card; the cards stand above the kit and RIDE IN, and all of it on the
##            page.
##   art    - every gun on a card has a blurb and its picture for the card.
##   godot --headless --path . --fixed-fps 60 -s tests/test_cards.gd

var game: Node
var frame := 0
var failures := 0
var step := ""


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_civilians", true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _width(s: String) -> float:
	return game.hud.small.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x


func _order() -> void:
	step = "order"
	for slot in Player.ORDER:
		var prices: Array = Player.choices(slot).map(func(k): return int(Weapon.DATA[k].get("points", 0)))
		var sorted := prices.duplicate()
		sorted.sort()
		sorted.reverse()
		check(prices == sorted, "%s card not dearest first: %s" % [slot, prices])
	check(Player.choices("coach")[0] == "spencer82" and Player.choices("rifle")[0] == "rifle",
		"the pump gun and the Winchester should head their cards")


func _fit() -> void:
	step = "fit"
	var hud: Hud = game.hud
	var page := Rect2(Vector2.ZERO, Hud.PAGE)
	var lowest := 0.0
	check(_width("REMINGTON ROLLING BLOCK") > 80.0, "the small font measures nothing: this test can't see")
	for i in Player.ORDER.size():
		var slot: String = Player.ORDER[i]
		var card: Rect2 = hud._card(i)
		check(page.encloses(card), "%s card off the page: %s" % [slot, card])
		lowest = maxf(lowest, card.end.y)
		var options := Player.choices(slot)
		for j in options.size():
			var k: String = options[j]
			var line: Rect2 = hud._option(i, j)
			var name: String = Weapon.DATA[k]["name"]
			check(card.encloses(line), "%s's line sticks out of the %s card (%s in %s)" % [k, slot, line, card])
			check(line.end.x + 16 <= card.end.x, "%s's price past the %s card's edge" % [k, slot])
			check(_width(name) <= line.size.x, "%s's name cut off: %.0f px in %.0f" % [name, _width(name), line.size.x])
			check(line.get_center().x - _width(name) / 2 - 9 >= card.position.x + 2, "%s's > marker off the card" % k)
			if j > 0:
				check(line.position.y >= hud._option(i, j - 1).end.y, "%s's line over the one above" % k)
			check(_width(name) <= card.size.x - 8, "%s's name too wide under the picture" % name)
			check(_width(Hud.BLURB.get(k, "")) <= card.size.x - 8, "%s's blurb too wide for the card" % k)
	for k in Hud.KIT_NAME:
		var box: Rect2 = hud._kit_box(k)
		check(box.position.y > lowest, "the %s box over a card" % k)
		check(page.encloses(box), "the %s box off the page" % k)
		check(_width("> " + Hud.KIT_NAME[k]) <= box.size.x - 30, "the %s box's name runs into its price" % k)
	check(hud._ride().position.y > lowest and page.encloses(hud._ride()), "RIDE IN over a card or off the page")


func _art() -> void:
	step = "art"
	for slot in Player.ORDER:
		for k in Player.choices(slot):
			check(Hud.BLURB.has(k), "%s has no blurb on its card" % k)
			check(game.meta["ui"]["guns"].has(k), "%s has no picture for its card" % k)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		_order()
		_fit()
		_art()
		print("cards test: ", "OK" if failures == 0 else "%d FAILED" % failures)
		return true
	return false
