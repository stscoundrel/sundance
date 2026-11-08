extends SceneTree
## How much of the town the window shows, and the HUD laid out on it:
##   fit     - the art in whole pixels: three screen pixels a world pixel in a
##             1280x720 window (the view it always had), more town on a bigger
##             screen, never past VIEW_CAP (a 4K screen sees what a 1080p one does,
##             in bigger pixels); a 21:9 screen sees wider, not shorter; the HUD at
##             the most whole scale its 640x360 page fits.
##   window  - the game opens at 1280x720 as it always has; resized, the camera and
##             the HUD follow (the page grows, the corners go with it).
##   menus   - on a wider screen the menus' page sits in the middle, and a click on
##             a gun's name or a town's row still lands on it.
##   fright  - the machine gun's rout reaches as far whatever the window: a man off
##             the old view's edge doesn't take fright on a big screen either.
##   godot --headless --path . --fixed-fps 60 -s tests/test_view.gd

var game: Node
var frame := 0
var failures := 0
var step := ""


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_civilians", true)
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _fit() -> void:
	step = "fit"
	var g = game.get_script()
	var want := {
		Vector2(1280, 720): Vector2i(3, 2), Vector2(1920, 1080): Vector2i(3, 3),
		Vector2(2560, 1440): Vector2i(4, 4), Vector2(3840, 2160): Vector2i(6, 6),
		Vector2(2560, 1080): Vector2i(3, 3), Vector2(3440, 1440): Vector2i(4, 4),
		Vector2(2880, 1800): Vector2i(5, 4), Vector2(960, 540): Vector2i(2, 1),
	}
	for px in want:
		check(g.view_fit(px) == want[px], "%s: zoom and HUD scale %s, not %s" % [px, g.view_fit(px), want[px]])
	for w in range(800, 5200, 70):
		for h in range(480, 2900, 90):
			var f: Vector2i = g.view_fit(Vector2(w, h))
			var view := Vector2(w, h) / f.x
			check(view.x <= g.VIEW_CAP.x + 0.01 and view.y <= g.VIEW_CAP.y + 0.01, "%dx%d shows %s, past the cap" % [w, h, view])
			check(f.x >= mini(g.VIEW_ZOOM, h / 240) or f.x > 0 and h < 720, "%dx%d: art smaller than it ever was (zoom %d)" % [w, h, f.x])
			check(Vector2(w, h) / f.y >= Hud.PAGE, "%dx%d: the HUD's page doesn't fit (scale %d)" % [w, h, f.y])
	check(Vector2(1920, 1080) / g.view_fit(Vector2(1920, 1080)).x == Vector2(640, 360), "1080p should see 640x360 of the town")
	check(Vector2(3840, 2160) / g.view_fit(Vector2(3840, 2160)).x == Vector2(640, 360), "4K should see what 1080p does")


func _window() -> void:
	step = "window"
	check(game.camera.zoom == Vector2(3, 3), "1280x720 should be zoom 3, as ever (%s)" % game.camera.zoom)
	check(game.hud.page == Hud.PAGE and game.hud_layer.scale == Vector2(2, 2), "the HUD at 1280x720 should be its page at 2x")
	root.size = Vector2i(2560, 1080)
	check(game.camera.zoom == Vector2(3, 3) and game.hud_layer.scale == Vector2(3, 3), "2560x1080: zoom %s, HUD %s" % [game.camera.zoom, game.hud_layer.scale])
	check(game.hud.page == Vector2(853, 360), "2560x1080's HUD page should be 853x360 (%s)" % game.hud.page)


func _menus() -> void:
	step = "menus"
	check(game.hud.menu_at() == Vector2(106, 0), "the menus should sit in the middle (%s)" % game.hud.menu_at())
	game.picked.assign(["colt"])
	game._to_loadout()
	var i := Player.ORDER.find("rifle")
	var at: Vector2 = game.hud._option(i, Player.choices("rifle").find("henry")).get_center() + game.hud.menu_at()
	check(game.hud.loadout_hit(at) == "henry", "a click on the Henry's name hit %s" % game.hud.loadout_hit(at))
	check(game.hud.loadout_hit(at - game.hud.menu_at()) != "henry", "the cards are still drawn at the left")
	check(game.hud.level_hit(game.hud._row(1).get_center() + game.hud.menu_at()) == 1, "a click on the second town missed it")
	game.state = "play"


func _fright() -> void:
	step = "fright"
	var g = game.get_script()
	var seen: Vector2 = g.HUD_PAGE * 2.0 / g.VIEW_ZOOM
	var c: Vector2 = game.camera.get_screen_center_position()
	var view := Rect2(c - seen / 2.0, seen)
	var shown: Vector2 = game.get_viewport_rect().size / game.camera.zoom.x
	check(shown.x > seen.x + 100, "the big window should show more than the old view (%s)" % shown)
	# _gun_fright's view is the old one: a point past its edge but on this screen is out
	var edge := c + Vector2(seen.x / 2.0 + 40.0, 0)
	check(not view.has_point(edge) and Rect2(c - shown / 2.0, shown).has_point(edge), "the test point should be on screen but off the old view")


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		_fit()
		_window()
	if frame == 5:
		_menus()
		_fright()
		print("view test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
	return false
