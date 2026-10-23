# Publishing Sprint Slam

## One-time setup (needs your Roblox login, so it can't be scripted)
1. `node tools/build-place.js`, then open `build/SprintSlam.rbxlx` in Studio.
2. **File > Publish to Roblox As...**, pick the creator, name it, and click Create.
3. **Home > Game Settings > Security**: turn on **Enable Studio Access to API Services**.
   This is a setting on the published experience (it is not stored in the place file), and
   saving coins, progress, personal bests, the leaderboards and the Hall of Fame all need it.
4. **Game Settings > Basic Info**: description, genre, devices (Computer, Phone, Tablet, Console).
5. On roblox.com > the experience > Configure: add an icon and thumbnails, then set Privacy to
   Public when ready.

## Smoke test on the live (private) game
- Join, run challenge 1, leave, rejoin: coins, progress and your best should still be there.
- Leaderboard and Hall of Fame wall show your entry.
- Test on a phone or tablet (touch buttons).

## Updating
`node tools/build-place.js`, open the file, **File > Publish to Roblox**. Edit code here, never
in Studio: the place is regenerated from the project.

## Releasing a new week
Add `src/shared/Weeks/WeekN.luau` (copy Week1, `StartsAt` = the Sunday 00:00 UTC), list it in
`Weeks/init.luau`, rebuild and publish before that Sunday. The previous week is inducted into
the Hall of Fame by the first server that starts after the new week begins.

## Known gaps
- No audio yet (`Config.Sounds` ids are empty).
- Touch controls are untested on a real device.
