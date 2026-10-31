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

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Aim (hovering over a bandit aims at him) |
| LMB | Fire |
| RMB | Revolver: fan the hammer (hold) · Coach gun: fire both barrels |
| C / Ctrl | Toggle crouch |
| R | Reload (press fire to stop a partial reload) |
| 1 / 2 / 3, wheel | Colt / coach gun / Yellow Boy |
| Enter | Restart after win or loss |
| Esc | Quit |

## Hero

Long dusty duster, flat-brimmed wide hat, cigarillo, gunbelt and a shell
bandolier. 6 HP: revolver and rifle hits deal 2, buckshot pellets deal 1, so
he survives two clean hits. No health pickups.

Crouching: half speed, silent footsteps, tighter spread and a smaller visual
profile (see Stealth).

## Weapons (period-authentic)

### Colt Single Action Army (1873), .45 Colt — 6 rounds
- Single action: the hammer is thumbed back between shots (~0.35 s).
- Fanning (hold RMB): fast, very inaccurate fire.
- Reloading, per chamber: hammer at half-cock and loading gate open, then for
  each chamber the ejector rod pushes out the spent case and a fresh round goes
  in. Slow, and it can be stopped at any point. Closing the gate cocks it again.
- Damage 2 · fast bullet · medium range.

### Coach gun — side-by-side 10-gauge double, external hammers, two triggers
- LMB fires one barrel (right, then left). RMB fires both barrels together.
- 9 buckshot pellets per barrel with a wide spread. Deadly up close, weak at range.
- Reloading: break open, pull spent shells, load two shells, close (cocks the hammers).
- Pellet damage 1 · short range · loudest weapon.

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
- **The posse**: once five or fewer bandits are left, the survivors band together
  instead of waiting at their posts at the far end of town. The steadiest man (by
  rank, then whoever is nearest the others) calls "To me, boys!" and they gather
  on him; anyone mid-fight or mid-search finishes first and then falls in. They set
  off when all are within ~70 px of him, or after 30 s with whoever has come. The
  leader walks from street to street, always to the nearest of the spots they've
  seen least lately, so the whole town gets swept rather than the same streets
  twice; he pauses 1.5–3 s at each and waits for stragglers. The others keep their
  slots behind and beside him, each watching his own side (left, right, the rear)
  whenever they stop. A fight breaks the formation as usual, and once the search
  that follows is over each man falls back in on the leader. If the leader dies, the
  next man takes over. `tests/test_posse.gd` checks they gather, stay together,
  cover most of the town and re-form after a fight.
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
| Pistolero | poncho, sombrero (3 serapes) | Colt | rank and file, often breaks under fire |
| Cowboy | vest, bandana (3 palettes) | Colt | steady mid-range gunman |
| Rifleman | duster, bowler (2) | Winchester + Colt | good shot, leader (orders covering fire) |
| Red Scarf | vest, red scarf | coach gun + Colt | rushes in, fires on the move |
| El Jefe | red duster, sombrero | coach gun + Colt | 4 HP, nerves of steel, leader |
| Drunkard | shirt, suspenders, slouch hat (2) | Colt | wild aim, slow, scared, slurs |
| Gambler | frock coat, top hat (2) | Remington derringer | quick hands, cool head |
| Saloon girl | dress and shawl (3) | derringer (3 in 4) or Colt | opportunist, passes as townsfolk until something's up |
| Poacher | buckskin, fringe, coonskin cap, beard (2) | Sharps 1874 | sniper: very long range, deadly, slow single-shot reload |
| Old timer | old cavalry coat, slouch hat, white beard (Union / Confederate) | howdah pistol | 3 HP, slow, unshakeable, "Seen worse at Shiloh!" |
| Gunslinger | black (or tan) vest, red scarf, flat hat, two holsters (2) | a pair of Colts | bold: walks in shooting, fast, scorns cover, "Draw, stranger!" |
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
**sawn-off** is a double 12-gauge cut down to a pistol grip and stubby barrels: the
coach gun's shells and volley, a much wider pattern (15 degrees) that is spent by
~115 px, and a quicker reload. It's carried at the hip like the coach gun, and a
blast from it up close throws a man back just the same (`tests/test_hillbilly.gd`
checks a hillbilly closes to its range and fights nearer than a cowboy).

Guns are data too (`Weapon.DATA` in `scripts/weapon.gd`): an action type (revolver,
lever, or breech for anything that opens to load), stats, smoke, and for breech guns
the barrel count and each reload step's time and sound. A new breech gun is a data
entry plus a model and poses in `tools/chars.py`. `tests/test_types.gd`
checks the type data against the baked art.

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
- **Couples**: two placements sharing a `couple` id stroll together while all is
  calm: the first leads (with a long `wander`), the second walks on his arm,
  finding her way round anything in the way, and he waits if she falls behind.
  At the first shot each runs for it alone; back out, they pair up again.
- **Innocents**: townsfolk are hit by stray rounds from either side, and bandits
  hold fire when one is in the line. If the hero kills one, the town notices: "AN
  INNOCENT - the town will remember", witnesses shout "Murderer!" and run, and the
  end card counts them ("innocents shot: 2"). No other penalty yet.
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
scatter at a shot. `tests/test_perf.gd` times a firefight with and without the townsfolk.

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
  to. Frames are trimmed and packed into one atlas per character; metadata gives
  each frame's rectangle and offset, each legs frame's hip height and each aiming
  frame's muzzle point.

## Tech

- Godot 4 (GDScript). The world is built in code from `data/town.json`.
- Gameplay runs on the screen-space ground plane. Bullets and sight lines are
  tested at foot level and drawn at gun height.
- Pathfinding: `AStarGrid2D` on a half-tile grid.
- All art and sound are generated by `tools/gen_assets.py`, which uses a small
  point-splat 3D renderer for 8-direction sprites and synthesises the sound
  effects. Every asset can be swapped for hand-made art later.
