# Sundance — Design Document

An isometric, pixel-art spaghetti western. One gunslinger, one dusty border town,
a gang of bandits. Built in Godot 4.

## Inspiration

- **Sergio Leone** — the stare-down, extreme close-ups of eyes, bleached skies,
  long dusters, wide-brimmed hats, ponchos, cigarillos, the church bell.
- **Sergio Corbucci** — mud, grime and brutality. Bleak frontier towns, coffins,
  gangs marked by red scarves, short merciless gunfights.
- **Sergio Sollima** — the Mexican border, revolutionaries and bounty hunters,
  bandoliers, sombreros, sun-baked adobe.
- **Commandos / Desperados (90s–early 2000s)** — 2:1 isometric pixel art,
  visible enemy vision cones, stealth into firefight.

## Core loop (v1)

Mode **Eliminate all enemies**. The player starts at the edge of town.
Bandits patrol and guard. Pick them off quietly or start a shootout.
Win when every bandit is dead, lose when the hero dies. Restart instantly.
A level can add someone to save on top of that (San Miguel's hanging, Cruz
Verde's prisoner, below): he can die and the fight goes on, but the end card says
the stranger failed him.

## Levels

After the title card comes the level picker (San Miguel, Cruz Verde and Paso Esperanza; the shuffled
San Miguels and the wave test are hidden, kept for the tests) ("Where to, stranger?"; up/down and
Enter, a number or a click), then the loadout. The levels are listed in
`data/levels.json`, each a map (a town file) and, optionally, a **count**: with one,
the gang is shuffled. Each map carries **guard posts** (San Miguel has 64, written by
`tools/make_town.py`: its own gang's 25 and more spread along the streets, alleys
and yards, none in sight of where the stranger rides in), tagged for who suits them:
`boss`, `porch` (those passing as townsfolk), `lookout` (riflemen), `street`,
`alley`, `yard`. A shuffled level deals `count` men out over them with the count as
the seed, so the same count is always the same town (adding posts reshuffles them,
which is fine). The mix is the map's own gang scaled to the count, always one El
Jefe; each man goes to a post of his kind, kept six tiles from the others where the
posts allow it, and posts on blocked ground are passed over. A smaller or bigger gang
scales its saloon reserve (2 to 8) and the size it bands into a posse (3 to 7). The
hand-drawn San Miguel stays first in the list, unshuffled: the tests and the tuning
lean on it. Picking another level reloads the scene with it, straight to the guns;
after a win or a loss, Enter goes back to the picker with the same level ready. A
map can do without streets (the posse rides between guard posts), townsfolk, a
reserve, a boot hill (no burials) or holdouts (no falling back), and can name its own
baked ground; the hidden "Test yard" proves it. `tests/test_levels.gd` checks the
posts, the deal and its determinism, the scaling and the picker; `tests/test_yard.gd`
plays the bare map to a win.

**Waves.** A level can bring more of the gang in at set times
(`"waves": [{"at": seconds, "groups": [{"from": road, "count": n}]}]`, or a group's
`"kinds"` by name), whether or not the stranger has dealt with the last lot: that's
his problem. Each map names its **entries**, where the roads and trails cross its
edge (San Miguel: the east and west roads, the north, north-east and south trails),
and its **centre**. The men come in on foot, one road after another a man at a time.
They walk in close behind one another, a man every half second off each road. Under
the bandit count a countdown runs to the next wave; 15 s before it, a banner
names the roads ("Men coming in by the east road and the north trail!") and an arrow
marks each (at the road, or at the edge of the screen pointing to it) until the last
of them is in. Arrivals make for the middle of town and spread out about it, wary,
unless there's shooting going on they can hear (within the last 8 s, not too far
from where they come in): then they go straight to it. Those passing as townsfolk
and El Jefe never come marching in; otherwise each is one of the sort already in
town. The town isn't won till the last wave is in and down. The director
(`scripts/director.gd`) runs it apart from the game. "San Miguel (waves)" in the
picker is for trying it: 20 bandits, then 7 or 8 more every 90 s, from two
roads at a time. `tests/test_waves.gd` runs a quick version in the test yard.

**The hanging** (San Miguel: a level's `"hanging"`, run by `scripts/hanging.gd`).
The gang has an innocent man up on the plaza's gallows (`captive`: bareheaded,
they've had his hat; crossed bandoliers, so he could be one of the revolution's or a
friend of the stranger's; his hands tied behind his back; noosed, on the trap) and
they drop him at noon: 300 s in, counted down under the bandit count
("HANGING AT NOON 4:12"; a banner says so as he rides in). The hangman (his own
type and body, `hangman`: a black hood over his head with holes for the eyes, a dark
shirt, a Colt; one more of the gang, 26) keeps to the foot of the gallows steps till it's
done: no running to the fight, no ducking from it (a fright that would send him to
cover leaves him where he is), nobody sends him to rescue a man or scout. Nine
seconds without a sight of the stranger and he's out of the fight again, back to
watching, warier (else the town would never go quiet: the mayor would keep his head
down for good). And when the hanging's over, one way or another, he's still the
gallows' man: he fights the stranger while he can see him but never from more than
140 px off his post (`Enemy.LEASH`), backing up to it if he has to; lose the
stranger three seconds, or be sent anywhere (a search, a scout, a holdout), and he
walks back to his place by the steps. The posse goes without him, and he's never
the one sent running to the saloon for the reserve. The alarm doesn't hurry it; only the stranger in the hangman's own sights
does, and then he goes for the lever ("¡Ahora!"): two seconds, and a shot in them
stops it. With the hangman dead nobody drops him, not even at noon, and a banner
says so ("The hangman's dead! Nobody left to drop him."), in case the stranger
didn't see which man fell (the bandido guarding the steps stands beside him). Once the trap
goes (the bell, a hole in the platform, his legs kicking down through it, straining
at the rope round his wrists) he has
seven seconds: a round through the rope (5 px across, from anyone's gun: heights
don't count, so a round lined up on the rope, or on the man before the drop, flies
on over the platform's edge where any other stops) parts it and he's down. The stranger's rounds that find the man himself (on the
trap, before the drop) count as the rope too, and he's loose: the stranger would
never aim at him. A bandit's stray round is another matter. Both are
drawn well up off the trap they stand over, so the cursor on either (or anywhere on
the rope up to the beam) aims at the trap itself, the way it aims at a bandit's
middle when it's on him (`Player.aim_ground`); without that, aiming at the drawn
rope sent every round 13 to 27 px wide of it, into the platform. The
round that parts it is spent. Or the knife: hold E at the platform's edge (within
50 px of the trap) for a second and he's loose, before the drop or after. Loose, he
runs down the steps for the nearest building and stays in it. He can be hit as he
goes (or on the trap: a stray lined up on him), though nobody aims at him. Too late,
and he hangs there, his head fallen forward, turning a little on the rope. The end card: "the condemned man:
saved", "hanged, you failed him" or "shot dead, you failed him" (alive on the trap
with the gang all dead counts as saved). The captive's "bound" pose set
(in `tools/chars.py`: hands behind his back, rope at the wrists; "struggle" for
the kicking, "hang" for after) is his upper body; his legs are the walk cycle for
the kicking. He's lowered through the trap and clipped at the platform (the palette
shader's `clip_y`; `Actor.lift` raises a body off its ground point). Cut loose, he
has his hands back (the "unarmed" set). The bound set is meant to serve a prisoner
tied to a post elsewhere too. `tests/test_hanging.gd` plays the rope shot aimed where it's drawn (from the
west, north and south), the kicking out, the hangman spotting him early, the hangman
stopped and the knife, a bandit's stray round, the stranger's round at the man (the
rope, as far as he's concerned), the hangman pinned under fire and calming
down after, and the hangman kept to the gallows once it's over (`tether`); every other test on the default town sets `no_hanging`.

**The prisoner** (Cruz Verde: a level's `"captive"`, run by `scripts/captive.gd`).
One of the stranger's own (the same `captive` body as San Miguel's condemned man,
hands tied behind him) is tied to a rough post by the well (`pole`, a prop that
stops nothing), a man of the garrison standing over him: the one placed nearest the
level's `"guard"` spot, the plaza's north-south patrol, taken off his rounds for it
(so the five outside are still five). Nothing happens while all is quiet; seeing
the stranger isn't enough to tell them what they're up against. The first shot,
whoever fires it, and the guard puts his gun to the man's head and counts ten
("¡Alto o lo mato!" and the like, every couple of seconds; "THE GUARD: ¡ALTO O LO
MATO! 7" under the wave countdown): he doesn't stir from the pole and doesn't turn
his gun on anyone else while he counts. Dead or down in time, and the man lives
("His guard's down! Cut him loose!"); at ten he shoots him. With two seconds
left the man starts his last words, a line from the song ("Hay que ganar muriendo,
pistoleros"), coming out a few letters at a time, and the shot cuts them off where it
finds him: "Hay que ganar murien—" stays over him a moment as he falls
(`Civilian.last_words`, the one bubble the HUD keeps over a dead man). Drop the man
counting mid-line and he gets to the end of it. Then El General: the
moment he's out of his house, if the man's still tied, he goes straight to the
pole, whatever's flying, and counts it out himself (he's desperate, half his men
outside the walls). Kill the guard with the knife before any shot and there's no
count at all, till the general comes out. The stranger's rounds go past the man
(he'd never aim at him); anyone else's don't. Dynamite going off round him
doesn't trouble him (an old guerrilla, as used to the revolution's battles as the
stranger is): only a blast right on him (12 px, `Captive.BLAST_ON`) kills him, kegs
and crates as well as sticks. And the waves make for
the middle of the fort, so a man still tied when the first one walks in (a minute
after the first shot) is in the crossfire. The level opens with word of him ("Cut
your compañero loose by the well: hold E!"). Hold E beside him (within 40 px,
feet to feet) a second and he's loose (an "E" over his head, faint from a few
strides off, bright once he's in reach, as over the man on the gallows): he runs for the chapel door and stays in. Killed: "They've killed him! Make
the whole fort pay for it." The guard is posted like the hangman (`Enemy.posted`):
tethered to the pole all level, never the posse's, a runner or a rescuer. The end
card: "the prisoner: saved" or "shot dead, you failed him". `tests/test_captive.gd`
plays the quiet, the count to the end, the guard stopped and El General's count, the
knife, the rounds, and the blasts; every other Cruz Verde test sets `no_captive`.

**Cruz Verde** (the second level: the ending of *The Wild Bunch*, and Sollima's and
Corbucci's revolutionary westerns). A garrison's walled town: thick crenellated adobe
walls (x 16..49, y 14..47) with a squat bastion at each corner, a gate wide open
midway along every side and the south and east walls breached, heaps of rubble in
the gaps; too tall to see over, so the gates and breaches are the ways in. Inside, a
whitewashed chapel with its bell wall, the general's two-storey house with its
balcony, the barracks (CUARTEL) with a portal along the front, a cantina, two adobes;
a plaza with a well, the tricolour on its pole, an old bronze cannon, sandbags
inside each gate, wagons, ammunition crates and powder barrels. The plaza's been made
ready for a push through the gates: cantina tables thrown over on their sides round
the well, each top turned to the gate it watches (`upturned_n/s/e/w`: only the top
stops a round, the legs behind it don't). Sandbags and barrels are piled against the
chapel in the north corner, and the fort's stores (`crate_stack`: two crates, a third
on top, a sack) are stacked wherever there was room, so there's little open ground
between the buildings. Both are breakable wood like the crates. And the fort's
powder (`KEG_SPOTS` in `tools/make_cruz_verde.py`): a **powder keg** by each gate and
the east breach, each beside a plain barrel, for the band coming through; three
**crates of dynamite** in among the stores. See "Powder kegs and dynamite crates"
below. Outside, a village of
jacales with chickens and, to the west, a great cemetery after Sad Hill: rings of
crosses, mounds and headstones (low cover) round a circle of stones, and rows of
graves below the west road. It's an **ambush**: the stranger starts outside the
west gate, flat against the wall beside it. The garrison is fifteen, but there was
a party last night after their last victory: only five revolucionarios on the
grounds (a tirador at the north gate, the rest on their rounds or at the breach),
the other ten indoors sleeping it off with the saloon girls (the map's `sleepers`,
each at the door he'll come out of, with "after": seconds). Nobody comes out till the
first shot, whoever fires it; then two who were ready dash out (with whatever
pistol they had on them: their long guns are in the rack, so only El General, whose
coach gun goes where he goes, comes out with more) in about two
seconds, three more at twelve, three at twenty and the last two (El General among
them) at thirty, spread out so that a small place doesn't overrun him all at once: four saloon girls, a soldadera, a drunk and revolucionarios, all making for
the fight. Kill the five outside without a shot and the quiet is noticed in the end:
out they come, wary, to look. The title counts all fifteen; the bandit count only
those he can see. The waves count from that first shot (`"waves_from": "first_shot"`),
so none walks past him while he's still creeping about. Seven waves, 64 men (79 of
the gang in all with the garrison): the first a minute after that shot (time enough
to clear the fort), then every half minute a band of six to ten comes down one or two
of the five roads (west, east, north, south, and through the cemetery), close
together (a man every half second), so a gun at the gate can't pick off a whole band
before the rest are in among the walls. After the fifth (three minutes in) there's a
lull of 75 s, and word of it ("The enemy is rallying their troops outside the
fort!", 20 s after the fifth: `"rally"` on the wave): time to bandage and scavenge.
Then the last two, thirteen and twelve, half a minute apart: the scrapings, badly
armed (a wave's `"arms"`, the "rabble" set in levels.json: Navies and single-shot
horse pistols, some with a brace of them; he's no doubt badly hurt by then), a
coronel at their head with his own Colt. A win is meant to be a narrow survival with
the dead stacked everywhere. He rides in with a stick of dynamite here (the level's
`"dynamite"`), for the choke points at the gates; he can carry no more than one. No more than 40 of the gang are about at once
(the frame time: past that the rest wait out on the road for room). There's no posse
here at all (`"posse": false` in the map): it's a fort, not a town to get lost in,
and the last of them just hold it. The waves have their own mix (`"wave_kinds"` in the map, by weight): mostly
revolucionarios, many of them soldaderas, a few tiradores and sargentos. Cruz Verde's padre is brave (`"brave"` in his placement): he goes to the dead
with the shooting still going on. Saloon girls (and one with a
derringer), peons, women and the padre about the place; no undertaker, gunsmith or
mayor. It falls back to the chapel, the general's house, the barracks or the cantina.
For now the garrison are the usual bandit types; the revolutionaries' own look and
their general come next. `tests/test_cruz_verde.gd` checks the map (nobody sees the
start, the ways through every gate and breach, a way in from every road), the ambush
(nothing stirs while he waits; the first shot brings them out, ready and sleepy, and
starts the waves) and has the autopilot hold out a few minutes against the waves;
`tests/test_ambush.gd` does it with the knife, and the quiet brings them out.

**Paso Esperanza** (the third level, in the making: a freight the revolution has
stopped out in the scrub, after *A Bullet for the General* and *Compañeros*; its
name after Esperanza, the town the train's bound for in Corbucci's *Navajo Joe*).
No army there yet, only the revolution carrying off the train's arms: walk it to see how it lies
(`tools/make_train.py`, `data/train.json`). The line runs down the middle (x 30,
top right to bottom left on screen: the ground bake draws its dark cinder ballast,
ties and rails from the map's `"rails"`), torn up south of the engine, where she
went over: a 4-4-0 on her side west of the line, wheels in the air towards the
fight, the tender dragged off the rails and leaning behind her. North of them the
cars: a boxcar, the guards' car (burnt out round them to the floor and ribs, still
smoking: low cover, seen over), another boxcar, a flatcar of cases under a canvas.
The boxcars' doors are run open both sides, rifles stacked inside, a doorstep on
each side for whoever carries them out; the gaps at the couplings are ways through.

There's been a fight all round it. Along the cars' east side, where the guards held
out: their wagon over on its side (`wagon_over`, breakable), mess tables thrown
down, sacks (`sacks`), barrels and crates shot through. Off the front of the train,
south of the engine: cases and barrels thrown when she went over, twisted rails and
loose ties, the section gang's handcar knocked off the line (`handcar`).

The revolution's side is the west: cases piled by the doors, and a heap of them
already out by the engine's cab (where the stranger will see them carried off),
the wagon trail they came in on, three carretas waiting along the west and north
edges, mules in harness facing out. The army's side is the east and south. A road
comes in from the east edge straight at the breastwork's flank, with the
revolution's ambush positions along it (sandbags where they lay waiting for the
train), rocks big and small (`rock_c` is the big one), a wagon over, cases: cover
every few tiles, for an army to come down it from one to the next. The south is the
same, thinner. Beyond, open scrub, rocks, cactus and agave.

The stranger holds a breastwork in the angle between the engine and the line
south: railroad ties stacked crib-fashion, sandbags and cases of rifles, a front
facing south and a flank facing east, the corner where they meet kept for the
Colt-Browning (the map's `"mg"`, empty for now), open at the back to the north. The
front runs on west, under the engine's nose and across the torn-up line, to a pocket
on the revolution's side looking up the west of the train at the cargo, for those
who get past the train after it; and a post of crates and sandbags by the tender
looks north up the cars' east side. Three sticks of dynamite lie about it (the
map's `"pickups"`: one on him at a time, as ever), one in the west pocket. The
telegraph runs down the west side, cut either side of the pole they felled. Once the
gun's done, there's somewhere to fall back to: the corner where the tender meets the
engine's cab on the train's far side, bags to its north and west (the way the
flankers come), the cars at his back and the engine on his flank; from the gun it's
along the back of the front, under the engine's nose and up her far flank, the
engine between him and the army all the way. The
train's dead lie where they fell (the map's `"dead"`, `scripts/corpse.gd`: a body
template and palette, drawn from the last frame of a death, a pool under it;
scenery, nothing to hit, haul or bury), twenty of them, so it reads as a battlefield:
the engineer and his fireman by the cab; the federal escort (soldados, levas, a cabo,
their teniente) along the cars where they made their stand and a few run out east
into the scrub; and the revolution's own at their ambush positions on the east road.
The soldiers wear their type's colours from `data/enemies.json` (`_body` in
`tools/make_train.py`), so the dead and the army coming over them are one army. Smoke from the burnt car and steam from the boiler go
up all level (`"smoke"`, `scripts/smoulder.gd`, its own dice). With no gang on the
map, nothing ends it but the cargo (below). `tests/test_train.gd` checks the pieces,
the dead, the sticks, the smoke, the ways round (to the west pocket, the tender post
and down the east road too) and that the empty count doesn't end it.

**The cargo** (a level's `"cargo"`: `loads` and `spare`; the map's `"cargo"`: the
piles and the wagons; run by `scripts/cargo.gd`). Five of the revolution's carriers (and a sixth for the machine guns, below)
(Civilian, `"role": "carrier"`, unarmed, in the revolucionarios' and soldaderas'
clothes) take the train's arms to the wagons a load at a trip: three on cases
(`"load": "case"`: a case held across the chest, a little slower), two on loose
rifles (`"rifles"`: an armful, as the gunsmith gathers guns in San Miguel). Each
goes to the nearest pile of his kind that isn't everybody's (stacked cases by the
doors and the cab, the boxcars' own west doors, rifles heaped where cases broke
and the guards' own by their car), bends to it, and takes a load to whichever wagon
is loading: far one first, the last by the wagon trail. A case and an armful count
the same, one load; 40 in all, the wagons holding 13, 13 and 14. An emptied pile is
gone from the map. A full wagon drives off west under its own dust (slid, the mules
unmoving: it's at the edge), out of everyone's way at once. The count is under the
bandit count ("LOADED 12 / 40  CARRIERS 5").

There's a fight on the other side of the train the whole time, so only a round
within 90 px of a carrier (or a man dropping that close) sends him to cover: the
nearest boxcar door, load and all; four seconds without another and he's back at
it. Shot down with a load, he drops it where he falls, a pile of one for the next
man. Two replacements (`spare`) come up from the wagons, eight seconds after a man
falls; with them gone too and every carrier dead, it's lost: "NOBODY LEFT TO CARRY
THEM". Their comandante (`"role": "leader"`, a coronel's body in a field coat)
stands by the heap at the cab waving them on and takes cover for nobody; shoot
him and they carry on just the same. His first call, five seconds in, is his own
("¡Estudiantes, rebeldes, bandoleros!", his `"call"` shout, out of Morricone's
"Vamos a matar, compañeros" for Corbucci's *Compañeros*), and it's among his urging
after ("¡Ándale, muchachos!" and the rest). The stranger has his say first, two and
a half seconds in: "Pintamos de rojo sol y cielo", from the same song (a level's
`"line"`, said in a speech bubble over his head: `Player.say`, the same bubble the
bandits and townsfolk have; he's not a talker, and says nothing else yet). At Cruz
Verde his line, outside the west gate before the ambush, is the song's title: "Vamos a
matar, compañeros".

With every load in, the carriers climb onto the last wagon, the comandante calls
"¡Vámonos, muchachos!", and an arrow marks the wagon for the stranger. He gets to
it and he's on (out of sight) and away, and the level's won; the end card counts
the loads away and the carriers lost. Killing every one of the gang doesn't win it
here. With nobody shooting, the 40 loads take about two and a half minutes.
`tests/test_cargo.gd` plays the trips, the comandante shot, a fright close by and
none further off, a load dropped and a replacement, a wagon leaving, the run to
the wagon, and the loss.

**The army** (see "The federal army" under Bandit types). The count names them
("FEDERALES 9": the map's `"foe_count"`, and `"foes"` for the banners). A first
company comes 25 s in, by the clock; after that each comes with the loading (a
wave's `"loads"`: at 6, 12, 18, 24, 30 and 35 loads in, and a last push at 40, while
the stranger runs for the wagon), word of it two loads before: the quicker the arms
go, the sooner the army's on them. They come by the east road, the north-east, the
east scrub (the east edge, south of the road), the south-east (the map's corner,
straight at the gun on the diagonal, past a few low things far out), the south and up
the line, most companies split three ways at once, so the same men come spread
wider, mostly levas and soldados (the map's
`"wave_kinds"`), a teniente and the colours with some companies by name, and the
capitán with the second-to-last. About 130 in all (the first try, 90, was too few to
push), no more than 40 about at once: the rest come on down the road as there's room. They come for the train, not
for the stranger (see "The federal army": the assault).

**The Colt-Browning** (the map's `"mg"`, `scripts/mgun.gd`). An M1895, the "potato
digger", on a low tripod in the corner of the breastwork, facing the army's way: a
nest of its own sandbags tight round it, two layers deep to the south and east and
one to the west, open only to the north, the way in (`nest_x`, `nest_y`: breakable
but heavy, 120 a piece, so forty rifle rounds; at first they were 30, and a company
had them gone in seconds). The front's timbers are cleared out of its way, and
nothing of the ambush's is left in close to the south of it (a breastwork of
sandbags six tiles out took the gun's rounds meant for the men coming up from
there; the big boulder on the east road, seven tiles out, hid a wedge of the road
from it, and is further down the road now; the crates out there it just shoots
through). The army's spots are all in front of it now (they used to include the
tender's, behind it, and from there they shot him in the back). The stranger gets on it with E
from his place behind it ("[E] the Colt-Browning", and how many in the belt), and
off again with E or a step any way; on it he can't move, and the gun goes where
the cursor is as far as it can: half a circle each way of straight out (the map's
south-east), swinging no faster than 1.8 rad/s. Fire held: seven or eight rounds a
second from the one belt of 250 (a strip of brass in the gun panel, running out),
damage 3, each through a man and on into the next two, 760 px. Its spread is its own (1.4°, off the tripod): a belt through it puts none of the bloom that rapid fire from his own guns does on his hands, so off it his Winchester and Colt shoot as true as ever. Its rounds go over
low cover within 64 px of him (a man's go over 26), which takes in the whole nest
and nothing else of ours: the breastwork was laid out round that, and checked by
tracing its arc. Then it's silent ("The belt's spent"), and the federales can't
use it either. He's off it if he goes down. A stick of dynamite landing in reach of
him on the gun (a rural's, for the nest's the place he keeps killing from) brings a
shout ("¡Dinamita! Off the gun, compañero!"): bolted to it, he'd never see it for
the smoke, and it's that or the blast. Firing it makes the breastwork a place
the army has seen him firing from, and a rural with a stick knows what to do with
that. Its own dice (`MGun.rng`).

The carriers also take three loose machine guns off the train (`mgun_pile` by the
second boxcar, the tripods left behind): a sixth carrier (`cargador_mg`, `"load":
"mg"`, `"then": "case"`), the gun up on his right shoulder and its belt over his
left, takes them first, each worth three loads (`Cargo.WORTH`), and then goes on to
the cases. Shot with one, he drops it for the next man. `tests/test_mgun.gd` plays
the gun (getting on and off, the arc and the traverse, the rate, over the nest and
through a file of men, the belt spent) and the machine guns carried off.

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Aim (hovering over a bandit aims at him) |
| LMB | Fire |
| RMB | Revolver: fan the hammer (hold) · Coach gun: fire both barrels |
| C / Ctrl | Toggle crouch |
| R | Reload (press fire to stop a partial reload) |
| 1 / 2 / 3, wheel | Revolver / shotgun / rifle slot (the ones he has) |
| F | Swap the gun in that slot for the one at his feet |
| E | Knife: a silent takedown from behind, or a rush |
| Enter | Restart after win or loss |
| Esc | Quit |

## Hero

Long dusty duster, flat-brimmed wide hat, cigarillo, gunbelt and a shell
bandolier. 6 HP: revolver and rifle hits deal 2, buckshot pellets deal 1, so
he survives two clean hits. No health pickups.

Crouching: half speed, silent footsteps, tighter spread and a smaller visual
profile (see Stealth).

**Bandages** (B). He rides in with one, and can pick more up: a dead bandit now and
then leaves the one he never used (one in five), lying by him; walk over it to take it.
One at a time: with a bandage on him, the next stays lying there till he's used his. Down on one knee, gun set aside, winding it round: ten seconds, and only
crouched and still. Moving, firing, reloading, the knife or a hit breaks it off
(he keeps the bandage, not the time). Done, it gives back two bars (never more than
he started with), ends a limp and stops the bleeding. The long wait is the point:
the gang's memory of where he fought fades, they drift into searching, and the town
starts going about its business again. A HUD bar shows the progress, and the
tearing cloth can be heard close by.

**The last stand** (`tests/test_laststand.gd`). Once a level, the shot that would
kill him puts him down instead (not the heart of a blast, nor a scattergun at arm's
length): the moment slows, a sting, and the colour starts going out of it. He lies
propped on an elbow, boots towards whoever dropped him, in the same poses as the
gang's last gasp, with one bar left. He can't move, but he can drag himself round
on his elbow to face any way, boots and all (2.5 rad/s: a man behind him takes over
a second to face; flanked still costs him). It's his Colt if he rode in with one; if not, a revolver
comes out of his boot (a Colt, a Schofield or a Navy, loaded). Everything takes half as long again
one-handed in the dirt (no fanning), and lying flat he's a small target: his hurtbox
lies along him, and he counts as crouched, so low cover stops everything. A heartbeat
slows and the screen greys as he bleeds; "BLEEDING OUT" drains in 25 s. The only way
up is a bandage (B, 5 s lying flat with the gun down; fire breaks it off): up he gets
with one bar, a limp and the gun he had. Or nerve: drop three of them from the dirt
(killed or downed, his rounds or a keg he set off; counted by three notches by the
bleed bar) and he gets up the same, but still bleeding, his bandage kept for later.
Anyone who sees him rise is shaken (+0.5), those walking up to finish him stop, and
the nearest says so ("¡No se muere!"); it has its own dice (`rise_rng`). If the third
was the last of the gang, it's simply the win. With none, he shoots till he bleeds out or
they finish him; and if the last of them falls first, it's a win ("FROM THE DIRT").
The gang calls it ("¡Ya cayó!"), and the bold ones in sight walk up to finish him
(`"finish"` per type: El Jefe, El General and the gunslinger always, the hillbilly,
coronel and pistolero often; no more than two at once, rechecked every 3 s): no
running, no cover, then a round into him from close. That's when a man lying there
with a pistol is most use: dropping one of them, or an officer, from the dirt shakes
the men round him, and they're the likeliest three to get him up. The end card
says "(3 from the dirt, and up again)".

**Blood trails**. Any wounded man bleeds till he's bandaged: a drop in the dirt
every few steps, and now and then where he stands. A bandit who comes across
fresh drops of the stranger's blood (under 45 s old, in view within ~170 px)
follows them ("Blood... he's hit."), drop by drop, reading the ground (once on the
trail he picks up the next drop anywhere within ~70 px); in a fight it tells them
where he went to ground. The stranger can follow a wounded bandit's trail the same
way, by eye.

**The knife** (E). A small blade over a bandit's head shows who it would go for (the
one under the cursor if he's in reach, else the nearest; never through a wall):
- *Pale: a silent takedown.* Within ~22 px of a man who isn't on to him (no fight,
  not looking at him): the stranger steps in, a hand over his mouth, and lets him
  down quietly. The sound carries ~40 px; anyone who sees it reacts as to any
  killing in front of him.
- *Red: a rush.* Within ~58 px of a man who is aware: he lunges (fast, ~0.4 s). As
  he gets there it's decided by what the man is doing. A loaded gun, ready, in hand
  and facing him, not reeling, cowering or fleeing: he fires point-blank (a ready
  coach gun is the end of him) and the stranger is left reeling right in front of
  him. Otherwise (mid-reload, as with a bandido's Navy, empty, turned away, staggered)
  the knife goes in: a yell heard ~160 px off, and a cut of 3 (El Jefe, with 4 HP,
  takes it and reels). Then 0.7 s before the next (1.2 s after being shot).
`tests/test_knife.gd` covers both, the witness, and the ready, reloading, tough
and out-of-reach cases.

**Moving the dead** (hold E by a body). Only the dead: a downed man is still alive
and would call out, so the knife comes first. A tap of E is the knife; held a third
of a second by a body, the stranger takes him by the collar (the guns put away, the
rescuers' "haul" pose) and hauls him along behind at 40% of a walk. Letting go of E,
reaching for a gun, crouching, bandaging or being hit drops him; no shot goes off
with his hands full. There are no special hiding places: round a corner, out of the
bandits' sight, is hidden. But it leaves evidence. The pool stays where the man
fell, and a bandit who sees a pool with nobody in it gets suspicious and goes to
look (not the full alarm a body brings); the body leaves a smear the bandits read
as the stranger's own trail and follow (the sweepers clean it up later). Townsfolk
who see him at it mostly (70%) cry murder ("¡Asesino!"), which bandits within ~340
px of him hear and come to see; the rest, no friends of the gang, slip off indoors
without a word. The undertaker won't claim a body the stranger has hold of.
`tests/test_drag.gd`.

**Loadout and loot.** After the title card the stranger chooses his irons: one gun
a slot, or none, at least one in all. Three cards, sidearm, shotgun and rifle, each
listing what goes in it (Colt, Schofield, Navy or horse pistol; coach gun, sawn-off, Champion or escopeta;
Winchester, Spencer, Springfield or cut-down Rolling Block) with a line on what the chosen one is like. 1 2 3
or a click on a card goes on through its guns and then none; a click on a gun's
name takes it, or puts it back. Enter or "ride in". The choice is kept across
restarts. He rides in with those and their cartridges (`Player.RESERVE`; guns
sharing powder and ball add theirs to the one belt). Cartridges for a gun he hasn't
got still go in his belt, ready for when he finds one. Three small slots over the
gun panel show which he has (the one in hand outlined), and a line there says what
he picked up. `tests/test_loadout.gd` covers the screen, the switching, and picking
guns up.

**Points.** Each choice costs points, out of the level's `budget` in
`data/levels.json` (12 where none is named, for now enough for everything). A gun's
price is its `points` in `Weapon.DATA`, by how good it is, not by its slot: junk is
free (horse pistol, escopeta, cut-down Rolling Block), the poor or one-job guns 1 (Navy, Champion,
Springfield), the solid ones 2 (Colt and Schofield alike: as strong, each with its
own faults; sawn-off, Spencer), the coach gun 3 and the Winchester, the best gun in
the game, 4. Kit is bought on the same screen (`Player.KIT`): a bandage for 1 (B,
or the box left of "ride in") and a stick of dynamite for 2 (G, the right box), in
every level. What he doesn't buy he hasn't: no free bandage. Each
gun line shows its price, greyed when he can't afford it with what else he's taken;
1 2 3 pass those by, and a click on one gets a dry click. A choice kept from a
richer level gives back its dearest thing first (kit before a gun of the same price)
until it fits. Guns taken off the dead are free. The tests that skip the screen
keep the level's own kit (a bandage, the level's sticks). `tests/test_budget.gd`.

**Taking up the dead's guns.** Three slots, one gun in each, by role, so the keys
never change meaning: **1** a revolver or pistol (Colt, Schofield, Navy, horse pistol), **2** a
shotgun (coach gun, sawn-off, Champion, escopeta), **3** a rifle (Winchester, Spencer, Springfield, cut-down Rolling Block).
`Player.SLOT` lists what he can carry; the derringer, Sharps and howdah
still stay where they lie, and the gunsmith may get to them first.
- A gun for an **empty slot** is his for walking over it.
- One for a **slot he's filled** is a swap he has to mean: standing over it, it
  glints, and a line over the gun panel names it, what's in it and what he'd give
  for it ("[F] SPENCER CARBINE (5 loaded) for your WINCHESTER 1866"), there being no
  telling one gun from another in a heap of the dead. **F** swaps: the new one in
  his hand, his own left lying where the other lay, loaded as it was. He can take it
  back the same way.
- A dead man's gun is **loaded as he left it** (what he'd fired is fired), so a dry
  Colt can be dropped for a loaded Navy off the nearest body and the fight goes on
  without a reload.
- The dead man's cartridges, lying by his gun, come with it (his bandolier): a few
  rounds, never a full belt.
- **Ammo is by kind, on one belt**: .45 Colt, shotgun shells (coach gun, sawn-off and Champion), .44 rimfire, Spencer
  rimfire, the Sharps' big .50 (the cut-down Rolling Block's too: few men drop them, so
  he lives on what he rode in with and what poachers leave) (the Schofield takes the Colt's .45), and powder and ball for the cap-and-ball Navy and the muzzle-loaders
  (horse pistol, escopeta, Springfield), so those share. Every dead man drops the
  rounds for his gun, whether the stranger has one or not.
The revolution's guns are worse than his own; they earn a slot when his are dry.
`tests/test_pickups.gd`.

## Weapons (period-authentic)

### Colt Single Action Army (1873), .45 Colt — 6 rounds
- Single action: the hammer is thumbed back between shots (~0.35 s).
- Fanning (hold RMB): fast, very inaccurate fire.
- Reloading, per chamber: hammer at half-cock and loading gate open, then for
  each chamber the ejector rod pushes out the spent case (0.36 s) and a fresh round
  goes in (0.5 s): about 6 s for all six. Slow, and it can be stopped at any point.
  Closing the gate cocks it again.
- Damage 2 · fast bullet · medium range.

### Smith & Wesson Schofield, .45 — 6 rounds
The Colt's rival, a top-break: an alternative for the sidearm slot, and in about a
third of the gang's hands where they'd have a Colt (`Enemy.SCHOFIELD`, a type's
`"schofield"` chance; its own dice, `schofield_rng`).
- Reloading: unlatched, the barrel swings down and the extractor throws out **all
  six at once, spent and live alike**; the live ones are lost in the dirt. Then six
  go in quickly, with no turning the cylinder to each. A full six in about 3.5 s
  (the Colt: about 6 s), but no topping up a round or two in a hurry: two spent
  and four live costs the four, and takes as long as six (the Colt: about 2.4 s).
- The hump-backed grip sits oddly in most hands: a little wilder than the Colt
  (spread 3.0 against 2.2). No fanning; that's the Colt's alone.
- Takes the Colt's .45 rounds, off the same belt.
- Damage 2 · fast bullet · medium range.

### Coach gun — side-by-side 10-gauge double, external hammers, two triggers
- LMB fires one barrel (right, then left). RMB fires both barrels together.
- 9 buckshot pellets per barrel with a wide spread. Deadly up close, weak at range.
- Reloading: break open, pull spent shells, load two shells, close (cocks the hammers).
- Pellet damage 1 · short range · loudest weapon.

### Johnson & Bye Champion (1879) — single-barrel break-open shotgun, 12-gauge
The cheap single gun every hardware store sold: the low end of the gang carries one
slung beside the sidearm, and the stranger can take one up for his shotgun slot.
- One long, choked barrel: the shot goes further and holds tighter than the coach
  gun's (range 240 against 175, spread 5.5 against 9), the same nine pellets.
- One shot, then the side lever snaps it open, the shell's pulled, a fresh one in,
  shut and the hammer back: about 1.3 s (the coach gun: about 2.3 s for two; the
  escopeta: about 7.4 s with the ramrod).
- Weaker in a fast fight than the coach gun: one shot, never both barrels at once.
- Takes the coach gun's shells, off the same belt.
- In the gang's hands it's one shot from a little further off, then more often than
  not it's thrown down for the revolver (`draw_sidearm` 0.8): fire once, ditch it,
  go to the pistol. A type's `"champion"` is the chance a man who would carry only a
  sidearm has one slung as well (cowboy 0.25, bandido 0.3, drunkard 0.2,
  revolucionario 0.25, soldadera 0.2), on its own dice (`Enemy.champion_rng`), so the
  rest of a seeded fight stays as it was. Never a man caught indoors
  (`pistols_only`), nor one passing as townsfolk. A wave's arms option can carry its
  own chance: the rabble's is 0.12, rarer than their Navies and horse pistols.
  `tests/test_champion.gd`.

### Remington Rolling Block carbine, cut down — single shot, on the Sharps' .50 rounds
The rifle slot's junk gun, free on the loadout screen: a carbine somebody took a saw
to, the stock cut back to a pistol grip and the barrel short of the fore-end, so it
rides under a poncho. The spaghetti westerns' own: in Corbucci's *The Great Silence*,
*Compañeros* and *Minnesota Clay*, and in a kid's hands in Leone's *Duck, You Sucker!*.
- A rifle's round still: damage 2 (no pierce: what's left of the barrel doesn't
  drive it through).
- But short and wild: range 320 (the Winchester 620), spread 2.6 (0.6): nothing
  left to aim it with, and little past pistol range.
- The quickest single-shot to load: thumb the hammer back, roll the block, a round
  in, close: about 1.2 s (the Sharps about 1.7 s, the Springfield about 7 s).
- Takes the Sharps' cartridges, off the same belt: 10 to ride in with; dead
  poachers drop four (on no dice: they fall where he lies, so seeded fights stay as
  they were).
- In the gang's hands it's a crafty man's hidden gun, rarer than the Champion: a
  type's `"rollingblock"` is the chance a man who'd carry only a sidearm has one as
  well (pistolero 0.12, under the poncho; revolucionario 0.06, after the Champion's
  roll), on its own dice (`Enemy.rollingblock_rng`, seed 41). One shot from the edge
  of pistol range, then likely the revolver (`draw_sidearm` 0.7). Never a man out
  of a door, nor (yet) one passing as townsfolk. `tests/test_rollingblock.gd`.

### Remington Rolling Block, the full rifle — single shot, on the Sharps' rounds (for now)

The federal army's rifle, as Mexico bought it: a long barrel in a fore-end banded
nearly to the muzzle, the full stock, the block that rolls back under the thumb.
One round at a time but quickly (open, out, in, shut in about 1.4 s), as far as the
Springfield (680) and truer (spread 0.6), damage 3, through one man into the next.
Soldados and cabos carry it; the stranger takes one up off the dead (slot 3,
"REMINGTON ROLLING BLOCK"; 2 points on the loadout card, 12 rounds to ride in with).

### Winchester Model 1866 "Yellow Boy" carbine, .44 Henry rimfire — 13 rounds
- Lever worked between shots (~0.45 s).
- Loaded one round at a time through the side gate on the brass receiver,
  and it can be stopped partway.
- Damage 2 · very fast bullet · long range · accurate.

Reserve ammo is limited. Dead bandits drop cartridges for the weapon they
carried, which you collect by walking over them.

## Stealth and enemy AI

- Each bandit has a visible **vision cone** in two bands: the **near band**
  spots you even when crouched, the **far band** only spots you standing.
- Walls block sight completely. Low cover (crates, barrels, wagons, troughs,
  coffins) blocks sight only while you crouch behind it, and always stops bullets.
- Being seen fills a suspicion meter (faster when closer). A **?** means
  suspicious, **!** means alerted.
- **Noise**: gunshots (loud, per weapon) and standing footsteps (very short range).
- States: **Patrol / Guard** → **Investigate** (noise or a glimpse, look around,
  give up) → **Combat** → **Search** (last known position) → back to a wary patrol.
- In combat bandits shoot with a reaction delay and aim error, keep their
  distance per weapon, and **run to cover to reload** — that is your window.
  An alerted bandit shouts and draws in nearby gang members.
- Each bandit has a personality: his own reflexes (reaction times vary about
  threefold between bandits) and nerve. On spotting the stranger he sometimes stops
  to point him out ("¡Allí está!").
- **Reactions** (the cinematic beats). Rounds passing within ~55 px, dirt kicked up
  within ~70 px, a wound, or a comrade dropping within ~180 px make a bandit react,
  each after his own short delay so a group never reacts in unison:
  - *point* and shout ("¡Allí está!"), held 1.5–5 s;
  - *flinch* with arms up, 1.2–2 s, often followed by backing off or dashing;
  - *cower* with hands on the hat for 2.5–4.5 s, then hide or flee;
  - *back off* out of the line of fire, gun up but not shooting, 2–3.5 s;
  - *dash* for cover and crouch there 2–4 s;
  - *flee* for 8–12 s, then catch his breath crouched out of sight.
  Death of a comrade always triggers a reaction from those nearby who see him fall.
  Wounded bandits stagger for almost a second.
- **Fear is local**: a round or a strike only frightens a bandit with no wall
  between him and it; a comrade's death behind a building only tells the others
  where the fight is. Gunfire he hears but can't see rattles him only if it's
  right on top of him (~75 px) or in view within ~300 px, checked again when his
  reaction is due, since he may have moved on by then. Bandits further off come
  to the fight without stopping for every shot. `tests/test_locality.gd` has the
  hero shoot it out on main street and checks nobody takes fright at a fight he
  can't see, no bandit fires into a wall, and at least half the bandits from far
  off reach the fight.
- **Morale**: every scare, wound and fallen comrade shakes a bandit. Fear is his
  nerve minus how shaken he is, so as the fight goes badly the gang breaks: more
  cowering, more fleeing. `tests/test_reactions.gd` checks reaction hold times and
  that a death always draws reactions.
- **Firefight**: each bandit takes a fighting position, preferring cover that hides
  him crouched but lets him shoot standing (barrels, crates, wagons, corners), not
  taken by a comrade. Behind cover he ducks, pops up, aims, fires and ducks again.
  He takes a moment to aim before each shot and often sidesteps instead of
  advancing. **He shoots back unless pinned**: a bandit who can see the stranger
  and hasn't fired for ~1.6 s stops what he's doing and fires; only rounds landing
  near him (pinned for 2.5 s) keep him ducking long. It's on the player to pin
  them down.
- **Hunting and flanking**: when the stranger slips out of sight, bandits head for
  where he was last seen. The first goes straight there. Any bandit whose comrades
  from nearby are already heading in the same way may (by his type's `flank`
  chance: Red Scarves 0.8, most 0.6, El Jefe 0.4, the poacher 0.3, the drunkard
  0.1) go round instead: the pathfinder steers clear of the routes already taken
  and he comes in from another side, ending just past the spot to cut off the
  escape ("¡Por atrás!", "Cut him off!"). Only real flanks count: from a clearly
  different side and no more than ~1.8x the straight distance.
  `tests/test_flank.gd` checks it (`NO_FLANK=1` runs the control: about half the
  groups go single file without flanking, about a quarter with it).
- **The gang's alarm**: a fight on one side of town doesn't go unnoticed on the
  other, but nobody there knows where the stranger is. Sustained gunfire (each of
  his shots 1, theirs 0.3, dynamite 6), every man downed or killed (5) and news
  brought by a survivor (8) build up a gang-wide alarm (it drains a little only
  after 30 s of quiet). The men out of the fight (over ~350 px from where he was
  last seen or heard) answer by stages:
  - *Uneasy* (12): they stop their rounds where they are and stand facing the
    trouble, wary (wider, longer eyes), muttering "¿Qué pasa allá?". Still at their
    posts: sneaking up gets harder, not impossible.
  - *Sending men* (35): each post of two or more sends a pair to see (the two
    nearest the fight), and again every 30 s while it lasts; a man alone holds his
    post. A scout cut down is a scout who never comes back: +10 more.
  - *Falling back* (a third of the gang down): the far men abandon their posts for
    the holdout furthest from the fight (cantina, bank, church or stable, from
    `town.json`), "¡Al cantina, muchachos!", run there and dig in behind its cover,
    facing the way he'll come. The stranger then has a held position to crack.
  News travels with people: a man who runs from the fight runs to his comrades if
  there are any not back towards the stranger, and when he reaches them ("He's
  killing everyone!") they're on edge and the alarm goes up. Cutting him down keeps
  the far side in the dark. `tests/test_alarm.gd` covers the news, a few shots
  stirring nobody, the far side going uneasy, a pair sent and heading for the fight,
  a lost scout, and the fall back to the right holdout.
- **The posse**: once seven or fewer bandits are left (a band of seven: more than
  one man's six shots), the survivors band together
  instead of waiting at their posts at the far end of town. The steadiest man (by
  rank, then whoever is nearest the others) calls "To me, boys!" and they gather
  on him; anyone mid-fight or mid-search finishes first and then falls in. They set
  off when all are within ~70 px of him, or after 30 s with whoever has come. The
  leader walks from street to street, always to the nearest of the spots they've
  seen least lately, so the whole town gets swept rather than the same streets
  twice; he pauses 1.5–3 s at each and waits up to 6 s for stragglers, who run
  for him first when far behind. In an alley too tight for the formation the
  others fall in behind him single file. The others keep their
  slots behind and beside him, each watching his own side (left, right, the rear)
  whenever they stop. A fight breaks the formation as usual, and once the search
  that follows is over each man falls back in on the leader. If the leader dies, the
  next man takes over. `tests/test_posse.gd` checks they gather, stay together,
  cover most of the town and re-form after a fight.
- **Cover that wears**: crates, coffins, barrels, water troughs and wagons stop
  rounds, but not for long: every round that hits one is damage to it (crate 9,
  coffin 8, barrel 12, trough 21, wagon 33; a Colt round 2, each pellet 1, so a crate
  takes five Colt rounds, or a coach gun blast that lands square plus a little more). Below about half it looks shot up (holes,
  raw splinters), and at nothing it's a heap of boards: no longer cover, nobody's
  way blocked, the cover points gone. A holed trough leaks: a dark puddle spreads
  out in front of it. Strong rounds go through thin wood, one point of damage
  weaker for it: a Winchester through a crate or coffin, a Sharps through a barrel
  too; troughs and wagons stop everything. Each hit cracks, and the last one brings
  it down with a clatter.
- **Things that break**: gunfire leaves its mark on more than the cover. Window
  panes (the glazed ones on the wooden buildings; the adobes' openings have none)
  shatter when a round strikes them at the height it's flying, a dark hole with
  jagged shards left in the frame and glass glittering on the porch; shut
  shutters take the round instead, and hide a broken pane when they close over it.
  A lantern hangs out front of every porch, lit; shot, the glass goes and it
  dangles askew. Tables of bottles stand on the saloon, hotel and cantina porches
  (the bottles go first, whisky in the dirt, then the table), with chairs that go
  over and then to pieces; clay water jars (ollas) by the adobe doors burst in a
  wet patch of shards. None of it is cover or in anyone's way: rounds break it and
  fly on (a separate collision layer only bullets see). Each break has its sound
  (glass, crockery, splintering wood). Dynamite clears everything near it, windows
  included, and it all goes on the mayor's list. Panes and lanterns are baked per
  building like the shutters (rendered with the building around them, keeping only
  what they change). `tests/test_fragile.gd` checks there's plenty about town and
  none of it blocks anything, each kind breaks step by step, a pane breaks only
  when hit at its height and not behind shut shutters, a blast clears the lot, and
  the mayor hears about it.
- **Signs, washing and bullet holes** (more of the same: no cover, but a fight
  leaves its mark, whoever's shooting). A painted board hangs on chains from an
  iron arm out front of most porches (WHISKY, ROOMS, BATHS, WANTED, COFFINS...): a
  round sets it swinging away from the shot, a damped pendulum over seven baked
  angles, settling in a couple of seconds; the third parts a chain and it hangs
  down from one corner till the carpenter rehangs it. Washing is pegged out on
  lines in the back yards and across three alleys (sheets, shirts, red long johns,
  towels, a skirt), flapping now and then in a gust: a round holes it and it
  flaps hard, the third tears it off the line into the dirt, and the hen women peg
  it out again once it's quiet. Rounds into a building's walls leave holes there
  for good (on the faces you can see; up to 150 a building, the oldest going),
  drawn with the building so they sort and fade with it: raw wood round them, or
  chipped plaster on adobe (the cantina, the adobe houses and everything in Cruz
  Verde: its walls, gates and buildings; `ADOBE` in `tools/gen_assets.py`). Windows and shut shutters still take their own rounds.
  `tests/test_signs.gd`.
- **Blast wounds** (`scripts/wounds.gd`, `tests/test_wounds.gd`): a blast (a stick, a
  keg or a crate of dynamite) marks the walls in its reach for good. Rays fanned out
  along the ground find the nearest place on each face it can reach, on the faces you
  can see only, as with the bullet holes; the bigger the bang and the closer the wall,
  the worse the wound. Soot blackens the face up from where it struck, widest at the
  foot; close enough (size 0.55 and up: a stick within about 40 px, a crate from
  further off) it knocks a ragged hole in it: mud brick and cracks round a breach at
  the foot of an adobe or the fort's walls, splintered board ends round one at knee
  height in planks (the bottom of a timber wall is mud-stained and reads as porch
  boards). Rubble is heaped in the dirt below, lumps of adobe or splinters. Another
  blast near an old wound makes it worse; twelve a building, the oldest going. It's
  only a look: the wall stops rounds and eyes as before, there's no new way through,
  nobody mends it and the sweepers leave the rubble be. The wounds are painted on a
  copy of the building's picture that clips them to it (so one by a corner never
  hangs in the air), over its shutters (a hole blown in a window) and under its
  signs and lanterns. Their own dice.
- **Patching up**: most bandits carry a bandage (`bandages`; not the bandidos or
  drunks). Hit and still standing, one may break off (`patch` chance, more likely
  the more rattled he is, less for a bold one): "¡Me dieron!", into cover away from
  the stranger, down on one knee for 8 s. One HP back (El Jefe and the old timer
  aren't made whole), no more limp or bleeding. He isn't shooting meanwhile, so it's
  a moment to flank or rush him; a leader counts it as trouble and orders covering
  fire. The stranger walking up on him in plain view (~100 px) breaks it off.
  `tests/test_bandage.gd` covers the stranger's bandage (time, interruption, two
  bars, none left), his blood trail and a guard following it to him, a bandit
  patching up (and bleeding on the way), one giving it up, and who carries none.
- **Downed, not dead**: about a third of killing shots (not dynamite, not the
  knife, not a shotgun at arm's length, and never twice for the same man) put a
  bandit in the dirt instead. He's out of the fight as far as anyone's counting
  (his gun falls, comrades react, the posse and the win count him out) but he's
  still there to hit: groaning, calling for help ("¡Ayúdenme!"), bleeding out in
  45 s. Every type, from bandido to boss, can be downed and will go for a downed
  comrade: the nearest one free (within ~300 px; the more rattled, the less likely)
  shouts "Hang on, amigo!", the others nearby lay down covering fire, and he runs
  to him, drags him by the collar into cover away from the stranger (a smear of
  blood behind them), kneels and bandages him for 10 s (long enough to be spotted at it). While he has hold of him
  the downed man presses the wound and his clock stops. Patched up, he gets up with
  1 HP, shaken and limping, his own gun back in hand. Shoot the rescuer and the
  man's left lying there, clock running again. Another round (or the knife,
  quietly) finishes a downed man; the stranger's tally of such is kept, unseen, for
  a later honour system. His hurtbox lies along his body as drawn (the bake records
  where each fall leaves him, by direction: `meta.json` "lie"), so a round or the
  cursor on any part of him finds him, not just the spot where his boots were. The
  undertaker, padre and gunsmith leave him be till he's
  dead. `tests/test_downed.gd` covers going down, bleeding out, finishing him, a
  rescue (the clock stopped while he's held, up again with his gun), the rescuer
  shot mid-drag, the knife, no second time down, and real rounds aimed at the
  drawn body hitting it however he fell.
- **The last gasp**: a downed man with a pistol to hand (his own, if it's still lying
  by him, or a Colt he never drew; never a rifle or a scattergun) and the stranger
  close (~230 px) and in sight may push himself up on a straight arm, feet towards
  him, and fire. Slowly: over a second to come up, the hammer cocked audibly, then a
  round every 2.4 s, wide (twice his usual spread). One shot mostly, two or three now
  and then (no more than a derringer or howdah holds). Then he sinks back and lets
  the gun go: half the time it's the end of him, otherwise he's still down with 12 s
  gone off his clock and can still be saved. Not all of them try it: a chance per type
  ("gasp": gunslinger 0.75, El Jefe 0.65, the old timer 0.6, pistolero 0.55, bandido
  0.5 (there are so many of them), cowboy 0.45, down to a drunk at 0.25), cut to 0.6x
  while a comrade is near enough to come for him, and not tried at all while one is
  on his way, since a man who can hope to be dragged clear would rather wait. He makes
  up his mind when the stranger first comes in sight, and once more late, when nobody's
  come. But walk right up on him (~120 px) and he doesn't wait for anyone: help coming
  or not, he gets one more think, 1.6x as likely (at most 0.95), and a comrade on his
  way is let off. Play with `-- --gasp` to have every man who can try it. A round
  while he's up finishes him and isn't counted as shooting a wounded man. The
  propped-up poses are baked per pistol into each template's "full" animations
  (`full/<gun>/gasp_rise|aim|fire|sink|die`). `tests/test_lastgasp.gd`.
- **Hens** (for Corbucci, whose gunfights always had animals running through them):
  five hen houses stand in the back yards, two hens pecking about each, and crates
  of hens for market sit by the store, the feed store and the plaza. A round into
  a coop or crate lets them all out (four from a coop, three from a crate),
  bursting out in a flapping, squawking zigzag. Gunfire or a blast nearby sends
  any hen bolting away from it, and a man walking right up to one sends her off a
  few steps; after a few seconds she settles and pecks wherever she's got to. Hens
  are scenery only: nothing can hit them, they block nobody, and they keep their
  own dice so they never change how a seeded fight plays out. Sprites: three
  colours x eight directions x stand, two walk frames, peck and two flap frames.
  `tests/test_hens.gd` checks they keep to their yards when it's quiet, bolt and
  then settle at a shot, shy from a man walking at them, burst out of a shot coop
  or crate (once), and have no body to hit.
- **Seeing behind cover**: crouched behind something and holding still, the
  stranger is hard to make out; firing over it gives him away for a second (he
  rises to shoot, and there's the flash). Bandits in a fight within ~130 px see a
  crouched man over low cover anyway: they're watching for him. Calm guards don't,
  so creeping up behind crates still works. Once he's gone to ground behind a crate
  (or barrel, trough...) by where he was last seen, up to two bandits who can see it
  put rounds into it ("Splinter that crate!"); the rest carry on. `tests/test_cover.gd`
  covers the wear, the damage looks, the leak, which rounds go through what, the
  eyes, and the breakers.
- **Dynamite**: most of the gang's rank and file carry a stick (pistoleros,
  bandidos, riflemen, red scarves, the poacher, the old timer, the hillbilly and the
  drunks; not cowboys, gamblers, saloon girls, El Jefe or the gunslinger). They
  use it only when they believe they're being killed from one place: the stranger
  was just seen at a firing spot (see corner watching) he's killed **two or more**
  from, and has fired from in the last 8 s. A carrier 100-220 px off with no wall in
  the way, and none of his comrades within reach of the blast there, may light it:
  he shouts ("¡Dinamita!", "Fire in the hole!", or after Leone's *A Fistful of
  Dynamite*, "Duck, you sucker!" / "Giù la testa!"), winds up for 0.57 s and lobs it
  at where the stranger was seen, give or take. It arcs over crates (not walls),
  bounces, rolls to a stop, fizzing. One stick lit at a time, and 20 s after a blast
  before the next. Once it's lit, it's lit: shot dead winding up, he drops it at his
  feet and it blows there; winged, he lets go of it and runs. A drunk may throw it
  short or fumble it. On the ground a pulsing ring shows its reach (80 px), and
  bandits and townsfolk inside it run clear. The fuse runs 6 s from lighting,
  so 4-5 s once it's down: time to get clear. The blast hurts everyone in reach who isn't behind a
  wall: 8 within 32 px (death, flung back), 3 to about 56 px, then 1; a crate or
  barrel in between takes 2 of it. It blows nearby cover apart (crates, coffins and
  barrels near it, troughs badly, wagons only right by it), scorches the street,
  shakes the screen and is heard all over town (the saloon too, three shots' worth).
  It marks the walls it reaches, too (see "Blast wounds"). He can't throw it back or
  shoot it: once it's down, the thing to do is get clear.
- **The stranger's dynamite** (G; `tests/test_rally.gd`): Cruz Verde gives him one
  stick, and a dead carrier leaves his unthrown stick half the time. One at a time:
  with a stick on him, the next stays lying there till he's thrown his.
  Lit off his cigar, a wind-up (the gang's "throw"), and lobbed at the cursor, 40 to 230
  px; his own fuse is cut shorter (3.2 s from lighting). Officers see it land and run;
  the rest only now and then (35%). A hit in the wind-up makes him fumble it at his
  feet one time in four (always, if it kills him). The HUD shows his sticks after his
  bandages.
- **The rabble** (`"rabble"` per type; `tests/test_rally.gd`): in a big fight, with
  eight or more of them in combat round the stranger, the rank and file given to it
  (drunks most, revolucionarios, soldaderas and bandidos often, a few cowboys,
  pistoleros and hillbillies) now and then stand in the open wasting it for a couple
  of seconds: a round loosed at the sky with a "¡Viva Villa!" (a salute pose: arm up,
  the gun at the sky; the round is spent and heard, nothing flies), or bawling the
  others on ("We got him now!") with a point. Not in a posse of a few, and never the
  officers or marksmen. Their own dice, so seeded fights stay as they were.
  `tests/test_dynamite.gd` covers who carries it, when it's thrown, the blast, and
  the dropped and fumbled stick.
- **Powder kegs and dynamite crates** (Cruz Verde; `scripts/charge.gd`,
  `tests/test_kegs.gd`): props that go up when hit, by anyone's round (the gang's
  strays too) or a blast close by. A **keg** (squat, near black, copper hoops and a
  white band so it isn't taken for a water barrel) fizzes and spits sparks for a
  second, then goes up: reach 110 px, nobody lives within 45. A **crate of dynamite**
  (the lid prised off, the red sticks showing) catches and burns for three seconds,
  flames and black smoke, then makes the biggest bang there is: 150 px, core 60. A
  ring on the ground shows the reach while it burns. The blast is the stick's, scaled
  up (fireball, debris, scorch, shake and noise), and any keg or crate inside it goes
  up a moment after (0.15-0.35 s): one can bring a whole row of stores up, or a gate
  keg the breach's. The gang mostly blunders on (one may shout "¡Pólvora!" for all
  the good it does him); officers (rank 2 and up: the coronel, El General) know what
  it means and run clear of its reach. Townsfolk flee. A round stops in a keg; it
  isn't worn down like other cover, and hiding behind one is a poor idea, since the
  gang shoots the cover he's behind. Kegs aren't mended.
- **Corner watching**: the gang remembers where the stranger shoots from. Each shot
  is filed under a *spot*, a loose cluster: within ~90 px of its centre or ~50 px of
  any place he's fired from there, so the two corners of a small house, or turning
  from side to side, are one spot. A burst counts as one *peek* (a new one needs
  1.5 s without a shot). Once he's peeked from a spot twice, up to two bandits who
  can see one of its firing places from where they stand, within their gun's reach,
  hold their aim on it (sometimes calling "Watch that corner!"), standing ready
  instead of ducking or giving covering fire. If he shows within ~45 px of it they
  have him: almost no reaction time, already aimed, and a moment in which nothing
  pulls them off the shot. Everyone else carries on as before (flanking, closing
  in), a watch lasts at most 10 s, then that man moves again and won't settle to
  watch for 8 s, and a spot unused for 35 s is forgotten. Kills from each spot are
  counted too, for the dynamite to come. `tests/test_corners.gd` checks the loose
  spots, that nobody watches before the second peek, that no more than two do and
  the rest keep moving, that a watched corner is met almost at once, and that a new
  spot has nobody ready for it.
- **Reinforcements**: five more of the gang (two bandidos, a pistolero, a cowboy and
  a red scarf; `reserve` in the town data) drink in the saloon, out of the story
  until something brings them out. Gunfire within ~450 px of its door heats it up
  (about a shot each, cooling a quarter a second): around seven shots in a short
  while and they come. Or a runner: once a fight has gone on 3 s, a man breaks off
  from it and runs for the door shouting "¡Al saloon! ¡Refuerzos!", not stopping to
  shoot: the weak ones first (bandido, pistolero, drunkard), nearest the door, never
  the one with the stranger in his sights. Shoot him and the next goes 15 s later.
  When they rally there's a warning ("¡Vámonos, muchachos! The saloon empties!"),
  the saloon's shutters slam, and 2.5 s later they spill out of the door one every
  0.7 s, already fighting, making for the last place the stranger was seen (or the
  shooting). Silence all 25 on the street before then and the town is won; once
  they've rallied they have to die too (the count goes up as they come out).
  When it's over each goes back to a spot of his own out front of the door (a
  reachable one: they once all made for one point against the saloon wall and
  jostled there for good, corking the gap beside it). And a bandit stuck behind a
  comrade standing still asks him to step aside for a moment, instead of
  re-planning the same way through him.
  `tests/test_reinforcements.gd` checks a quiet win brings nobody out, distant
  gunfire doesn't stir them but gunfire outside does, that all five come out and
  must be killed, and that a runner is sent, can be stopped, and the next one
  brings them. (`no_reserve` leaves them indoors for tests of the street fight.)
- **Bounding**: before breaking position to move more than ~40 px, a bandit calls
  "¡Cúbreme!" / "Cover me!" (leaders always, others half the time) and the
  comrades holding positions nearby lay down fire while he sprints.
- **Leaders' orders**: El Jefe and the riflemen order "¡Fuego!" / "Covering fire!"
  when the stranger has gone to ground or a comrade is fleeing, cowering or
  reloading. Everyone nearby with a view of his likely position blazes away at it,
  seen or not, faster and looser than aimed fire; the leader either moves up under
  it or leads the shooting. Covering fire, harassing shots and panic shots all need
  a line to the spot: nobody shoots at walls, and a man who loses his view mid-burst
  ceases fire.
- **Panic shots**: a bandit running, dashing or backing off may loose a wild shot
  back over his shoulder.
- **A reason to shoot**: the gang shares when anyone last saw the stranger or heard
  him fire. Covering fire, "Cover me!", leaders' orders and panic shots need that
  to be fresh (under 5 s). Blind suppression tapers as the sighting ages and stops
  after ~2.5 s without one. From 5 to 12 s only one bandit at a time takes a lone
  harassing shot at the last known spot, about every 3 s; after that, silence until
  someone sees or hears him again.
- **Fire with fire** (`tests/test_returnfire.gd`): the stranger fires from somewhere a
  bandit can't see (one of theirs shot at round a corner): unless it's frightened him
  (a reaction coming), or he's busy (watching a corner for him, reloading, empty,
  finishing him off, standing about with the rabble), every bandit who hears it close
  (in the fight already, or near enough to join it) answers it, on his own, no order
  needed. He puts rounds for 2-3.5 s into the corner the stranger's behind
  (`game.corner_near`: his spot if there's a view of it, else his freshest blood in
  view near it, else the nearest open ground by it in view, the one furthest round
  towards him: the edge he'd come out of), so it's still never a wall. It takes him a
  moment to swing round and find it (0.6-1.2 s by his reflexes, never under half a
  second), it stops with the rest of the covering fire once nobody's seen or heard him
  for 2.5 s, and he won't do it again for 6-9 s after. The corner watchers keep their
  guns still on their corners instead. Its own dice.
- `tests/test_tactics.gd` runs a standing firefight and checks that free bandits
  shoot within a few seconds, that cover calls, leaders' orders and panic shots
  all happen, and that the shooting dies down once the stranger vanishes.
- **Spreading out**: each bandit joining a fight takes his own flanking angle and
  holds a spot around the stranger at his weapon's range, instead of filing in behind
  the others. Comrades push apart when they get too close, and a bandit holds fire
  and sidesteps when a comrade is in his line of fire.
- **Reading the fight**: a bandit reloading is plain to see — gun raised to load,
  the coach gun broken open — and he often shouts "¡Recargando!".
- Enemy aim and rate of fire are tunable at the top of `scripts/enemy.gd`
  (`AIM_SPREAD`, `AIM_SPREAD_SHOTGUN`, `CADENCE_MULT`).
- Bandit types live in `data/enemies.json` (see *Bandit types* below).
- 2:1 isometric diamond tiles. Sprites are rendered at 3× detail (96×48 px per tile)
  and shown through a close camera (about 13 tiles across) in a 1280×720 view, scaled up by whole numbers with no smoothing, in a
  maximised window.
- Buildings are solid (no interiors in v1). They fade when the hero walks behind them.
- **Town** (64x64 tiles, laid out by `tools/make_town.py`): a main street, north and
  south streets, two cross streets, a plaza with the gallows and alleys between the
  buildings. Saloon, hotel, bank, sheriff, general store, barber, undertaker,
  assay office, feed store, an adobe cantina, a church with a bell tower, stables,
  a water tower, adobe houses and boot hill; wagons, crates, barrels, troughs,
  hitching rails, cacti, tumbleweeds and mud. 25 bandits.
- **Seeing through buildings**: a building fades when it hides the hero or when
  he aims at it; anyone else hidden behind a building shows through as a
  silhouette: red for known bandits, pale for the hero, and a neutral bone
  colour for townsfolk and for anyone still passing as one.

## Look and feel

- Palette: bleached sky, ochre dust, burnt sienna wood, bone-white adobe,
  deep brown-black shadows, Corbucci red accents. Hard midday sun with long shadows.
- Black-powder smoke: every shot leaves a cloud that hangs and drifts on the wind;
  the coach gun leaves a wall of it. Missed rounds kick up dirt, and wall hits throw
  splinters and dust and leave bullet holes.
- Each gun has its own carry pose so it reads at a glance: the Colt held out at arm's
  length, the coach gun low at the hip, the Yellow Boy shouldered with its brass receiver.
- Pace: unhurried. Walk speeds and bullet speeds are deliberately slow.
- Post-process: warm grade, vignette, film grain.
- Presentation: a title card in the style of the films' opening credits and a
  church bell. If a bandit lays eyes on the hero before he has fired a shot, the
  game slows briefly while an extreme close-up of his eyes crosses the screen
  (1.7 s, counted in unscaled frame time so headless tests stay deterministic).
- Sound: gunshots are loud and echoing, like the films: a hard crack, a saturated
  powder blast and a low boom, then a long stereo canyon tail whose echoes bounce
  left and right (three takes per gun, no pitched "pew"). Gunfire carries across
  town. The mechanics are heavy and clear: the Colt's four cocking clicks, the
  hammer falling on an empty chamber, the loading gate, the Winchester's lever, the
  coach gun's hinge and snap, brass tinkling onto the boards, spurs jingling. The
  hero's own sounds play at full volume; a compressor and limiter on the master bus
  keep firefights punchy.

## Bandit types

All bandit types are data in `data/enemies.json`, shared by the game and the art
generator:

- **Templates** are body shapes (duster and bowler, poncho and sombrero, vest,
  shirt and suspenders, frock coat and top hat, saloon dress...), baked once each.
- **Types** pick a template, one or more **palettes**, a **loadout** and behaviour
  knobs: `hp`, preferred `range`, `cadence` (pause between shots), `aim` (spread
  multiplier, higher is worse), `speed`, `reflex` and `nerve` ranges, leader `rank`,
  `cover_call` (chance to shout "Cover me!"), `fires_on_move`, `draw_sidearm`,
  `flank` (chance to go round when hunting), `bold` and `opportunist` (0-1, below)
  and their own `shouts`. Anything not
  given comes from `defaults`.
- **Placements** in `data/town.json` may override any field for one bandit (a fixed
  `palette` index, a braver nerve), except the loadout, which is baked per type.
- **Palettes are free**: recolourable parts are baked in neutral grey with a slot
  map, and a shader paints each bandit, so variants cost no art.
- **Long gun and sidearm**: a bandit carrying a rifle or coach gun plus a Colt uses
  the long gun until it runs dry mid-fight, then (by `draw_sidearm`) throws it down
  and draws the pistol rather than reloading.
- **Random loadouts**: a type may list weighted `loadouts` instead of one fixed
  loadout; each bandit picks one when the town is built (the art is baked with
  every gun on the list). Saloon girls carry a derringer three times in four, a
  Colt otherwise; one pistolero in ten has a sawn-off. An option can bring its own
  knobs too (the sawn-off pistolero's range, flanking and firing on the move), so
  he fights the way his gun wants.
- **Within reach**: a fighting position, in cover or in the open, is never further
  from the stranger than the bandit's own gun reaches, so a derringer has to come
  close.

| Type | Look | Guns | Character |
|---|---|---|---|
| Pistolero | poncho, sombrero (3 serapes) | Colt, now and then a cut-down Rolling Block under the poncho | rank and file, often breaks under fire |
| Bandido | peasant whites, straw sombrero, bandolier, coloured sash (3) | Colt Navy (cap-and-ball), now and then a Champion too | 1 HP, poor aim, thin nerve, slow to react; dangerous for six shots, then an age reloading |
| Cowboy | vest, bandana (3 palettes) | Colt, a Champion slung for one in four | steady mid-range gunman |
| Rifleman | duster, bowler (2) | Winchester + Colt | good shot, leader (orders covering fire) |
| Red Scarf | vest, red scarf | coach gun + Colt | rushes in, fires on the move |
| El Jefe | red duster, sombrero | coach gun + Colt | 4 HP, nerves of steel, leader |
| Drunkard | shirt, suspenders, slouch hat (2) | Colt, now and then a Champion | wild aim, slow, scared, slurs |
| Gambler | frock coat, top hat (2) | Remington derringer | quick hands, cool head |
| Saloon girl | dress and shawl (3) | derringer (3 in 4) or Colt | opportunist, passes as townsfolk until something's up |
| Poacher | buckskin, fringe, coonskin cap, beard (2) | Sharps 1874 | sniper: very long range, deadly, slow single-shot reload |
| Old timer | old cavalry coat, slouch hat, white beard (Union / Confederate) | howdah pistol | 3 HP, slow, unshakeable, "Seen worse at Shiloh!" |
| Gunslinger | black (or tan) vest, red scarf, flat hat, two holsters (2) | a pair of Colts | bold: walks in shooting, fast, scorns cover, "Draw, stranger!" |
| Hangman | black hood with eye holes, dark shirt, suspenders | Colt | San Miguel's hanging only: keeps to the gallows steps till the man is dropped, and fights from them after |
| Hillbilly | bib overalls, straw slouch hat, beard (3) | sawn-off | 3 HP, closes in fast, fires on the move, "Git off my land!" |

**Opportunists** (`opportunist`; saloon girls 0.85, with low nerve) shoot while
the stranger's attention is elsewhere, quickly, without lining up long. When he
turns his gun her way (aiming within ~20 degrees, in sight, within ~260 px) or
comes within ~70 px, she wavers after a moment: backs off, ducks for cover or
flinches, then tries again from somewhere else; never twice within 3-5 s. And
she won't stand and shoot it out while he has her in his sights.
`tests/test_opportunist.gd` holds the hero still, aiming at her and then away:
she must waver only when aimed at and shoot more when he looks away; a cowboy
never wavers just for being aimed at.

**Bold** bandits (`bold`, the gunslinger has 0.8) fight differently: near misses
pin them down only briefly and shake them less; they seldom flinch, duck, back off
or run; they often skip cover and pick a fighting spot near the close end of their
range, never give ground, and their sidesteps close in while they keep shooting on
the move. With a pair of guns, the left usually follows the right quickly
(bang-bang), and if he can see the hero while reloading he comes back out as soon
as one gun is full. Blind suppressive fire keeps a steady floor (0.45 s) whatever
the type, so a quick-handed bandit can't fill the air at nothing.

The **Remington double derringer** (1866) has two stacked barrels, cocked per shot,
short range and damage 1; its barrels tip up to reload. The **Sharps 1874** is a single-shot
falling-block buffalo rifle (damage 3, the longest range, reloaded after every shot).
The **howdah pistol** is a two-barrel .577 break-action hand cannon (damage 2 per
barrel, both can go at once). The gunslinger's **pair of Colts** holds twelve: the
chambers alternate between the guns, so he fires right, left, right, with only a
short pause between; he reloads one gun at a time while the other sits holstered
(`tests/test_gunslinger.gd` pits one against a pistolero under fire). The
**Colt Navy 1851** is the old cap-and-ball revolver the bandidos carry: six shots,
damage 1, a fog of black-powder smoke, and no cartridges. Each chamber is charged
with powder and ball, rammed and capped, so a full reload takes about 11 s (a
Colt's ~4.5): empty, a bandido is a sitting duck. It leaves nothing for the
stranger to take. Revolver reload steps are data (`eject`, `insert` per gun). The
**sawn-off** is a double 12-gauge cut down to a pistol grip and stubby barrels: the
coach gun's shells and volley, a much wider pattern (15 degrees) that is spent by
~115 px, and a quicker reload. It's carried at the hip like the coach gun, and a
blast from it up close throws a man back just the same (`tests/test_hillbilly.gd`
checks a hillbilly closes to its range and fights nearer than a cowboy). The
stranger can take one up off a dead hillbilly for his shotgun slot, or ride in with
it: murder in a doorway, useless across the street (`tests/test_pickups.gd`).

Guns are data too (`Weapon.DATA` in `scripts/weapon.gd`): an action type (revolver,
lever, or breech for anything that opens to load), stats, smoke, and for breech guns
the barrel count and each reload step's time and sound. A new breech gun is a data
entry plus a model and poses in `tools/chars.py`. `tests/test_types.gd`
checks the type data against the baked art.

### The revolutionaries

Up from the south for Cruz Verde (and three of the five drinking in San Miguel's
saloon reserve): no modern kit, and a worse, older arsenal than the gang's. Most of
them carry revolvers (the Navy above all); the long guns go to fewer of them and are
cast-offs (see "The revolution's arsenal" below).

- **Revolucionario**: white campesino cottons, two bandoliers crossed over the chest,
  a striped serape over the left shoulder, a big straw sombrero; mostly a Navy or a
  Colt (8 in 11, and a Champion slung for one in four of those), else a Spencer, a Springfield or an escopeta with a Navy to fall
  back on; 2 HP; "¡Tierra y libertad!".
- **Tirador**: the same in plainer cloth, with a long eye: a Springfield (less
  accurate than it should be, in his hands), a Spencer, or a captured Winchester.
- **Sargento**: bearded, sashed, coach gun (or a Spencer) and Colt; calls the orders
  (rank 1).
- **Soldadera**: a woman of the revolution in a long dress, crossed bandoliers and a
  sombrero; a Navy or a Colt more often than not (now and then a Champion with it), else a Spencer or an escopeta.
  (Not the saloon girls: they're still about.)
- **Coronel**: an olive tunic with two rows of brass, a red collar, gold epaulettes, a
  kepi, a cavalry sabre at the hip (for show) and a Colt; 3 HP, rank 2.
- **El General**: Cruz Verde's boss (as El Jefe is San Miguel's: both `"boss"`): a dark
  tunic with medals and a red sash, epaulettes, a peaked cap with gold braid, a cigar,
  a sabre, coach gun and Colt; 4 HP. He's the garrison's **coordinator**
  (`"coordinator"`): while he lives, or sleeps, the gang's alarm is organised (men sent
  to look, a holdout to fall back on). Down he goes and the banner says it, "¡Mataron
  al general!": every man left is shaken to the core with his nerve cut, the
  faint-hearted run, nobody gives orders any more (no men sent out, no falling back,
  however badly it goes), and anyone still to come out of a door or down a road
  arrives shaken. Hunting the general is worth the risk. `tests/test_general.gd`.

**The revolution's arsenal** (`tests/test_arsenal.gd`):

- **Spencer carbine** (1860): the repeater the revolution has instead of the
  Winchester. Seven rounds in a tube through the butt, and two motions a shot: the
  lever, then the hammer thumbed back (0.85 s between shots against the Winchester's
  0.45); a little less range and a slower bullet. A lever gun with `"tube": 7`.
- **Springfield Model 1861** rifle-musket: a fine gun, long (armory-bright barrel,
  three bands, the ramrod beneath), a .58 Minie ball that hits for 3 and carries far.
  But a muzzle-loader: one shot, then he stands it on its butt, tears the cartridge,
  pours, rams and caps, about 6.7 s. In revolutionary hands its aim is worse than the
  gun deserves (`"aim"` on the loadout).
- **Pistola**: a single-shot percussion horse pistol (a Model 1842 or the like):
  smoothbore, a big soft ball that wanders (damage 1), then powder, ball and rammer
  all over again (about 6 s). The last waves' gun; some carry a brace, fire one, throw
  it down and draw the other.
- **Escopeta**: an old single-barrel percussion fowling piece, the peon's gun: a
  fistful of shot at close range, then powder, wad, shot, wad, all rammed down from
  the front (about 7.4 s). Nobody waits for that: fire it once, throw it down, go to
  the Navy (`"draw_sidearm"` 0.9 on that loadout).

Muzzle-loaders are breech guns in `Weapon.DATA` with their steps renamed (open: the
cartridge torn; eject: the powder poured; insert: the ramrod; close: the cap), and
their own poses: the gun upright by the left foot, the right fist working the rod
above the muzzle. A loadout option can carry its own way of fighting (`range`,
`aim`, `draw_sidearm`, `fires_on_move`) over the type's. A man created with
`"pistols_only"` (the director does it for everyone coming out of a door but the
boss) is given a revolver option only.

New pieces of costume for them in `tools/chars.py`: the serape, a "uniform" style (a
buttoned tunic with a coloured collar, a short closed skirt), epaulettes, medals, the
sabre, the kepi and the peaked cap; a dress can do without its shawl.

### The federal army

Paso Esperanza's enemy: the government's army come for the train, in blue and white,
kepis and one bandolier over a white crossbelt (`"bandolier": "one"`,
`"crossbelt"`), many of them and most of them poor soldiers.

- **Leva** (`leva` body: a pressed peasant in his white cottons and an army kepi):
  the most of them. One hit and he's down; a Springfield (or an escopeta, or a horse
  pistol), slow to load and badly aimed; little nerve.
- **Soldado** (`federal` body): a regular, steady, a Springfield or the new
  Remington Rolling Block.
- **Cabo** (`federal`, gold on the kepi): a Remington or a coach gun and a Navy;
  rank 1, calls the covering fire.
- **Rural** (`rural` body: the grey charro suit and the big grey sombrero of the
  rurales): few, and dangerous: a Spencer and a Colt, bold, shoots on the move,
  works round the flanks; the only ones with dynamite.
- **Abanderado** (`federal`, a white kepi): the colours, the tricolour with the eagle
  on its cactus, on a staff in the crook of his left arm, and a Navy he fires
  one-handed (the `banner` pose set: the Navy's, the left hand on the staff but to
  load, the flag drawn with the body). One to a company at most, by name in the
  waves. Shot, the colours go down in the dirt (`flag_down`): every man within 300 px
  sees it, the levas lose heart and the rest are shaken. The nearest regular
  (soldado or cabo, `"flag": "raise"`, within 340 px) runs to them whatever's flying,
  drops his long gun, takes the colours and a Navy, and they're up again; shot in
  his turn, they stay down. (Raising them costs no more baking: the regulars and the
  bearer share a body.)
- **Teniente** (the coronel's body in federal blue, gold braid): rank 2, a Colt;
  leads a company.
- **Capitán** (the same body, white trousers): the commander (`"commander"`), with
  the second-to-last company. His death shakes every man on the field and sends
  the faint-hearted off; the companies still on the road haven't heard, and come
  on as before (unlike El General's, it leaves nobody leaderless).

**The assault** (the map's `"assault"`: spots close round the engine, the tender
and the breastwork, where the stranger and his gun can see them come; spread along
the cars, the east road's companies went north out of his sight; and, for the
flankers, spots on the train's far side among the carriers). Each man walking in is given one of the few spots nearest his road
and goes for it, the stranger or no. He goes in bounds of 90 to 150 px: to cover a
little further on (cover from the stranger, nearer the train than where he is), or,
the less he knows about cover, to open ground (`"cover_use"`: a leva 0.25, too green
to be careful; a soldado 0.85; an officer 0.9). Between bounds he's down a while
(1.5 to 3 s; a leva hardly stops), shooting if he can see the stranger, longer if
rounds are coming in. On the move he doesn't shoot, but a rural does. At his spot
he fights it out from there.

They know they'll never beat a machine gun from far off: lying out there under it
is death, and the only way is in. So while a man is short of his spot and more than
160 px from the stranger, he's **pushing**: a round past him doesn't pin him (it
only shakes him a little, and gives him a chance to duck once every few seconds,
0.15, a leva twice that), a comrade falling beside him doesn't stop him, his bounds
are longer (150 to 230 px) and he's down only a moment between them (0.25 to 0.7 s).
Inside 160 px he goes back to fighting from cover, pinned and ducking like anyone.
(Before this they'd lie pinned at the edge of the stranger's sight for as long as
the gun kept firing.)

But they still fear the gun, where it's doing its work and the stranger can see
it. When it cuts a man down, the men within 90 px of him who are on the stranger's
screen (or within 300 px of him and in his sight) take fright, pushing or not: most
throw themselves into the nearest cover, some give ground (a regular, 0.2, 0.4 if
he was right by the man; a leva turns and runs back a way, 0.4, 0.6 close), and in
2.5 to 4 s they're up and coming on again. For 8 s after that the gun doesn't
frighten them (`GUN_NERVE`), so they don't lie there for good under it: they come
on in rushes, and go to ground in clumps where it finds them. Men off down the line
where he can't see don't hear of it: no rout starts out of his sight.

**The smoke** (the map's `"haze"`: [0.7, 1.4]). It's a big battle, black powder and
chaos everywhere: the army's guns carry seven tenths as far as they would (and they
keep their distances in proportion), and throw four tenths wider, volleys and all.
The stranger's don't: he's a hardened professional. So they have to get close
before they're much danger. A cabo or teniente with three or more men about him who
can see the stranger has them hold and aim ("¡Apunten!") and fire together a second
later ("¡Fuego!"), every 15 to 20 s: a volley you can see coming. A leva who loses
heart (his capitán dead; the colours down, four in ten of the levas who see it; or
now and then at a comrade falling beside him, 0.04: `"deserts"`) throws it in and runs for the nearest road, and is gone
off the map, not dead. And a man round among the carriers (within 220 px of one, in
sight, the stranger not close) gets one chance (`"hunt"`: a rural 0.35, a soldado or
cabo 0.1, a leva 0.05) to turn his gun on them: he kills one and he's back to the
stranger; he never tries again. Their own dice (`Enemy.assault_rng`), so no other
level's fight moves. `tests/test_assault.gd` plays the bounds, the push, the levas'
cover against the regulars', a volley, a deserter, the smoke, the gun's fright and a
hunter.

Dead, they drop their guns like anyone: the stranger can take up a Remington.
`tests/test_federales.gd` checks the bodies have their guns, the Remington, the
waves coming with the loading (and their officer and colours), the colours going
down, raised and going down for good, and the capitán's death.

## Townsfolk

A dozen unarmed townsfolk (fewer than the bandits) go about their business in
town: townsmen, peones in white, townswomen, gentlemen in frock coats and saloon
girls. They are data too, under `civilians` in `data/enemies.json` (template,
palettes or `palettes_from` a bandit type, `speed`, `nerve`, `snitch`, `wander`,
`shouts`), placed by `tools/make_town.py`.

- **Life**: each idles near home and strolls about within `wander` px of it.
- **Panic**: gunfire within ~110 px, or in view within ~320 px, a round cracking
  past (whoever fired it), or a man dropping in front of him sends him running.
  He heads for the nearest doorway that doesn't take him towards the shooting, or
  off the edge of town if that's nearer, and fades through it: out of the story.
  Doorways are recorded from the building models when the art is generated
  (`doors` per object in `assets/meta.json`). Short on nerve or caught close, he
  cowers on the spot for a few seconds first.
- **Snitches**: one in five (`snitch` 0.2; saloon girls 0.3), decided at random
  when the town is built. Nothing marks them, but a sharp eye can tell: honest
  folk glance at the stranger for about a second and look away; a snitch keeps
  staring, turns his head to follow him, and starts edging off towards the nearest
  bandit. After about 2.5 s with the stranger in view he hurries to that bandit
  with a white "!" over his head, points the way and shouts, and the bandit raises
  the alarm. Then he runs indoors. Stopping him means shooting an unarmed man, or
  getting out of his sight before he's done looking.
- **Coming back out**: once the town is quiet (no gunfire and no bandit fighting
  for `quiet_after` seconds, 45 for now, in `game.gd`), those who hid come back
  out of the door they went in by, a few at a time, at least 10 s after hiding, and
  walk home. Snitches are re-rolled, so the one who told last time may not again.
- **The undertaker and his apprentice** (`role: "undertaker"`): the undertaker
  waits at his shop on main street, the apprentice up on boot hill. When the town
  is quiet each claims the nearest dead bandit nobody else is seeing to, walks over,
  bends to measure him with a tape ("Six foot one. Pine."), then hauls him by the
  boots up to boot hill, leaving a smear in the dirt. There he's buried under a
  heap of fresh earth with a cross at its head (so new graves stand out from the
  old ones) and is gone: a buried man is nothing for the bandits to find. A
  bandit who sees a comrade being dragged past still finds the body. Gunfire
  makes them let go and run indoors like anyone else; the body stays where it
  dropped until they come back out. They see only to bandits for now, and take a
  man the padre has blessed, anywhere in town, before one he hasn't (any, if none is blessed yet,
  preferring one the padre isn't on his way to). Their animations are the "tools"
  set: empty hands plus measuring and dragging.
- **The padre** (`role: "priest"`, black cassock, white collar, breviary): waits
  at the church door. When the town is quiet he walks to the nearest of the dead
  he hasn't blessed, anyone at all, bandit or townsman, kneels and makes the sign
  of the cross over him ("Requiescat in pace."), and the church bell tolls once,
  far off. He leaves a man the undertakers already have in hand. A holy man, he
  fears no one: gunfire, near misses and killings in front of him never send him
  running or cowering (at most he calls out "Put down your guns!"). He still waits
  for the quiet before going out to the dead. Animations: the
  "prayer" set.
- **The sister** (`role: "sister"`, placed `indoors`; in San Miguel's church and
  Cruz Verde's chapel): a black habit, a white coif and wimple, a rosary at her belt.
  She stays inside, and fears no one, the stranger included. Gunfire within ~320 px
  of the door brings her out onto the doorstep, beckoning ("¡Adentro, hijos!", "In
  here, quickly!"): townsfolk running from shooting within ~300 px make for her door
  over any other. Ten seconds without a shot near it and she's back in. If the padre
  is shot she runs out to him at once, whatever's flying ("¡Padre!"), and drags him
  back by the shoulders, leaving a smear, in through the door, and nobody sees him
  again. What became of him is left unsaid: the end card says only "the padre: in
  God's hands". With him gone she sees to the dead in his place once the town is
  quiet, kneeling and crossing them ("Descansa en paz."), but no bell tolls for
  hers; the undertakers still take a blessed man first. Shot herself, she drops
  where she is, and so does he. Animations: the "nun" set (folded hands, beckon,
  drag, bless).
- **The barber-surgeon** (`role: "barber"`, San Miguel only): shirtsleeves with red
  sleeve garters, braces, an apron and a black leather bag; he stands on the porch
  of the barber's (BATHS). Only gunfire close by (~220 px of him or his door), a
  round past him or a man dropping in front of him sends him in, and he doesn't wait
  for the town's quiet to come back out: 12 s without a shot near his shop will do,
  however it's going elsewhere. If the stranger is wounded (bars down, bleeding or
  limping, or in his last stand) within ~120 px of the door and in sight of it,
  and no bandit fighting him has him in view within ~300 px, the barber comes out
  ("Hold still, friend.") and binds him up where he stands: 5 s (a bandage takes
  10), the stranger keeping still ("PATCHING UP" on the HUD; moving starts it over,
  and firing sends him back in). Done, the stranger is whole again, the bleeding and
  the limp stopped, up out of the dirt if he was down, his own bandage kept. Once a
  level, so bandages still count. With the stranger seen to, he'll kneel by any
  downed man within ~180 px of his door that none of the gang has come for (the
  bleed-out clock stops while he works), and 8 s later the bandit's back on his
  feet with one HP: he gets paid either way. Animations: the "barber" set (bag in
  hand, binding a man standing, tending one on the ground).
- **Cruz Verde's cemetery** has its own folk, out among the graves west of the fort
  by the stranger's start:
  - *The families of the revolution's dead* (`role: "visitor"`: three women in
    black, `widow`, and a peon, `widower`) go from grave to grave round the stone
    circle (which is drawn under anyone crossing it, `game.FLAT`) (any cross, headstone or mound on the level's `boothills` within ~320 px
    of where each started), standing or kneeling at each for 10-18 s, the grief
    poses, now and then a word ("Mi hijo...", "Viva la revolución... para qué.").
    A fresh grave nobody's wept over yet comes first.
  - *The grave digger* (`role: "digger"`, beard, slouch hat, braces, a long-handled
    spade) works down a row of three open graves (`open_grave`: the spoil heaped at
    the back, a coffin like those about San Miguel's streets waiting, a cross on
    its lid, the hole in front) along the west road:
    24 s digging, the coffin let down (the pit then shows its lid,
    `open_grave_in`), 12 s filling in, and it's a fresh mound and cross like the
    undertaker's in San Miguel, for the families to come to. Then the next. He only
    buries those coffins: the gang's dead in the fort stay where they fell.
  - There's nearly always shooting at the fort, so only gunfire within ~220 px of
    them, of where they started, or of the west gate (`ward` in the placement)
    scatters them, and a near miss or a man dropping by them. They run off the west
    edge of the map rather than into town, and they're back 8 s after it stops there,
    however it's going in the fort; the digger takes up his grave where he left it.
  - *The fort's carpenter*: Cruz Verde opens with the last battle's damage not all
    mended: eleven crates, barrels and thrown-over tables shot up (`worn` on the
    map's objects: 1 holed, 2 wrecked flat, no cover), set silently as the level
    loads. The town's carpenter is placed there `local`: like the cemetery folk he
    minds only gunfire close by, and he doesn't wait for the town's quiet, so he's
    at the damage from the moment the stranger arrives, nearest first, and back at
    it 8 s after shooting near him stops. Whatever he mends is cover again.
  - *The morning after*: the revolution's leaders drank late, and broken bottles lie
    about the fort (the map's `litter`: thickest round the cantina, the general's
    house and the plaza tables), green, brown and clear glass by a dark stain, laid
    down on their own dice (`litter_rng`). Two sweepers, placed `local` like the
    carpenter, are at them from the start, and at whatever blood and glass the
    fight adds.
  Animations: "grief" (both templates) and "spade" (dig, lever, throw). They roll the
  townsfolk's own dice like the sister and the barber.
  The sister and the barber roll their own dice (`Civilian.rng` through each one's
  `dice`, which `game.sfx` and `game.free_point_near` also take), so the seeded
  tests play out as they did before them.
- **Couples**: two placements sharing a `couple` id stroll together while all is
  calm: the first leads (with a long `wander`), the second walks on his arm,
  finding her way round anything in the way, and he waits if she falls behind.
  At the first shot each runs for it alone; back out, they pair up again.
- **Mourners** (`role: "mourner"`, placed `indoors`): women in black, a rebozo
  drawn over the head and long sleeves, who stay inside until there's a fresh
  grave. Once the town is quiet one comes out (two at most to a grave) and walks
  up to boot hill to stand at the mound, hands clasped and head bowed, now and then
  a handkerchief to her eyes ("Descanse en paz."), for 20-30 s; then she goes home
  and in. Gunfire scatters them like anyone, and a grave left unmourned waits for
  the next to come out. Animations: the "grief" set.
- **The gunsmith** (`role: "gunsmith"`): spectacles, bowler and a leather apron; his
  shop sits between the bank and the store, a big carved rifle over the door. Every
  bandit drops the gun in his hand when he falls (a man who draws his sidearm throws
  his empty long gun down), and the cartridges the stranger could take lie with it.
  Once the town is quiet the gunsmith goes out for them: the nearest first, then
  only ones close by (~400 px), four or five a trip, down on one knee for each and
  holding it up to the light ("Needs a new spring."). He leaves a gun lying under a
  body until the undertaker has the man buried or dragged away. Whatever he takes,
  its cartridges go with it, so loot left lying is loot lost. He carries the armful
  home and into the shop. Gunfire sends him running with it (he keeps it); shot,
  he drops it, and the guns and their cartridges spill round him. Animations: the
  "smith" set (a rifle to inspect, an armful to carry).
- **The mayor** (`role: "mayor"`, with a `stump` to speak from): top hat, a grey
  frock coat, a red waistcoat with a gold watch chain, thumbs in its pockets. He
  idles on the bank's porch. Gunfire he can hear sends him hurrying out to the
  plaza by the gallows, where he harangues them all, arms wide, a hand raised to
  heaven, palms down to calm them ("Gentlemen, please!", "Think of the election!",
  "¡Basta ya, señores!"). It's all bluster: a round cracking past or a man dropping
  near him and he's on his knees, hat in hands ("Don't shoot! I'm the mayor!"),
  staying down while the shooting goes on; once there's been 3 s without a shot
  he's back up and at it. After 8 s of quiet he steps down; after 12 he tours the
  damage, hands behind his back, nearest first: every shot-up or wrecked crate,
  barrel, trough or wagon and every scorch mark from the dynamite, up to four a
  tour, tutting at each ("Who's going to pay for this?", "That was a perfectly good
  crate."), then home. No effect on the fight. Animations: the "mayor" set.
- **The town puts itself right** once it's been quiet a while, like the undertaker:
  - *The carpenter* (`role: "carpenter"`, hammer in hand, apron) mends whatever
    wood is broken: crates, barrels, coffins, troughs, wagons, chairs, tables,
    coops, crates of hens. Whatever the mayor has tutted over comes first (as the
    undertaker prefers blessed bodies), then the nearest. Down on one knee
    hammering, 12 s for cover, 6 s for furniture; a wreck comes back whole,
    solid and cover again (he waits if someone's standing in the way). So cover
    shot to pieces doesn't stay gone if the stranger lets the town settle.
  - *The saloon keeper* (`keeper`, slicked hair, towel over his arm) keeps to his
    own porch: his tables (fresh bottles and all) and chairs, nobody's orders.
  - *Two sweepers* (`sweeper`, peones with brooms) sweep the nearest mess into the
    dirt, a broom's reach at a time: blood (drops, pools once the body's gone),
    glass, crockery, scorch marks, spilt water. The stranger's blood trail goes
    with it, so a swept trail can't be followed. They keep apart from each other.
  - *Two hen women* (`henwife`, rebozo and apron, a broom) go after any hen well
    away from a coop (~80 px), get round behind her and shoo her home along the
    streets ("¡Fuera, fuera!"): into the coop if there's room, else she pecks
    about outside it. Hens don't mind them.
  All of them run from gunfire like anyone else and leave the job for later;
  shooting one is shooting an innocent. Animations: "carpentry", "keeper" and
  "broom" (sweep, shoo) sets. `tests/test_crew.gd` checks the mending (the
  mayor's list first, the crate solid and cover again, the keeper's own things by
  the keeper), the sweeping (blood trail and glass gone), the hens shooed home,
  and the carpenter dropping his job at a shot.
- **Shutters**: every glazed window on the wooden buildings and every small window
  on the adobes has a pair of shutters (weathered planks on the wood, painted
  turquoise, blue, green or oxblood on the adobes, the fort's included; one colour per building, picked
  in game). The townsfolk behind them slam them shut as the stranger comes into
  view (~150 px, line of sight), one after another ahead of him with a bang of
  wood; crouched, he's only noticed within ~70 px. Gunfire slams every shutter
  within earshot of it, the nearest first. Once the town has been quiet a while and
  he's moved on they creak open again, a few at a time. A fifth are shut from the
  start, against the heat. Purely atmosphere: the bandits pay them no mind. The
  shutters are baked per window (four frames, open to shut) in neutral grey,
  rendered with the building around them so a porch post stays in front.
- **Innocents**: townsfolk are hit by stray rounds from either side, and bandits
  hold fire when one is in the line. If the hero kills one, the town notices: "AN
  INNOCENT - the town will remember", witnesses shout "Murderer!" and run, and the
  end card counts them ("innocents shot: 2"). No other penalty yet.
- **His tally**: every end card, won or lost, counts the gang he put down ("12 of
  the gang by your hand", "(3 from the dirt)" for any shot from his last stand).
  A man downed counts when he drops.
- **Bandits passing as townsfolk**: types marked `concealed` (the armed saloon girl
  and the gambler) look like the unarmed ones: hands empty (they're baked with the
  unarmed set too), no vision cone, no suspicion bar, and a neutral silhouette.
  They are never the ones to start anything: they ignore footsteps, glimpses of the
  stranger, distant shots and bodies. They drop the act (gun out, cone on, red
  silhouette) only when the fight comes to them (gunfire close by, a comrade's
  alarm, a snitch, the posse forming), or when the stranger walks right up to them
  (within ~40 px), and then they draw on him.

`tests/test_civilians.gd` checks townsfolk near a shot run indoors while those far
off carry on; that a snitch stares (and hasn't run yet) after 1.8 s, then reaches a
bandit and starts the fight; that an honest townsman looks away; that concealed
bandits pass as townsfolk, let the stranger stand a few paces off, and draw when he
walks right up; and that a dead townsman counts as an innocent.
`tests/test_aftermath.gd` (with a shortened quiet period) checks the undertakers
bury every body, wait for the quiet, drop a body and run at a shot, come back out
and finish, and that buried men are no longer found; that the padre blesses a dead
townsman and bandits and never runs from gunfire; and that an undertaker takes a blessed man over a nearer
unblessed one. `tests/test_couples.gd` checks couples stay together on a stroll and
scatter at a shot. `tests/test_mourners.gd` checks nobody in black comes out
before there's a grave, that mourners stand at the fresh graves once it's quiet,
run at a shot (freeing the grave), and in the end mourn every grave and go home.
`tests/test_gunsmith.gd` checks the gunsmith waits for the quiet, never takes a gun
from under a man still lying there, carries four or five a trip, takes the
cartridges with the guns, and that shooting him spills his armful, cartridges and
all. `tests/test_mayor.gd` checks the mayor goes out to speak at gunfire, cowers
at a near miss and stays down while it goes on, gets back up in the calm, steps
down in the quiet and then tours every bit of damage and goes home.
`tests/test_sister.gd` checks the sister starts indoors (and Cruz Verde has one),
comes to the door at gunfire with a townsman running for her door, goes back in
once it's quiet there, drags the shot padre in under fire (gone for good), then
blesses a dead bandit, and that the end card leaves his fate unsaid.
`tests/test_barber.gd` checks the barber leaves a stranger too far off, or under a
bandit's gun, alone; patches him up close by, in under the bandage's time, his own
bandage kept, and only once; ignores shooting across town but ducks in at shooting
by the shop and is back out while the town is still loud; and gets a downed bandit
by his shop back on his feet.
`tests/test_cemetery.gd` checks the families go grave to grave and stay in the
cemetery, carry on through shooting in the fort, scatter off the map at shooting by
the west gate and are back soon after it moves off (the fort still loud), and that
the digger digs out all three graves, lets each coffin down and fills it in, and the
families mourn at each fresh grave.
`tests/test_fort_carpenter.gd` checks Cruz Verde opens with eleven props worn
(three wrecked, out of the way), uncounted; the carpenter starts on them at once,
works through shooting across the fort, runs from shooting by him and is soon back,
and in the end mends every one, cover again.
`tests/test_litter.gd` checks Cruz Verde opens with last night's bottles lying about
the fort and the two sweepers start on them at once and sweep up every one.
`tests/test_shutters.gd` checks creeping down main street slams far fewer shutters
than walking it, that the far end of town stays open, that a shot slams those
around it, and that they open again once it's quiet. `tests/test_perf.gd` times a
firefight with and without the townsfolk.

## Animation

Characters are two stacked layers: **legs** (trousers, boots, the duster's skirt)
and **upper body** (belt and up, arms, head, hat, gun). The legs follow movement
(idle, walk, crouch, crouch-walk, stagger, limp) and report their hip height each
frame; the upper body sits on top at that height and plays the gun's animations,
so walking while reloading or limping while firing needs no combined frames.
Deaths are whole-body and the gun falls away as a separate prop, so they exist
once per character rather than once per gun. The blood pool is separate too:
baked once per death and direction (`pools` in `assets/meta.json`, the same for
every body) and laid on the ground as the body comes to rest, spreading over a few
seconds. A body dragged away leaves it behind.

- Upper body, per gun: aim, fire (recoil), cock / fan (Colt), lever (Winchester),
  reload open / eject / insert / close, point, flinch, cower, and hit reactions
  (left shoulder, right shoulder, gut).
- Hits: where the round lands decides the reaction; a leg hit staggers him and
  leaves him limping (slower) for several seconds.
- Deaths: thrown back (shotgun up close), down on the knees then face down, spun
  round, and the slow Leone slump.
- Animations are data in `tools/chars.py`: a few key poses interpolated into
  frames at 4-12 fps, with event frames (brass ejecting, shells) the game reacts
  to. What a gun throws out (a lever's case, a revolver's empties knocked out, a
  Schofield's whole cylinder, a shotgun's shells) falls as a particle and, where it
  comes to rest, stays for the rest of the fight: a pixel of brass, or red for a
  shell, flat on the ground (`scripts/brass.gd`). Each one falls to its own spot a
  few pixels nearer or further than his boots (`Brass.rng`, seeded for tests), so they
  scatter rather than line up. The ground is cut into 256 px squares that each draw
  their own, so a new case redraws only its square; past 2000 the oldest go
  (`tests/test_brass.gd`). The machine gun throws out none. Frames are trimmed and packed into one atlas per character; metadata gives
  each frame's rectangle and offset, each legs frame's hip height and each aiming
  frame's muzzle point.

## Tech

- Godot 4 (GDScript). The world is built in code from `data/town.json`.
- Gameplay runs on the screen-space ground plane. Bullets and sight lines are
  tested at foot level and drawn at gun height.
- Pathfinding: `AStarGrid2D` on a half-tile grid.
- Long things (a boxcar, the engine, a wagon and team: `CHUNKED` in `tools/world.py`)
  are rendered once and cut into pieces a couple of tiles long, each its own
  sprite and building sorted at its own middle: one sprite sorts at the middle of
  the whole thing, so a man beside one end of a boxcar was drawn behind it. Each
  pixel goes to the piece holding the point it shows, the outline to the piece it
  rings, the shadow to where it falls; the pieces of one thing fade together.
- Performance (a big fight, measured with `tests/profile.gd`): paths are
  string-pulled in one pass over the grid path's turns (not a ray to every later
  point), and at most two hunts are planned a frame; a bandit checks for cover to
  shoot at a few times a second; who's hidden behind which building is worked out
  20 times a second. Smoke, sparks, splinters and ground marks are drawn as quads
  of one shared disc texture (they batch: a few draw calls a cloud, not a circle
  each), and view cones as two triangle fans. Every sprite is loaded at start, so
  nothing is first read from disk mid-fight. In a window, a 40 s fight on main
  street went from ~40 ms a frame (600-970 draw calls, ~30k primitives) to ~11 ms
  (~200 draw calls, ~3k primitives), only the first frames after loading over 17 ms.
- All art and sound are generated by `tools/gen_assets.py`, which uses a small
  point-splat 3D renderer for 8-direction sprites and synthesises the sound
  effects. Every asset can be swapped for hand-made art later.
