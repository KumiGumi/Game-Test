# Warden — combat feel prototype

A side-on 2D feel prototype. It exists to answer one question:

> Does commitment-based combat — animation lock, counter windows, stagger
> checks — feel good in a side-view bullet-pattern space?

Not a game. No art, no audio, no menus, no networking, no progression.
Colored shapes only. All names are original.

Godot 4 / GDScript. Open the project folder in Godot and press F5.

---

## Status: step 3 of 5

| # | Step | State |
|---|------|-------|
| 1 | Movement, dash i-frames, action economy, side-on view | **done** |
| 2 | Boss state machine, filler patterns, telegraph system | **done** |
| 3 | Knockback + ledges, the counter, the stagger check | **done** |
| 4 | Wipe mechanic, HP-gated mechanics, phase change, enrage | not started |
| 5 | Full debug tooling pass | not started |

**Not yet built:** four more filler combos (quad slam, enhanced axe strike with
the glow/no-glow read, anchor, jump+cross), and the HP-threshold scheduler that
should fire mechanics at fixed HP rather than rolling them from the pool.

## Controls

| Input | Action |
|-------|--------|
| WASD | move |
| Mouse | aim |
| **RMB** | auto attack (hold) |
| 1–4 | skills |
| Space | dash |
| **F** | Overheat |
| Tab | switch variant |
| **Numpad 1–8** | force boss pattern N (pulled forward from step 5) |
| **Numpad / and \*** | break the left / right platform |
| **Numpad 0** | restore the floor |
| F5 / Backspace | instant restart |

## The action economy

Built around a two-long-casts-plus-fillers rhythm rather than six equal buttons.

| Input | Skill | Cast | CD | Notes |
|---|---|---|---|---|
| RMB | Staff | 0.26s | — | one press, one shot |
| 1 | Frostfall | **instant** | 6s | 8 impacts over 2.4s |
| 2 | Riposte | **instant** | 9s | the **counter** |
| 3 | Emberlance | 1.20s | 10s | first long cast |
| 4 | Starfall | 1.80s | 24s | second long cast, big stagger |
| Space | Dash | — | 7s ×2 | 0.3s i-frames |
| F | Overheat | — | meter | burst window |

Four things make this feel like a rotation instead of a cooldown queue:

- **Auto attack fills every gap.** One press, one shot. No cooldown, holdable
  (`AUTO_HOLD_REPEAT`), and it's the main way the Overheat meter charges — so
  the correct thing to do between casts is never "stand still".
- **Cast queuing.** Press 4 during 3's cast and it fires the instant 3 finishes,
  with zero gap. The queued input survives the whole remaining cast instead of
  expiring like a normal input buffer, and it skips the recovery frames. That
  3 → 4 chain is the signature of the build.
- **Instants are genuinely instant** but still carry recovery, so instant does
  not mean free. The counter has to be instant — a counter you have to cast is
  not a counter.
- **Multi-hit beats single-hit.** Frostfall drops eight separate impacts over
  2.4 seconds rather than one number. Damage numbers scale with hit size, so a
  stream of small ones and one big one read differently at a glance. Both
  instants visibly originate from the player — a muzzle burst at the body, and
  shards that arc out and land exactly as each impact fires, so the rain reads
  as something *you* did rather than weather.

### Overheat (identity)

Fills from landing hits — autos and the multi-hit rain charge it fastest. At
100%, F converts it into a 10s window that **wipes every cooldown instantly**,
cuts cast times to 60% and raises damage 35%. It's the payoff that makes the
committed casts worth their cost, and later it's what you save for a phase.

This one is a **proposal** — you said you weren't sure how to fit the mode in.
It's on its own key, off the number row, with a meter above the hotbar and an
aura on the player. If you'd rather it were a passive threshold, a toggle, or
gone, it's one section of `tuning.gd` and one function in `player.gd`.

## The Warden

A finite state machine that picks its next pattern from a weighted pool:

```
IDLE -> REPOSITION -> PATTERN -> RECOVER -> IDLE
                         ^
                 STUNNED / DEAD cut in
```

IDLE and RECOVER are the beats that let the fight breathe. REPOSITION drifts it
to a new spot near the player so it isn't a static turret check. The same
pattern never rolls twice in a row while an alternative exists.

Every attack is WIND-UP → ACTIVE → RECOVERY, drawn as a ground shape with a
static outline at full extent (so the safe spot is readable from frame one) and
a fill that sweeps to tell you *when*.

| # | Pattern | Shape | The read |
|---|---------|-------|----------|
| 1 | CLEAVE | cone | tracks you for the first half of the wind-up, then **commits** — the read is *when it stops following*, not where it points |
| 2 | PULSE | circle on the boss | safe zone is **outside**: get out |
| 3 | RING | donut on the boss | the exact inverse — safe zone is **at melee**: run *toward* the thing winding up |
| 4 | LANCE | rectangle | telegraphed lane, then it dashes down it. Multi-hit, so the lane stays lethal for the whole dash rather than only on the frame it goes live |
| 5 | CROSS | four rects | axe slam into an X of shockwaves. Arms start at the boss, so melee is inside all four — the answer is to be out in a **gap** |
| 6 | TRIPLE SWING | 3 cones | front, behind, front. Three beats in one pattern, so it's answered by moving *twice*; the second swing catches anyone who rolled straight through |

2 and 3 exist as a pair. Either alone has a dominant answer ("stay at range");
together they make range a decision you re-make every wind-up. 5 pushes the
other way again — RING wants you at melee, CROSS wants you out in a gap.

| 7 | SUNDER CHARGE | slams + lane | **the counter.** Three slams on a fixed beat, then a charge |
| 8 | OVERBEAR | channel | **the stagger check.** Fill the bar or take a huge shove |

**No bullet-hell patterns.** Every pattern is a placed ground shape with a
wind-up, the way a Lost Ark boss actually works — not a projectile field you
weave through. An earlier spiral-of-projectiles pattern was cut for exactly
this reason.

### One indicator, one verb

The fight is meant to read like a rhythm game: *go in, get out, dodge, in then
out, go behind, stand in a place.* So every pattern carries a `verb` in tuning —
GO IN, GET OUT, FIND A GAP, GO BEHIND, COUNTER IT — and the HUD prints it under
the boss bar while the wind-up runs. It is a design constraint as much as a
readout: **if a pattern can't be named with one verb, the pattern is the
problem.**

### The counter

Three slams on a fixed beat, then a charge down a lane he locked in before the
first slam. The window opens on the **second** slam and only on his **front
arc**, so the answer is to run into his face on beat two — the most committal
movement in the fight, on a rhythm you have to learn. Land it and he's knocked
down for 3s. Miss it and the charge shoves you the better part of a dash length,
which near a broken ledge is death rather than damage.

### The stagger check

He channels for 6s; fill the bar or eat a ~300-unit shove. The bar does **not**
decay during a check — the timer is the pressure, not leakage. It's tuned to
want the big cast, so spending Starfall on filler a moment earlier is a real
mistake rather than a rounding error.

## Knockback, ledges and falling

This is the fight's identity, not a detail: **everything he does pushes you, the
stage is small, and once a platform breaks you can be shoved into the void.**

- Every boss hit carries a knockback value, tuned in world units so it can be
  compared against the 215-unit dash. A failed stagger check moves you ~300.
- Knockback decays at a **constant** rate, so a push travels a finite, knowable
  distance. (It was briefly exponential, which meant drifting toward the edge
  forever — a genuinely bad property on a stage with ledges.)
- Getting knocked out of a cast still costs you the cooldown. Being hit is not a
  free reset.
- The floor is two rects: `arena_rect` (outer bounds, nothing walks past) and
  `floor_rect` (the solid part). A platform break shrinks the second, and the
  gap between them is a hole. **i-frames don't save you** — they stop damage,
  not gravity, which is what makes a ledge scarier than a hitbox.
- Falling is lethal and restarts the run (`Tune.FALL_IS_LETHAL`).

### Patterns are coroutines

Attack choreography reads as a script — wind up, fire, pause, fire again — and
is miserable as a step table, so each pattern is an `await`-driven function.
The hard part of that approach is interruption, and it's solved with a **run
token**: every abort bumps `_run_token`, and every wait site checks it, so a
pattern dies within one frame of being cancelled by a counter stun, a phase
change, or the numpad. Telegraphs a dying pattern left behind are cancelled
with it, and a pattern that has been superseded is not allowed to drag the boss
out of the state it was interrupted into.

## The variant toggle

Now that the loadout is 2 instants + 2 casts + autos, the Commit/Flow A/B is
narrower than it was: it only changes what the **cast-time** skills cost you.
Instants and autos are untouched — they were never the commitment.

- **COMMIT** — casts root you completely, aim locks at cast start, full damage.
- **FLOW** — move at 50% while casting, aim keeps tracking, 55% cast time, 70%
  cast damage.

**Dash-cancelling** a cast gets you out, but the skill still goes on cooldown —
`Tune.CANCEL_COOLDOWN_FRACTION` controls how much you pay (1.0 = the whole
cooldown for nothing). Set it to 0.0 to feel a version with no commitment.

## The side-on view

Rabbit-and-Steel style: **not** a platformer. Movement is still free 2D on a
flat arena — there's no gravity and no jumping. The world is flat (`x` = across,
`y` = **depth**), and the camera is a projection: screen `y` = world `y` ×
`VIEW_SQUASH`.

That one transform does the work. The ground layer carries the squash as a node
scale, so every telegraph drawn in it becomes a ground ellipse with no
per-shape code, while gameplay maths stays flat 2D — a distance test is still a
distance test. Actors sit in an unscaled layer and place themselves through
`View.to_screen()`, so characters stand upright with shadows at their feet.

Turn `Tune.VIEW_SQUASH` up to 1.0 and it's top-down again, with no other change.

## Tuning

Every number lives in [`scripts/tuning.gd`](scripts/tuning.gd). Timings, damage,
cooldowns, cast times, speeds, radii, stagger, the view angle, colors. Nothing
is hardcoded in a node and nothing is buried in a scene — `main.tscn` is a
single node with a script and no properties.

## Architecture

**`View`** — world ↔ screen projection plus the layer registry. The only place
that knows the camera is angled.

**Layers.** `z_index` in Godot is *relative to the parent* unless
`z_as_relative` is off, so the Arena root sits at z 0 and every layer states its
own depth (`Tune.Z_*`): backdrop −100, ground −10, telegraphs −15, actors 0.
Drawing the backdrop on the root instead meant the root needed a low z, which
dragged the ground layer below the floor and painted every AoE indicator
underneath the stage. There's a regression test for it.

**`AtkShape`** — one geometry object (circle / donut / cone / rect) that serves
as *both* the telegraph drawing and the hitbox test. No physics in this project:
no `Area2D`, no collision layers. One player, one boss, both circles, so hits
resolve analytically — frame-exact, deterministic, and the debug visualiser can
draw exactly the shape the game tested against.

**`Telegraph`** — owns WIND-UP → ACTIVE → RECOVERY for one `AtkShape`, and
pulses `activated` N times if `hits > 1`, so a rain or a channel is one
telegraph rather than many. Doesn't know who it hurts; the spawner connects and
resolves. Player skills and boss attacks share it, so every hitbox in the game
passes through one choke point.

**`Actor` / `Hostile`** — world-positioned things. `Hostile` owns a static
registry of live targets so damage code never names the Arena.

**`Events`** — autoloaded signal bus.

**Boss FSM (step 2)** — outer states `IDLE → REPOSITION → PATTERN → RECOVER`,
plus `STUNNED` and `DEAD`; weighted-random selection from a pool mutated in
place at the 50% phase change. Patterns are `await`-driven coroutines, because
attack choreography reads as a script and is miserable as a step table.
Interruption (counter stun, debug force-pattern, phase change) uses a run token:
`await ctx.wait(t)` returns `false` if the token moved, so every await site is a
one-line bail.

## Headless tests

```
godot --headless --path . tests/smoke.tscn --quit-after 40000
```

Exits non-zero on failure. 137 checks: `AtkShape` containment for all four
shapes, the view projection round-trip, one-press-one-shot autos, instants
staying instant, the rain landing spread over its duration (not all at once),
cast queuing outliving the input buffer, dash-cancel, i-frames, Overheat, the
variant rules, multi-hit telegraph pulses, every boss pattern running to
completion and releasing the FSM, **an aborted pattern's telegraph never going
live**, PULSE hurting at melee while RING does not, boss death, restart,
knockback travelling a finite predicted distance, platform breaks, falling being
lethal, the counter window being directional (front yes, behind no), and the
stagger check not leaking.

```
godot --headless --path . tests/dps_sim.tscn --quit-after 60000
```

A DPS bench. Runs a priority rotation against a parked boss for 60s and prints
sustained DPS plus the implied time-to-kill, so `WARDEN_MAX_HP` can be sized
against the enrage timer instead of guessed. Current reading: **355 DPS**, which
puts 70,000 HP at a 3.3-minute kill.

Both are here because a feel prototype gets its numbers rewritten constantly and
a parse error shouldn't cost a play session.
