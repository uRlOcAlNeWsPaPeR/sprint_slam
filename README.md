# Sprint Slam

**RUN. BOOST. SLAM. REPEAT.** You get 45 seconds to sprint a neon course, build momentum,
launch off the ramp, and slam into a giant target. Speed sets your base score; precision
sets the multiplier.

The full concept analysis, technical challenges, architecture and phased roadmap are in
[docs/DESIGN.md](docs/DESIGN.md).

## Status

**Weekly challenges.** Every Sunday (00:00 UTC) a new week of **10 challenges** goes live. At the
Sprint Slam portal you pick one; the first time through you must clear them **in order** (a
clear is any server-verified slam), and once all ten are cleared you can replay **any** of
them to improve. Each challenge has two leaderboards:

- **Best score**: impact power x ring multiplier + time bonus (10 points for every second left
  on the clock, so a faster run is worth more) + combo bonus.
- **Fastest time**: GO to launch.

When a week ends, the top player on every board is inducted into the **Hall of Fame** (the
wall in the hub, and a tab in the portal menu), along with the week's champion (most board
wins). Week 1 is **Neon Rush, Danger Zone, Laser Grid, Spin Cycle, Blink Out, Pillar Punch,
Sweep Shot, Death Slalom, Gauntlet and Grand Slam**, each a bit longer than the old single
course, with a new hazard introduced one at a time over the first five. To add a week, copy
`src/shared/Weeks/Week1.luau`, give it the next Sunday as `StartsAt`, and list it in
`Weeks/init.luau`.

**Hazards.** Death blocks (touch one and you respawn at the last checkpoint), laser gates that
blink on and off, floor spinners that knock you away, blink floors that flash in a wave you ride
at about 50 st/s, pillar fields and sweeping blocks. Challenge progress and best times are saved
in published places.

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
| Pick a challenge (in the portal) | 1-9, 0 for #10 | - | tap a challenge |
| Next challenge (results) | N | - | NEXT |

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
game.Players.LocalPlayer:SetAttribute("AutopilotAdvance", true) -- with Loop: go on through challenges 1-10
game.Players.LocalPlayer:SetAttribute("AutopilotChallenge", "SKY TOWER") -- or run a hub challenge
```

The bot completed every hub challenge (Dash Gaps 2.3 s, Beam Run 4.5 s, Sky Tower 6.9 s)
and all ten Week 1 challenges in a row with verified bullseyes. To skip ahead in Studio, set
`workspace:SetAttribute("DevClearTo", 5)` from the server DataModel (Studio only), then pick
challenge 6 (`AutopilotLevel`)."

## Tests

Pure scoring, combo and geometry logic has specs in `src/tests`. In Studio's command bar:

```lua
require(game.ServerStorage.Tests.Runner).run()
```
