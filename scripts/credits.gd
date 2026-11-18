class_name Credits
extends RefCounted
## The end credits, after the funeral: whether the lid gave or the earth went in
## over him, the picture's over, and the names come up a card at a time over the
## burial ground gone dark, the way the films closed. The stranger's cast first
## (played by whoever was at the keys), the crew, how it was made, and the films
## and the music it owes; the last card is the ending's own, FINE over a filled
## grave, the level's name if he climbed out. The cards are data/credits.json.
## Each fades in, stands, and fades out (counted in real time: it's only to look
## at). A click or Enter moves it on a card; the last stays till he's read it.

const PATH := "res://data/credits.json"
const FADE := 0.8    # s in, and s out again
const HOLD := 3.0    # s a card stands where it names no "for"
const SKIP_IN := 0.25   # s a card skipped to takes to come up (a click shouldn't flash past it)

var cards: Array = []
var i := 0           # the card up now
var t := 0.0         # real s since it started to come up
var ending := ""     # "out" (he broke out) or "buried"


static func make(how: String) -> Credits:
	var c := Credits.new()
	c.ending = how
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	c.cards = data["cards"].duplicate()
	c.cards.append(data["ends"][how])
	return c


func card() -> Dictionary:
	return cards[i]


func last() -> bool:
	return i == cards.size() - 1


## How long the card up now stays, fades and all.
func span() -> float:
	return FADE + float(card().get("for", HOLD)) + FADE


func step(real: float) -> void:
	t += real
	if t >= span() and not last():
		i += 1
		t = 0.0
	if last():
		t = minf(t, FADE + float(card().get("for", HOLD)))   # (it never fades: it's the end)


## The next card, at once (a click or Enter). Says whether there was one.
func next() -> bool:
	if last():
		return false
	i += 1
	t = FADE - SKIP_IN
	return true


## How much of the card up now is showing, 0..1.
func alpha() -> float:
	var hold := span() - FADE
	if t < FADE:
		return t / FADE
	if t > hold and not last():
		return maxf(0.0, (span() - t) / FADE)
	return 1.0


## The last card's been up long enough to read: the way on can be offered.
func read() -> bool:
	return last() and t >= FADE + 1.0
