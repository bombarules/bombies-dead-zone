# Bombies: Dead Zone

A squad-based first/third-person wave shooter in Summer Engine (Godot 4.6).
You are the rogue hazmat engineer, holding a flooded underground parking
garage against mutating Bombies. Three rounds, then the exit opens.

## First playable version (in this repo)

- Flooded parking garage: murky standing water (slows you, not the runners),
  pillar grid, rusted parked cars, ramp to a mezzanine, amber tube lights and
  a flickering red emergency light, fog and haze.
- Hazmat engineer: hitscan rifle (30-round mag, R to reload), toxic grenades
  (G, area-denial acid cloud), two trap types (1 = proximity mine, 2 = acid
  trap, Q = place selected).
- V toggles first / third person. Right mouse aims down sights. F toggles
  the flashlight.
- 3 rounds: shamblers, then runners, then runners + tank brutes. After 40
  seconds in a round the surviving Bombies mutate (faster, tougher, redder).
- Win at round 3 (exit stairwell opens). Lose when downed. R restarts.
- Procedural sound: shots, booms, groans, drips, splashes — no audio files.
- Concept art for the game is in `assets/concept/`; the design brief is in
  `.summer/GameSoul.md`.

## Open it in Summer Engine

Summer Engine (macOS / Windows) → open this folder as a project. The main
scene is `main.tscn`.

> Note: Summer Engine has no Linux build yet, so this project was built and
> verified on Linux with stock Godot 4.6.3 instead of the Summer editor.

## Verify without the editor (stock Godot 4.6+)

```bash
# Import once (builds .godot/ caches):
godot --headless --import --path .
# Boot + self-play all 3 rounds under Xvfb, saves frames to /tmp/dz-shot-*.png:
DZ_SELFTEST=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --resolution 1280x720
```

The template's own probe also works once Summer Engine is available:

```bash
bash tests/autopilot/run.sh
```

## Android (touch controls + GitHub APK build)

On a touch device (Android, or `DZ_TOUCH=1` on desktop) the game shows touch
controls in landscape: floating left joystick = move, drag anywhere on the right
side = look, buttons for FIRE (hold; drag while holding to aim), JUMP, RELOAD,
GREN, MINE, ACID, ADS (toggle), SPRINT (toggle), VIEW (first/third person) and
LIGHT. After a win or loss, tap anywhere to restart. Keyboard + mouse still work
on desktop.

### Get the APK from GitHub (no local setup)

1. Create a new GitHub repository and upload the **contents** of this project
   to the repository root (so `project.godot` and the `.github` folder sit at
   the top level; make sure the hidden `.github/workflows/build-apk.yml` is
   uploaded).
2. Open the repo's **Actions** tab > **Build APK**. It runs automatically on
   every push to `main`; you can also press **Run workflow**.
3. When the run is green, open it and download the **bombies-dead-zone-apk**
   artifact (a zip containing `bombies-dead-zone-debug.apk`). The same APK is
   also published under the repo's **Releases**.
4. Copy the APK to your phone and install it (allow "install unknown apps").

The APK is arm64-v8a, debug-signed with a throw-away keystore generated during
the build, so no secrets or setup are needed. It is for sideloading, not the
Play Store.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look (Shift sprint, Space jump) |
| Left click | Fire |
| Right click (hold) | Aim down sights |
| R | Reload |
| G | Throw toxic grenade |
| 1 / 2 / Q | Place mine / acid trap / selected trap |
| V | First / third person |
| F | Flashlight |
| Esc | Release mouse |
