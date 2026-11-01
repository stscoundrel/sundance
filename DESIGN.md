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
| 1 / 2 / 3, wheel | Colt / coach gun / Yellow Boy (the ones he has) |
| E | Knife: a silent takedown from behind, or a rush |
| Enter | Restart after win or loss |
| Esc | Quit |

## Hero

Long dusty duster, flat-brimmed wide hat, cigarillo, gunbelt and a shell
bandolier. 6 HP: revolver and rifle hits deal 2, buckshot pellets deal 1, so
he survives two clean hits. No health pickups.

Crouching: half speed, silent footsteps, tighter spread and a smaller visual
profile (see Stealth).

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

**Loadout and loot.** After the title card the stranger chooses his irons: any of
the Colt, the coach gun and the Winchester, at least one (1 2 3 or a click to take
or put back; Enter or "ride in"; all three are allowed for now, for testing, and
`LOADOUT_SIZE` in `game.gd` limits it). The choice is kept across restarts. He
rides in with those and their belts of cartridges. Any of the three a dead man
drops is his for walking over it, part-spent as it was left; a gun he already has,
or one he can't use yet (derringer, Sharps, howdah, sawn-off), stays where it lies,
and the gunsmith may get to it first. Cartridges for a gun he hasn't got still go
in his belt, ready for when he finds one. Three small slots over the gun panel show
which he has (the one in hand outlined), and a line there says what he picked up.
`tests/test_loadout.gd` covers the screen, the switching, and picking guns up.

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
  Not yet: throwing it back, shooting the stick, the stranger carrying it.
  `tests/test_dynamite.gd` covers who carries it, when it's thrown, the blast, and
  the dropped and fumbled stick.
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
| Bandido | peasant whites, straw sombrero, bandolier, coloured sash (3) | Colt Navy (cap-and-ball) | 1 HP, poor aim, thin nerve, slow to react; dangerous for six shots, then an age reloading |
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
**Colt Navy 1851** is the old cap-and-ball revolver the bandidos carry: six shots,
damage 1, a fog of black-powder smoke, and no cartridges. Each chamber is charged
with powder and ball, rammed and capped, so a full reload takes about 11 s (a
Colt's ~4.5): empty, a bandido is a sitting duck. It leaves nothing for the
stranger to take. Revolver reload steps are data (`eject`, `insert` per gun). The
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
- **Shutters**: every glazed window on the wooden buildings and every small window
  on the adobes has a pair of shutters (weathered planks on the wood, painted
  turquoise, blue, green or oxblood on the adobes; one colour per building, picked
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
