# Agent Task: Replace Per-Object Background Capture With Level-Buffer Restore

## Goal

Improve stock 68000 performance by removing the per-frame `GetBobBackground` background-capture step for moving gameplay objects where possible.

The game already uses double buffering. The current bottleneck is that each active object on the hidden buffer still does this pattern:

```text
PasteBackground(old object)
GetBobBackground(new object)
PasteBob(new object)
```

For many moving objects, this should become:

```text
RestoreLevelRect(old object rectangle)
PasteBob(new object)
```

The clean static map is already held in `level_screen`, so old dynamic-object pixels can be restored from `level_screen` instead of from a per-BOB saved background buffer.

## Primary Files

- `jetpac.has`
- `c:\Users\prozentreter\Documents\highamigaassembler\lib\bob.s`
- `c:\Users\prozentreter\Documents\highamigaassembler\lib\graphics.s`

Follow the repo instruction file for `.has` / 68000 assembly work:

- `.github/instructions/m6800-retro-amiga.instructions.md`

## Existing Hot Path

The main gameplay loop is in `jetpac.has`, inside `game_start()`:

```text
SwapScreen
_stars_animate
update_player
update_laser
update_meteors
check_player_meteor_collision
update_explosions
update_pickups
update_hud_state
render_gameplay_on_current_screen
WaitFrame
Show
```

The render routine is `render_gameplay_on_current_screen()`.

Current render order:

```text
erase_laser_on_current_screen
erase_meteors_on_current_screen
erase_explosions_on_current_screen
erase_pickups_on_current_screen
PasteBackground(player)
select_player_bob_for_buffer
GetBobBackground(player)
capture_meteors_background_on_current_screen
capture_explosions_background_on_current_screen
capture_pickups_background_on_current_screen
PasteBob(player)
draw_meteors_on_current_screen
draw_explosions_on_current_screen
draw_pickups_on_current_screen
draw_laser_on_current_screen
PasteBob(rocket)
draw_hud_on_current_screen
```

The expensive pattern is especially visible for meteors:

- `erase_meteors_on_current_screen()` calls `PasteBackground` for previous meteor positions.
- `capture_meteors_background_on_current_screen()` calls `GetBobBackground` for current meteor positions.
- `draw_meteors_on_current_screen()` calls `PasteBob`.

With up to `MAX_METEORS = 6`, this serializes many blitter operations per frame.

## Required Change

Add a rectangle restore routine that copies from `level_screen` to `gfx_current_screen_ptr` for a rectangular object footprint. Use it first for meteors only, because they are the largest repeat offender and are easy to test.

### New Routine

Create a native HAS routine in `jetpac.has`, near `CopyLevelBuffer()` or the other low-level level-buffer routines:

```text
RestoreLevelRect(x, y, width, height)
```

It should copy a chunk-aligned rectangle from `level_screen` to the current screen buffer.

Expected assumptions:

- Mode is 320x256, 5 bitplanes, line-interleaved.
- One screen row is `40 * 5 = 200` bytes.
- A 16-pixel chunk is 2 bytes per bitplane.
- X should be rounded down to a 16-pixel boundary for blitter-friendly restore.
- Width should be rounded up to cover the original rectangle after X alignment.
- Clamp to screen bounds before starting a blit.
- Use 68000-compatible instructions only.

Implementation may use the blitter or a tight CPU copy. Prefer the blitter if the setup is straightforward and follows the style in `bob.s`. If using the blitter, wait for blitter completion before touching blitter registers.

### Meteor Integration

Change `erase_meteors_on_current_screen(use_b)` so it restores the previous meteor footprint from `level_screen` instead of calling `PasteBackground`.

Keep the per-buffer previous-position tracking:

```text
meteor_prev_x_a / meteor_prev_y_a / meteor_prev_valid_a
meteor_prev_x_b / meteor_prev_y_b / meteor_prev_valid_b
meteor_prev_dir_a / meteor_prev_dir_b
```

But replace the old erase action with a restore call sized for the previous alien BOB.

Use the correct restore height:

```text
ALIEN_TYPE_METEOR    -> METEOR_BOB_H
ALIEN_TYPE_UFO_0002  -> 26
ALIEN_TYPE_UFO_0003  -> 27
ALIEN_TYPE_UFO_0004  -> 25
ALIEN_TYPE_UFO_0005  -> 29
```

Use `METEOR_BOB_W` for width unless the sprite descriptor width is more accurate and cheap to read.

Then remove or bypass `capture_meteors_background_on_current_screen(use_b)` from the normal render path. After this change meteors should no longer need `GetBobBackground` each frame.

Do not remove the function immediately unless nothing else calls it. A conservative first patch can leave the function unused.

## Important Caveat: Dynamic Overlap

Restoring from `level_screen` erases anything dynamic inside that rectangle. The current render order already erases old dynamic objects before drawing new ones, so the simplest safe order is:

1. Restore old dynamic footprints from `level_screen`.
2. Draw current dynamic objects again.

For the first patch, apply this only to meteors and keep the existing player, explosion, pickup, and laser logic unchanged. Watch for visual artifacts when meteors overlap the player, explosions, fuel, or laser. If artifacts appear, solve by expanding the dirty-restore approach to all dynamic objects in one shared erase phase, then drawing all current objects afterwards.

## Do Not Change Yet

- Do not rewrite the whole renderer.
- Do not change gameplay speeds, constants, or physics.
- Do not remove double buffering.
- Do not change `WaitFrame()` unless profiling proves timing sync is incorrect. It is currently an edge wait and should cap updates to one per PAL frame when the frame workload finishes in time.
- Do not convert to full-screen copy every frame as the first attempt; 50 KB per frame is likely too expensive on a stock 68000.

## Suggested Follow-Up After Meteor Patch

If the meteor-only patch helps and is visually clean, repeat the same pattern for:

1. Pickups
2. Explosions
3. Player

At that point most `CreateBob(..., 1)` background allocations for gameplay objects can become `CreateBob(..., 0)`, reducing heap use and avoiding background buffer management.

## Validation

Build first:

```powershell
.\build_game.ps1 -Source jetpac.has
```

Then test on emulator or hardware with a stock 68000 profile and a 68020 profile.

Minimum visual checks:

- Meteors erase cleanly over empty map areas.
- Meteors erase cleanly over platforms/tiles.
- Meteors moving left and right both erase cleanly.
- UFO variants on later levels erase at the correct height.
- No stale pixels remain after a meteor despawns at screen edge.
- No visible corruption when a meteor overlaps player, laser, pickup, rocket, or explosion.
- HUD remains intact.

Performance checks:

- Compare 68000 speed with `MAX_METEORS = 6` before and after.
- Check whether gameplay reaches closer to PAL 50 Hz under normal load.
- If the 68000 still misses frames, temporarily disable `_stars_animate()` and compare again to determine whether the next bottleneck is stars or remaining BOB work.

## Expected Result

The first successful patch should reduce meteor render cost from roughly:

```text
restore saved background + capture new background + draw meteor
```

to:

```text
restore static level rectangle + draw meteor
```

This removes one blitter operation per active meteor per rendered frame and should make the largest difference when several meteors are active.