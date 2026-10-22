# Sprint Slam

**RUN. BOOST. SLAM. REPEAT.** You get 45 seconds to sprint a neon course, build momentum,
launch off the ramp, and slam into a giant target. Speed sets your base score; precision
sets the multiplier.

The full concept analysis, technical challenges, architecture and phased roadmap are in
[docs/DESIGN.md](docs/DESIGN.md).

## Status

**Phase 1 — Core prototype.** One complete course (Neon Rush) with momentum movement, dash,
slide, boost pads, jump pad shortcut, moving obstacles, slam flight with steering and Slam
Dash, zone scoring, server validation, session bests and instant restart.

## Running it

No tooling is required:

```bash
node tools/build-place.js
```

Then open `build/SprintSlam.rbxlx` in Roblox Studio and press **Play**. The course is built
from data at runtime, so it only appears in play mode.

For live sync without Rojo, keep `node tools/build-place.js --serve` running and run
[tools/studio-sync.luau](tools/studio-sync.luau) from Studio's command bar after each change.
It switches HTTP on only for the fetch. With [Rojo](https://rojo.space) installed,
`rojo serve` uses the same `default.project.json`.

## Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move / steer flight | WASD | Left stick | Thumbstick |
| Jump | Space | A | Jump |
| Dash / Slam Dash | Shift or E | X | DASH |
| Slide | Ctrl or C | B | SLIDE |
| Restart | R | Y | RESTART |

## Tuning

Every gameplay number lives in [src/shared/Config.luau](src/shared/Config.luau): movement,
dash, slam flight, target zones, scoring, combos and validation tolerances.

## QA autopilot (Studio only)

During a playtest, run this in the client command bar to have a bot drive full laps through
the real input path (stick, jump, dash, slide, flight steering, Slam Dash). It logs splits,
launch, impact and the server's verdict:

```lua
game.Players.LocalPlayer:SetAttribute("Autopilot", true)
game.Players.LocalPlayer:SetAttribute("AutopilotLoop", true) -- optional: restart after each result
```

## Tests

Pure scoring, combo and geometry logic has specs in `src/tests`. In Studio's command bar:

```lua
require(game.ServerStorage.Tests.Runner).run()
```
