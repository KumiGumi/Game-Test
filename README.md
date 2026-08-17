# Warden — combat feel prototype

A 2D top-down feel prototype. It exists to answer one question:

> Does commitment-based combat — animation lock, counter windows, stagger
> checks — feel good in a top-down bullet-pattern space?

Not a game. No art, no audio, no menus, no networking, no progression.
Colored shapes only. All names are original.

Godot 4 / GDScript. Open the project folder in Godot and press F5.

---

## Status: step 1 of 5

| # | Step | State |
|---|------|-------|
| 1 | Player movement, dash i-frames, the two cast variants, dummy target | **done** |
| 2 | Boss state machine, patterns 1–5, telegraph system | not started |
| 3 | Counter (pattern 6) and stagger check (pattern 7) | not started |
| 4 | Wipe mechanic (8), 50% phase change, enrage timer | not started |
| 5 | Full debug tooling pass | not started |

## Controls

| Input | Action |
|-------|--------|
| WASD | move |
| Mouse | aim |
| 1–6 | skills |
| Space | dash (same as 6) |
| Tab | **switch variant** — the whole point |
| R | instant restart |

## The comparison

Both variants share one skill list. Only the numbers change.

- **COMMIT** — 0.8–1.6s casts, movement fully locked, aim locked at cast start,
  full damage.
- **FLOW** — 0.2–0.5s casts, moves at 55% while casting, aim keeps tracking the
  cursor, 44% damage.

Switch mid-fight with Tab. The cast that's already in flight keeps the variant
it started under.

**Dash-cancelling** a cast gets you out, but the skill still goes on cooldown —
`Tune.CANCEL_COOLDOWN_FRACTION` controls how much you pay (1.0 = the whole
cooldown for nothing). Set it to 0.0 to feel a version of the game with no
commitment at all.

## Tuning

Every number lives in [`scripts/tuning.gd`](scripts/tuning.gd). Timings,
damage, cooldowns, cast times, speeds, radii, stagger values, colors. Nothing
is hardcoded in a node and nothing is buried in a scene — `main.tscn` is a
single node with a script and no properties. Edit, save, re-run.

## Headless smoke test

```
godot --headless --path . tests/smoke.tscn --quit-after 3000
```

Exits non-zero on failure. Covers `AtkShape` containment for all four shape
kinds, the cast → bolt → damage path, AoE shape resolution, dash-cancel (state,
cooldown charged, charge spent, i-frames), i-frame avoidance, the variant
switch, telegraph lifecycle, and restart. It's there because a feel prototype
gets its numbers rewritten constantly and a parse error shouldn't cost a
play session.

## Architecture

**`AtkShape`** — one geometry object (circle / donut / cone / rect) that serves
as *both* the telegraph drawing and the hitbox test. There is no physics in this
project: no `Area2D`, no collision layers. One player, one boss, both circles,
so hits resolve analytically — frame-exact, deterministic, and the debug
visualiser can draw exactly the shape the game tested against.

**`Telegraph`** — owns the WIND-UP → ACTIVE → RECOVERY lifecycle for one
`AtkShape`, draws it (static outline at full extent so the safe spot is
readable immediately, plus a fill that sweeps to communicate the timing), and
emits `activated` on the exact frame the hitbox goes live. It doesn't know who
it hurts; the spawner connects and resolves. The boss and the player's AoE
skills both use it, so every hitbox in the game passes through one choke point.

**`Events`** — autoloaded signal bus. Combat emits, HUD/DPS/juice listen.

**Boss FSM (step 2)** — outer states `IDLE → REPOSITION → PATTERN → RECOVER`,
plus `STUNNED` and `DEAD`; weighted-random pattern selection from a pool that
gets mutated in place at the 50% phase change. Each pattern is written as an
`await`-driven coroutine, because attack choreography reads as a script and is
miserable as a step table. Interruption (counter stun, debug force-pattern,
phase change) uses a run token: `await ctx.wait(t)` returns `false` if the token
moved, so every await site is a one-line bail.
