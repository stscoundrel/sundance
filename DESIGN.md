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
- **Reactions** (the cinematic beats). Gunfire nearby, a round cracking past, dirt
  kicked up at his feet, a wound or a comrade dropping beside him makes each bandit
  roll a reaction from his nerve, each after his own short delay so a group never
  reacts in unison:
  - *point* and shout ("¡Allí está!"), held 1.5–4.5 s;
  - *flinch*, at least 1 s;
  - *cower* with hands on the hat for 2–4 s, then scramble to cover and hide;
  - *dash* for cover, crouch there 1.5–3 s (or back away if there is none);
  - or keep fighting (steady bandits mostly; El Jefe almost always).
  A wounded bandit staggers for almost a second. `tests/test_reactions.gd` checks the
  hold times.
- **Spreading out**: each bandit joining a fight takes his own flanking angle and
  holds a spot around the stranger at his weapon's range, instead of filing in behind
  the others. Comrades push apart when they get too close, and a bandit holds fire
  and sidesteps when a comrade is in his line of fire.
- **Animation**: sheets carry named animations (idle, walk, crouch, crouch-walk,
  point, flinch, cower with hands on the hat, hurt, firing recoil, fall, dead),
  listed in `assets/meta.json`. Add a pose in `tools/chars.py` and a column name to
  `COLS`, and the game picks it up.
- Enemy aim and rate of fire are tunable at the top of `scripts/enemy.gd`
  (`AIM_SPREAD`, `AIM_SPREAD_SHOTGUN`, `CADENCE_MULT`).
- Bandit types:
  - *Pistolero* — poncho and sombrero, Colt.
  - *Rifleman* — duster and bowler, Yellow Boy, long-range sentry.
  - *Red Scarf* — Corbucci-style gang scarf, coach gun.
  - *El Jefe* — the boss in a red coat, coach gun, takes 4 HP.

## World

- 2:1 isometric diamond tiles. Sprites are rendered at 3× detail (96×48 px per tile)
  and shown through a close camera (about 13 tiles across) in a 1280×720 view, scaled up by whole numbers with no smoothing, in a
  maximised window.
- Buildings are solid (no interiors in v1). They fade when the hero walks behind them.
- **Town**: a main street crossed by a side street. On it: a false-front saloon,
  general store, sheriff's office, bank, adobe houses, a church with a bell tower,
  stable, water tower, gallows, and a boot hill with crosses and a coffin.
  Wagons, crates, barrels, hitching posts, troughs, cacti, tumbleweeds, mud.

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
  game slows briefly while an extreme close-up of his eyes crosses the screen.
- Sound: gunshots with a whip crack and a long canyon tail with slap-back echoes
  (three takes per gun); struck-metal mechanics such as the Colt's four cocking
  clicks, the Winchester's lever and brass tinkling onto the boards.
- HUD: Colt cylinder showing each chamber, the coach gun's two barrels, a
  Yellow Boy round counter, health pips and bandits remaining.

## Tech

- Godot 4 (GDScript). The world is built in code from `data/town.json`.
- Gameplay runs on the screen-space ground plane. Bullets and sight lines are
  tested at foot level and drawn at gun height.
- Pathfinding: `AStarGrid2D` on a half-tile grid.
- All art and sound are generated by `tools/gen_assets.py`, which uses a small
  point-splat 3D renderer for 8-direction sprites and synthesises the sound
  effects. Every asset can be swapped for hand-made art later.
