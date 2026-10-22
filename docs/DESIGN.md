# Sprint Slam — Design & Architecture

**RUN. BOOST. SLAM. REPEAT.**

A solo-attempt arcade sprint: 45 seconds to run a short neon course, build momentum,
launch off a ramp, and slam into a giant vertical target. Speed sets the base score,
precision sets the multiplier.

---

## 1. Concept analysis

The whole game hangs on one tension: **speed versus precision.**

- Speed comes from clean movement: carving instead of snap-turning, chaining dashes into
  boost pads, landing jumps cleanly, sliding down slopes.
- At the end of the course, all that speed becomes launch velocity. During the slam flight
  you steer a reticle onto the target. Fast launches score more, but leave less time to aim.
- The target multiplier (1x / 1.5x / 2x / 3x) means a precise slow run can beat a sloppy
  fast one, and a run that is both fast and precise wins by a lot.

The **slam flight** is what makes the final slam a skill rather than a dice roll:

1. Launching off the lip turns approach speed into launch speed (`x1.45`, clamped 70–150).
2. The flight uses its own gravity (20 st/s²) and a fixed 18° pitch. A natural, unsteered
   trajectory hits the bullseye at about 105 st/s launch, too low when slower, too high when faster.
3. The player steers with the move input (limited acceleration). A reticle shows where they
   will hit if they stop steering.
4. **Slam Dash**: one in-flight dash that adds 15–35% speed. It is worth more the earlier you
   use it, but it flattens your arc and cuts steering to 35%. Committing early is the
   high-skill play.

Every run ends at the wall, so no run ends without a score.

## 2. Technical challenges

| Challenge | Approach |
|---|---|
| Momentum on top of Roblox `Humanoid`, which snaps to `WalkSpeed` instantly | Client keeps its own `speed` value and drives `WalkSpeed` from it every frame. Steering is smoothed by overriding `Humanoid:Move` after the default ControlModule, with turn rate falling as speed rises. That gives carving, plus braking on reversals. |
| Dash/boost impulses fight the Humanoid controller | Boosts are added to the momentum model (`speed`, `dashBoost`) rather than raw impulses, so the Humanoid controller *applies* them for us. Only jump pads and knockbacks write velocity directly. |
| Deterministic, controllable launch | During flight the Humanoid is `PlatformStand`. A `LinearVelocity` constraint follows our own integrated velocity, and an `AlignOrientation` holds a Superman pose. |
| Client-owned physics vs. anti-cheat | The server never trusts client numbers alone. It samples every runner's root position at 20 Hz, checks gate crossings in order, enforces speed plausibility, and does its own impact-plane detection. Client claims are used **only when they agree with** what the server saw (`min(claim, observed × 1.12, physicsCap)`). |
| Latency on timers | All timers use `workspace:GetServerTimeNow()`. Client time claims are accepted only within `ping + 0.1 s` of what the server observed. |
| Combo bonus is client-driven | Server re-tallies combos with the shared `ComboTracker`. It rate-limits each event type, requires proximity to the relevant pad or ring for pad events, awards shortcut combos itself, and caps the total. |
| Moving obstacles stutter if replicated | Obstacles are anchored. Every client animates them locally from a deterministic function of server time, so they stay smooth and stay in sync (this is also needed for ghosts later). |
| Instant restart without rubber-banding | The client teleports itself immediately (it owns its physics). The server resets its sample history and expects the next sample to be near a valid respawn point. |
| Other players must not interfere | Collision group `Runners` does not collide with itself. |
| Procedural daily courses must be safe | Courses are **data** (`Shared/Courses/*`). Platforms, pads, rings, obstacles, checkpoints, launch and target are all declared in a table. The daily system (Phase 5) rotates validated templates and seeds only safe parameters (pad placement among fixed slots, obstacle phase/period). |
| Low-end devices | Effects are client-side and scale with the quality level. No per-frame instance creation. Course geometry is plain parts with no unions. |

## 3. Authority model

```
CLIENT (owns character physics)                SERVER (authoritative)
──────────────────────────────                 ──────────────────────
MovementController  speed/steer/slide/jump     RunSessionService  state machine per player
DashController      dash + cooldown            RunValidator       20 Hz samples, gates,
CourseController    pads/rings/obstacles/kill                     speed plausibility, impact
SlamController      flight, reticle, impact    ScoreService       ScoreFormula + combo re-tally
RunController       client run state      ───► CourseManager      builds course from data
UIController        HUD / countdown / results
       │  RequestRestart / RequestRespawn / ComboEvent / ImpactClaim
       └──────────────────────────────────────►
       ◄────────── RunState / Checkpoint / RunResult
```

The client predicts everything so it feels instant: countdown, timer, combos, impact FX,
and a provisional zone. The server's `RunResult` is the only score that counts.

## 4. Project structure (Rojo layout)

```
default.project.json             Rojo mapping (also used by tools/build-place.js)
src/
  shared/   → ReplicatedStorage.Shared
    Config.luau                  ALL tuning values (movement, dash, slam, score, validation)
    ScoreFormula.luau            pure scoring function (server + client preview)
    ComboTracker.luau            pure combo chain logic (server + client)
    Geometry.luau                plane crossings, OBB tests, path projection
    Net.luau                     RemoteEvent registry
    Signal.luau                  tiny signal class
    Courses/
      init.luau                  course registry
      NeonRush.luau              Phase 1 course (data)
  server/   → ServerScriptService.Server
    Main.server.luau             bootstrap
    Services/
      WorldSetup.luau            lighting, collision groups, player defaults
      CourseManager.luau         builds course parts from a definition
      RunSessionService.luau     per-player run state machine + remotes
      RunValidator.luau          sampling, gate crossing, plausibility, impact detection
      ScoreService.luau          authoritative scoring, session bests
  client/   → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau             bootstrap + single ordered update loop
    Controllers/
      InputController.luau       keyboard / gamepad / touch bindings
      MovementController.luau    momentum, carving, slide, landings, collisions
      DashController.luau        dash, cooldown, dash FX
      CourseController.luau      pads, rings, obstacles, kill plane, launch trigger, progress
      SlamController.luau        flight physics, steering, reticle, impact FX
      CameraController.luau      FOV by speed, trauma shake, flight camera
      ProceduralPose.luau        slide / flight poses via Motor6D.Transform
      EffectsController.luau     trails, speed streaks, bursts
      RunController.luau         client run state machine
      UIController.luau          HUD, SLAM MODE, countdown, results
      DevAutopilot.luau          Studio-only QA bot that drives full runs through real input
  tests/    → ServerStorage.Tests      spec modules for pure shared logic
tools/
  build-place.js                 zero-dependency .rbxlx builder; --serve exposes a sync manifest
  studio-sync.luau               pulls that manifest into an open Studio place (no Rojo needed)
```

Future services slot into the same structure: `GhostReplayService`, `LeaderboardService`,
`DailyChallengeService`, `ProgressionService`, and `TeamService` on the server, plus
matching client controllers.

## 5. Phased plan

### Phase 1 — Core prototype (this milestone)
- Momentum movement: acceleration curve, carving turn-rate limit, reversal braking, collision
  speed loss, slope gain/loss, slide (+drift), jump with perfect-landing window.
- Dash: cooldown, boost-chain timing window, air dash, cooldown refresh from pads/rings.
- Course "Neon Rush": runway with boost pads, jump gap, split section (moving blocks vs. an
  elevated shortcut beam reached by a jump pad), downhill speed ramp, S-bend, pillar gauntlet
  (weave it or thread a 3-stud straight line), gap with an apex-timing boost ring, slam runway,
  launch ramp, and target wall.
- Slam flight with steering, reticle, Slam Dash, and zones (Bullseye 3x / Inner 2x /
  Middle 1.5x / Outer 1x / Miss 0x).
- 45 s timer (stops at launch), 3 s countdown, instant restart (R / ButtonY / HUD button).
- Server validation and authoritative score breakdown; session personal best and splits.
- Functional HUD, basic impact FX (hit-stop, shockwave, burst, target pulse, shake, popup).
- Verification: spec suite for scoring/combos/geometry/server reconciliation, plus the Studio
  autopilot. It runs whole laps through the real input path, server scoring included.

### Phase 2 — Movement polish
Custom animation set (run cycles clamped by speed, slide, dash, flight), sound design via
`Sfx` IDs, a richer impact sequence (slow-mo tiers, target deformation), obstacle telegraphs,
broadcasting impacts to other players, and quality-scaled effects.

### Phase 3 — Competitive systems
DataStore personal bests, `GhostReplayService` (10 Hz snapshots with delta compression,
client-side interpolated playback, no collision), daily leaderboards (OrderedDataStore keyed
by `daily-YYYYMMDD`), and leaderboard ghosts.

### Phase 4 — Progression
XP and currency, speed titles (Rookie → Legendary, **cosmetic only**), trails, dash/impact
effects, poses, auras. `TeamService` scores teams from each member's best verified daily run.

### Phase 5 — Daily content
`DailyChallengeService`: UTC day index → seeded selection among validated templates, plus safe
parameter variation. Countdown to 00:00 UTC, practice mode for past courses (unranked).

## 6. Controls (Phase 1)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move / steer flight | WASD | Left stick | Thumbstick |
| Jump | Space | A | Jump button |
| Dash / Slam Dash | Shift or E | X | DASH button |
| Slide | Ctrl or C | B | SLIDE button |
| Restart | R | Y | ↻ button |
