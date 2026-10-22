# Sprint Slam — Design & Architecture

**RUN. BOOST. SLAM. REPEAT.**

A solo-attempt arcade sprint: 45 seconds to run a short neon course, build momentum,
launch off a ramp, and slam into a giant vertical target. **The goal is to go as fast as
possible for the whole run**. Momentum sets how hard you hit the wall, and precision is a
bonus on top.

---

## 1. Concept analysis

### Momentum, not last-second speed

- **Momentum = your average horizontal speed over the whole run** (distance ÷ time since GO),
  measured by the server from its own position samples. Every second counts equally:
  bonks, respawns and slow sections anywhere cost momentum, and a burst at the end only
  counts for its share of the run.
- **Launch speed = momentum × 1.8** (clamped 70–155). Your speed at the lip does not matter.
  So easing off before the ramp does not buy a slower, easier flight, and a late sprint does
  not buy a fast one.
- **Impact speed = the speed you drive into the wall**: the launch's horizontal part, plus
  Slam Dash. Steering and gravity move you *along* the wall, so they never add to it.
- **Impact power = impact speed² ÷ 20.** Like impact energy, speed counts twice: 2× the
  momentum gives roughly 4× the power.

### Scoring

```
Slam score = Impact power × Zone        (Bullseye 2x · Inner 1.6x · Middle 1.3x · Outer 1x · Wall 0.5x)
Final      = Slam score + Time bonus (10/s left at launch) + Combo bonus (≤ 600)
Coins      = Slam score ÷ 40            (verified impacts only)
```

Accuracy is deliberately a narrow multiplier, so a fast run that only clips the outer ring
beats a slow, perfect bullseye. Measured with the QA bot:

| Run style | Momentum | Impact | Power | Zone | Final | Coins |
|---|---:|---:|---:|---|---:|---:|
| Sprint the whole run | 74 | 147 | 1074 | Bullseye | 2684 | 53 |
| Sprint, then ease off on the slam runway to aim | 50 | 99 | 486 | Bullseye | 1291 | 24 |
| Crawl, then sprint and dash the slam runway | 45 | 87 | 380 | Bullseye | 1107 | 19 |

### The slam flight

1. Launch at momentum-derived speed with a fixed 18° pitch and its own gravity (20 st/s²).
   An unsteered flight hits the bullseye at about 105 st/s launch (≈ 58 momentum). Slower
   runs drop low, faster ones fly high and must steer down with less time to do it.
2. The player steers with the move input (limited acceleration). A reticle shows where they
   will hit if they stop steering.
3. **Slam Dash**: one in-flight dash that adds 6–15% speed. It is worth more the earlier you
   use it, but it flattens your arc and cuts steering to 35%.

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
    Momentum.luau                run-average speed → launch speed → impact speed (server + client)
    Lobby.luau                   THE HUB data: plaza, portals, parkour challenges
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
      BuildKit.luau              part-building primitives shared by every world builder
      LobbyManager.luau          builds the hub from Shared.Lobby
      CourseManager.luau         builds course parts from a definition
      RunSessionService.luau     per-player session: hub ↔ Sprint Slam runs, remotes
      RunValidator.luau          sampling, gate crossing, plausibility, impact detection
      ScoreService.luau          authoritative scoring, session bests
      WalletService.luau         coin balances (DataStore, session fallback)
  client/   → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau             bootstrap + single ordered update loop
    Controllers/
      InputController.luau       keyboard / gamepad / touch bindings
      MovementController.luau    momentum, carving, slide, landings, collisions
      DashController.luau        dash, cooldown, dash FX
      Interactables.luau         pads, rings, moving obstacles for any world
      CourseController.luau      course kill plane, launch trigger, progress
      LobbyController.luau       hub portals, parkour challenge timing, falls
      SlamController.luau        flight physics, steering, reticle, impact FX
      CameraController.luau      FOV by speed, trauma shake, flight camera
      ProceduralPose.luau        slide / flight poses via Motor6D.Transform
      EffectsController.luau     trails, speed streaks, bursts
      RunController.luau         client state machine (hub and runs)
      UIController.luau          HUD, SLAM MODE, countdown, results
      DevAutopilot.luau          Studio-only QA bot that drives full runs through real input
  tests/    → ServerStorage.Tests      spec modules for pure shared logic
plugin/
  SprintSlamPreview.server.luau  Studio plugin: edit-time course preview (not saved with the place)
tools/
  build-place.js                 zero-dependency .rbxlx builder; --serve exposes a sync manifest,
                                 --install-plugin installs the preview plugin
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
- Momentum: run-average speed (server-measured) drives launch speed, impact power and coins.
- Course "Neon Rush": runway with boost pads, jump gap, split section (moving blocks vs. an
  elevated shortcut beam reached by a jump pad), downhill speed ramp, S-bend, pillar gauntlet
  (weave it or thread a 3-stud straight line), gap with an apex-timing boost ring, slam runway,
  launch ramp, and target wall.
- Slam flight with steering, reticle, Slam Dash, and zones (Bullseye 2x / Inner 1.6x /
  Middle 1.3x / Outer 1x / Wall 0.5x) applied to impact power.
- 45 s timer (stops at launch), 3 s countdown, instant restart (R / ButtonY / HUD button).
- Server validation and authoritative score breakdown; session personal best and splits.
- Coins from verified impacts (`WalletService`, DataStore-backed; session-only in unpublished places).
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

## 6. The Hub

Players spawn in THE HUB, a floating plaza. A run starts only by walking into the Sprint Slam
portal: the client asks, and the server checks that the player really is at the portal
before starting the countdown. **L** (or HUB) returns to the hub from any run state. New modes
add a portal entry in `Shared/Lobby.luau` plus a session handler; the two locked portals are
placeholders for them.

Parkour challenges (Sky Tower, Dash Gaps, Beam Run) are data: a start box, a finish box, a
respawn and a fail line. The timer starts when you leave the start box. Falling below the
fail line returns you to the start, and walking back onto the plaza cancels the attempt.
Times are client-side session bests for now; leaderboards come with Phase 3.

## 7. Controls (Phase 1)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move / steer flight | WASD | Left stick | Thumbstick |
| Jump | Space | A | Jump button |
| Dash / Slam Dash | Shift or E | X | DASH button |
| Slide | Ctrl or C | B | SLIDE button |
| Restart run / challenge | R | Y | RESTART button |
| Back to the hub | L | Select | HUB button |
