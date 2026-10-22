# Sprint Slam

**RUN. BOOST. SLAM. REPEAT.** You get 45 seconds to sprint a neon course, build momentum,
launch off the ramp, and slam into a giant target. Speed sets your base score; precision
sets the multiplier.

The full concept analysis, technical challenges, architecture and phased roadmap are in
[docs/DESIGN.md](docs/DESIGN.md).

## Status

**Levels 1-5.** Sprint Slam has five levels on the Neon Rush layout. Each one adds a new
obstacle on top of the last: **Danger Zone** (death blocks: touch one and you respawn at the
last checkpoint), **Laser Grid** (laser gates that blink on and off), **Spin Cycle** (floor
spinners that knock you away) and **Blink Out** (the S-bend floor turns on and off in a wave
you have to ride at about 50 st/s). The portal opens a level select. Any verified slam
unlocks the next level, and NEXT LEVEL (or **N**) jumps straight there. Unlocks are saved in
published places.

**The Hub (lobby).** Every player spawns in a floating neon hub. Walk into the **Sprint Slam**
portal to start a run, and press **L** (or the HUB button) to come back. Two locked portals
are ready for future modes. Around the plaza are three timed parkour challenges that use the
full movement kit: **Sky Tower** (spiral climb), **Dash Gaps** (boost pads, a ring and air
dashes) and **Beam Run** (narrow beams, sweepers, a jump pad). Your session bests are shown
on finish.

**Phase 1 — Core prototype.** One complete course (Neon Rush) with momentum movement, dash,
slide, boost pads, jump pad shortcut, moving obstacles, slam flight with steering and Slam
Dash, zone scoring, server validation, session bests and instant restart.

## Running it

No tooling is required:

```bash
node tools/build-place.js
```

Then open `build/SprintSlam.rbxlx` in Roblox Studio and press **Play**.

The course is generated from data at runtime. To see it in the edit view too, install the
preview plugin once:

```bash
node tools/build-place.js --install-plugin
```

This copies `SprintSlamPreview.rbxmx` into Studio's local plugins folder
(`~/Documents/Roblox/Plugins` on macOS). Whenever a Sprint Slam place is open in Edit mode,
the plugin builds the course and rebuilds it when course code changes. It also adds a
**Sprint Slam → Rebuild Course** toolbar button. The preview is never saved into the place,
and Play builds the real course as usual. Delete that file to uninstall.

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
| Restart run / restart challenge | R | Y | RESTART |
| Back to the hub | L | Select | HUB |
| Pick a level (in the portal) | 1-5 | - | tap a level |
| Next level (results) | N | - | NEXT |

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
game.Players.LocalPlayer:SetAttribute("AutopilotAdvance", true) -- with Loop: go on through levels 1-5
game.Players.LocalPlayer:SetAttribute("AutopilotChallenge", "SKY TOWER") -- or run a hub challenge
```

The bot completed every hub challenge (Dash Gaps 2.3 s, Beam Run 4.5 s, Sky Tower 6.9 s)
and chained levels 1-5 with verified bullseyes. Keep the Studio window visible while it
runs: Studio pauses rendering for hidden windows.

## Tests

Pure scoring, combo and geometry logic has specs in `src/tests`. In Studio's command bar:

```lua
require(game.ServerStorage.Tests.Runner).run()
```
