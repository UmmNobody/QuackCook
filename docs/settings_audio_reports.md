# Settings, reports, and transitions

All UI elements are saved in scenes and can be edited in Godot:

- `scenes/ui/settings_panel.tscn`: shared mouse/SFX/music sliders.
- `scenes/ui/settings_page.tscn`: settings opened from the main menu.
- `scenes/ui/pause_menu.tscn`: Resume, Settings, Save & Main Menu.
- `scenes/ui/credits.tscn`: empty `ContentPlaceholder` ready for credits.
- `scenes/ui/run_summary.tscn`: final report after the Game Over comic.
- `scenes/ui/scene_transition.tscn`: persistent circular halftone wipe.

Settings, checkpoints, run totals, and best day are in memory only. Closing the
application clears them. Continue reloads a fresh kitchen at the checkpoint day,
keeping totals accumulated in that run (including actions before leaving a day).
New Game and Retry reset run totals but retain the best day for this session.

`GameManager.run_totals` tracks furthest day **reached**, successfully served
prisoners, prisoners incapacitated (once per prisoner), and player knockouts.
Disposing of an already incapacitated prisoner does not count a second time.
Daily totals remain separate. Game Over comic completion, autoplay, and Skip all
lead to the final report; Retry loads day 1 directly, Main Menu returns to menu.

## Adding audio

The default bus layout contains Master, SFX, and Music. Assign scene-authored
AudioStreamPlayer / AudioStreamPlayer3D nodes to the appropriate bus. Volume
sliders apply immediately, including while the game is paused. A value of zero
mutes the bus.

The persistent `AudioManager` offers:

```gdscript
AudioManager.play_music(preload("res://assets/audio/music/your_track.ogg"))
AudioManager.stop_music()
AudioManager.play_sfx(preload("res://assets/audio/sfx/your_effect.wav"))
AudioManager.play_sfx_3d(effect_stream, source_node_3d)
```

These are example paths; sound files are not supplied by this change. Enable
looping on the music stream/import settings as needed. Music persists through
scene changes and pauses. Spatial effects inherit the source's pause/lifetime.
One-shot effects free their player after playback.

## Transition adjustments

`SceneTransition` is an autoload scene using the supplied `transition.gdshader`.
Change `duration` on its root for seconds per closing/opening half (default 0.55).
The Curtain shader material holds the tiling, feathering, and sweep textures.
Changing `shape_tiling` changes dot size. The full screen uses its current aspect
ratio so dots stay circular. Input is blocked during the wipe.

All current scene changes go through GameManager and use this overlay. Daily
reports keep the existing 3-second wait, then wipe into the report. Advancing to
the next day also wipes while keeping the kitchen and its objects intact.

## Verification

- `tests/settings_summary_transition_scenarios.gd`: real scene navigation,
  settings, mouse input, bus routing, pause-safe transitions, stat accumulation,
  Continue, Retry, and final report.
- Existing day-loop and both comic tests cover the revised report routing.
