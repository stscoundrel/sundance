class_name Brass
extends Node2D
## Spent cases and shotgun shells lying where they fell, for the rest of the fight: a
## Winchester's brass round the spot a man held, a Schofield's six in a ring at his
## boots. Flat on the ground under everyone, a pixel each, as they looked coming to
## rest. The ground is cut into squares, each drawing its own, so a new case only
## redraws the few near it; past CAP the oldest go, so a long battle never piles up
## more than the screen can carry.

const CAP := 2000
const CELL := 256.0   # px a side of each square of ground

var cells := {}    # Vector2i -> Cell
var order: Array = []   # [Cell, case] oldest first, for dropping past the cap
var count := 0
static var rng := RandomNumberGenerator.new()   # (where on the ground each one comes down: its own dice)


## One square of ground's cases.
class Cell extends Node2D:
	var cases: Array = []   # [pos, color]

	func _draw() -> void:
		for c in cases:
			draw_rect(Rect2(c[0] - Vector2(0.5, 0.5), Vector2.ONE), c[1])


## A case come to rest at `p` (on the ground plane, world px).
func add(p: Vector2, color: Color) -> void:
	var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var cell: Cell = cells.get(k)
	if cell == null:
		cell = Cell.new()
		cells[k] = cell
		add_child(cell)
	color.a = 1.0
	var c := [p, color]
	cell.cases.append(c)
	cell.queue_redraw()
	order.append([cell, c])
	count += 1
	if count > CAP:
		var old: Array = order.pop_front()
		var oc: Cell = old[0]
		oc.cases.erase(old[1])
		oc.queue_redraw()
		count -= 1
