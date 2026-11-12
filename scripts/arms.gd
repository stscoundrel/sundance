class_name Arms
extends RefCounted
## The guests' long guns at the stranger's funeral (the map's "arms"). Nobody wears
## a rifle to a burial: every guest has only his pistol on him ("pistols_only"),
## and his long gun is where he left it, in the scabbard on his saddle, in his wagon
## by the road, or in a rack (by the cemetery gate, inside the cantina's door). A
## guest who runs for his goes to the nearest of these that isn't by the stranger
## (Enemy "arm"), takes it, and comes back to the fight with it: his type's own long
## gun, loaded.
##
## The stranger can take one too (F, standing by it): one gun to a saddle or a wagon,
## a few to a rack ("count": the one by the cemetery gate holds four), loaded and
## nothing spare, drawn when the town's built from the kinds a guest would
## have left there. A way out of his twelve rounds, at the risk of going where
## they're going.

static var rng := RandomNumberGenerator.new()   # (which gun is in which saddle: its own dice)

const REACH := 22.0        # px: close enough to take it out
const NEAR_HIM := 150.0    # px: a guest won't run for a place this near the stranger...
const DETOUR := 260.0      # ...unless it's this much nearer than any other
const KINDS := {
	"saddle": {"rifle": 3.0, "henry": 2.0, "spencer": 2.0, "springfield": 1.0, "remington": 1.0},
	"wagon": {"coach": 3.0, "rifle": 2.0, "springfield": 2.0, "spencer82": 1.0},
	"rack": {"rifle": 1.0, "coach": 1.0},
}

var game: Node
var places: Array[Dictionary] = []   # each: at (screen), kind, and for the stranger: "offer" (the gun, or {} once taken)


func _init(g: Node, points: Array) -> void:
	game = g
	for p in points:
		var place := {"at": Iso.to_screen(Vector2(p["x"], p["y"])), "kind": p["kind"], "left": int(p.get("count", 1))}
		_restock(place)
		places.append(place)


## The next gun in it for the stranger, as it was left: loaded, nothing spare (or none
## left, the rack bare).
func _restock(place: Dictionary) -> void:
	if place["left"] <= 0:
		place["offer"] = {}
		return
	var gun := _draw(KINDS[place["kind"]])
	place["offer"] = {"kind": gun, "weapon": Weapon.new(gun, null), "sprite": null, "at": place["at"], "place": place}


func _draw(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[-1]


## Where a guest at `from` runs for his long gun: the nearest place not right by the
## stranger, unless it's much the nearest. INF if there's nowhere.
func nearest_for(from: Vector2) -> Vector2:
	var him: Vector2 = game.player.global_position
	var best := Vector2.INF
	var best_d := INF
	for p in places:
		var d: float = from.distance_to(p["at"])
		if p["at"].distance_to(him) < NEAR_HIM:
			d += DETOUR
		if d < best_d:
			best_d = d
			best = p["at"]
	return best


## The gun the stranger could take where he stands (F), or {}.
func offer(at: Vector2) -> Dictionary:
	for p in places:
		if not p["offer"].is_empty() and at.distance_to(p["at"]) < REACH:
			return p["offer"]
	return {}


## He takes it: into its slot, loaded as it was left; what he had there goes down at
## his feet (see game.receive_gun).
func hand_over(o: Dictionary) -> void:
	var place: Dictionary = o["place"]
	place["left"] -= 1
	_restock(place)
	var at: Vector2 = game.player.global_position + Vector2(6, 2)
	game.hud.toast(game.receive_gun(o["kind"], o["weapon"], at, "from the " + place["kind"], rng))
	game.stats["guns from saddles"] = game.stats.get("guns from saddles", 0) + 1
