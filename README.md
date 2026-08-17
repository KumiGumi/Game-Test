# Warden — combat feel prototype

A side-on 2D feel prototype. It exists to answer one question:

> Does commitment-based combat — animation lock, counter windows, stagger
> checks — feel good in a side-view bullet-pattern space?

Not a game. No art, no audio, no menus, no networking, no progression.
Colored shapes only. All names are original.

Godot 4 / GDScript. Open the project folder in Godot and press F5.

---

## Status: step 1 of 5

| # | Step | State |
|---|------|-------|
| 1 | Movement, dash i-frames, action economy, side-on view | **done** |
| 2 | Boss state machine, patterns 1–5, telegraph system | not started |
| 3 | Counter (pattern 6) and stagger check (pattern 7) | not started |
| 4 | Wipe mechanic (8), 50% phase change, enrage timer | not started |
| 5 | Full debug tooling pass | not started |

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
| F5 / Backspace | instant restart |

## The action economy

Built around a two-long-casts-plus-fillers rhythm rather than six equal buttons.

| Input | Skill | Cast | CD | Notes |
|---|---|---|---|---|
| RMB | Staff | 0.24 / 0.22 / 0.30s chain | — | 3-step, finisher is a small blast |
| 1 | Frostfall | **instant** | 6s | 8 impacts over 2.4s |
| 2 | Riposte | **instant** | 9s | the **counter** |
| 3 | Emberlance | 1.20s | 10s | first long cast |
| 4 | Starfall | 1.80s | 24s | second long cast, big stagger |
| Space | Dash | — | 7s ×2 | 0.3s i-frames |
| F | Overheat | — | meter | burst window |

Four things make this feel like a rotation instead of a cooldown queue:

- **Auto attack fills every gap.** No cooldown, holdable, and it's the main way
  the Overheat meter charges — so the correct thing to do between casts is
  never "stand still".
- **Cast queuing.** Press 4 during 3's cast and it fires the instant 3 finishes,
  with zero gap. The queued input survives the whole remaining cast instead of
  expiring like a normal input buffer, and it skips the recovery frames. That
  3 → 4 chain is the signature of the build.
- **Instants are genuinely instant** but still carry recovery, so instant does
  not mean free. The counter has to be instant — a counter you have to cast is
  not a counter.
- **Multi-hit beats single-hit.** Frostfall drops eight separate impacts over
  2.4 seconds rather than one number. Damage numbers scale with hit size, so a
  stream of small ones and one big one read differently at a glance.

### Overheat (identity)

Fills from landing hits — autos and the multi-hit rain charge it fastest. At
100%, F converts it into a 10s window that **wipes every cooldown instantly**,
cuts cast times to 60% and raises damage 35%. It's the payoff that makes the
committed casts worth their cost, and later it's what you save for a phase.

This one is a **proposal** — you said you weren't sure how to fit the mode in.
It's on its own key, off the number row, with a meter above the hotbar and an
aura on the player. If you'd rather it were a passive threshold, a toggle, or
gone, it's one section of `tuning.gd` and one function in `player.gd`.

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

## Headless smoke test

```
godot --headless --path . tests/smoke.tscn --quit-after 6000
```

Exits non-zero on failure. 60 checks covering `AtkShape` containment for all
four shapes, the view projection round-trip, the auto-attack chain, instants
staying instant, the rain landing spread over its duration (not all at once),
cast queuing outliving the input buffer, dash-cancel, i-frames, Overheat, the
variant rules, multi-hit telegraph pulses, and restart. It's here because a feel
prototype gets its numbers rewritten constantly and a parse error shouldn't cost
a play session.
