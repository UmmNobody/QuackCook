# Endless kitchen loop

F5 opens `scenes/ui/main_menu.tscn`, with a single Start game button. With no session checkpoint it loads a fresh kitchen on day 1. A saved day opens Continue / New game / Cancel choices first. The kitchen allows thirty seconds to prepare, then releases a finite wave. Prepare food and refill the serving wells normally; wells are not automatically refilled. Running `main.tscn` directly with F6 remains available for development.

## Pause and session-only continuation

Esc opens settings and pauses gameplay, including preparation, cooking, spawning, AI, physics and combat timers. It has one Exit to main menu button. Esc again closes settings. Settings can also open above the daily report; closing it returns to the report with the world still paused.

The GameManager autoload stores only `checkpoint_day` in memory. There is **no disk save**, and no `user://` file. Returning to the menu preserves the checkpoint while the application stays open. Closing the application, stopping it in Godot, or starting another process loses that checkpoint.

- Beginning a day stores that day's number.
- Leaving during preparation or service returns to the beginning of the same day next time.
- Passing a day immediately stores the following day, even if leaving from the report before pressing Next day.
- Failing a day clears the checkpoint immediately, before Game Over confirmation, so exiting the failed report cannot restore that run.
- Continue loads a fresh `main.tscn` and recalculates difficulty for the saved day. Objects, stock, prisoners, HP, held items and daily counters start fresh.
- New game starts on day 1 and replaces the previous checkpoint. Cancel leaves it unchanged.

This differs from normal Next day inside a run, which keeps the same kitchen and objects as described below.

## Opening and closing the kitchen

The `CloseKitchenButton` is on the inside wall beside the door prisoners use, at approximately `(-6.06, 2.2, -4.6)`. Aim at it for an outline and a status message, then click. During preparation it reads OPEN KITCHEN; clicking immediately ends preparation and starts the wave. Without a click it opens automatically after 30 seconds. During service it reads CLOSE KITCHEN and keeps the close guards below. Its indicator is green when the current action is available.

All conditions must be satisfied:

1. Service has begun and every scheduled prisoner has spawned.
2. No prisoners remain waiting, collecting trays, moving through the queue or waiting at food stations.
3. No conscious angry prisoners remain.

Unconscious bodies and successful prisoners already walking out do not block closing. Player incapacitation still blocks interaction normally.

Closing opens a minimal daily report over the existing kitchen. It displays the day, successfully served count, not-served count, quota and pass/fail result. Physics, cooking, AI and gameplay timers pause. Mouse input becomes available for the menu, and a charged throw is canceled while the held object remains held.

- Pass: `Start day ...` increments the day and starts preparation in the same scene.
- Fail: `Continue to Game Over` changes to `scenes/ui/game_over.tscn`, after the player has read the report. That scene offers a fresh run or return to the main menu.

Going to the next day preserves world objects, unconscious bodies, held items, cookware contents, well stock and player HP. No scene reload or cleanup occurs. Existing object-specific lifetimes still apply during active play. A new run from Game Over loads a fresh kitchen and resets to day 1.

## Inspector settings

Select `Main/Queue/QueueLayout`:

- **Auto Start Run**: automatic startup; disable for external control or isolated tests.
- **First Day**: initial total prisoners, required successes, min/max foods, patience, spawn interval and preparation time.
- **Difficulty**: progression per day, food progression intervals/caps and patience floor.

Default progression:

| Day | Arrivals | Required successes | Foods per prisoner | Patience |
| --- | --- | --- | --- | --- |
| 1 | 6 | 4 | 1â€“2 | 45 s |
| 2 | 8 | 6 | 1â€“2 | 43 s |
| 3 | 10 | 8 | 1â€“3 | 41 s |
| 5 | 14 | 12 | 2â€“4 | 37 s |
| 9 | 22 | 20 | 2â€“4 | 30 s |

Arrivals and quota continue growing by two each day. Food counts stop at the configured bounds and patience never drops below its floor. Required successes are clamped to the number of arrivals. Preparation remains thirty seconds by default every day. `Spawner > Max Active Prisoners` stays at 9, so growing daily totals arrive over time instead of expanding the queue.

The GameManager autoload also exposes **Game Over Scene Path**, which can later point to a cutscene.

## Responsibilities / API

- `kitchen_queue.gd`: registers scene markers, wells, player and spawner, then calls `GameManager.start_registered_run(first_day, difficulty)` once, consuming the day selected by the main menu.
- `day_progression.gd`: creates a fresh `service_wave_config.gd` resource for the requested day; active settings are snapshots.
- `game_manager.gd`: owns `IDLE â†’ PREPARING â†’ SERVING â†’ SUMMARY`, then the next day or `GAME_OVER`. It owns the summary pause and resumes it on next day, scene exit or Game Over.
- `QueueManager`: exclusively controls station occupancy and queue reservations.
- `PrisonerSpawner`: finite arrivals and generation-specific tracking. Closing cancels old wave tracking without deleting actors.
- `Prisoner`: reports successful service once when beginning a normal exit with its complete order; anger/incapacitation first counts as failure. Outcomes cannot be counted twice or leak into later days.
- `close_kitchen_button.gd`: focus feedback and calls to `open_kitchen()` or `finish_service()` according to state.
- `scripts/ui/*.gd`: UI data and actions; node layouts and appearance are saved in scenes and a Theme resource. They do not decide game outcomes.

Useful calls: `can_open_kitchen()`, `open_kitchen()`, `start_run()`, `get_service_summary()`, `can_close_kitchen()`, `close_block_reason()`, `finish_service()`, `next_day()`, `confirm_summary()`, `restart_run()`.

Menu APIs: `has_checkpoint()`, `launch_from_menu(continue_previous)`, `toggle_pause_menu()` and `return_to_menu()`. `pause_menu_changed` updates the overlay. Scene transitions are guarded against repeated activation; unloading a kitchen releases pause and runtime references without clearing the session checkpoint.

Signals: `preparation_started`, `service_started`, `all_prisoners_spawned`, `session_changed`, `service_finished`, `summary_opened`, `day_started`.

The lower-level `start_service(settings)` remains available for isolated one-wave tests. Without `start_run`, finishing that standalone wave returns a report and goes idle instead of opening the day UI.

## Scene layout and navigation

Queue markers remain in child order: four waiting positions, tray collection, chicken, vegetables, rice, water. `ExitPoint` leads along the outside corridor. `EscapeRoute` enters the door, then baked navigation routes angry prisoners around counters. Keep the layout aligned with the table if editing either.

After moving static kitchen geometry, rebuild `resources/navigation/kitchen_navigation.tres`:

```text
godot --headless --path <project> --script res://scripts/tools/bake_kitchen_navigation.gd
```

## Validation

```text
godot --headless --path <project> --fixed-fps 60 --script res://tests/day_loop_scenarios.gd
godot --headless --path <project> --fixed-fps 60 --script res://tests/game_manager_scenarios.gd
godot --headless --path <project> --fixed-fps 60 --script res://tests/menu_scenarios.gd
godot --headless --path <project> --script res://tests/menu_scenarios.gd -- fresh_process_only
```

Day-loop tests exercise progression bounds, wall-button access/highlight and close guards, a real mixed-outcome day, paused physics/timers, held object and stock persistence, day two, failure, Game Over and retry. Native-renderer execution additionally checks cursor capture and can save UI screenshots with `-- <output-directory>`. Headless mode cannot capture the OS mouse.

`tests/stove_pickup_scenarios.gd` separately verifies cookware pickup and cooking in the main scene.

Menu tests cover the first launch, actual Esc input, nested report/settings pause, returning to menu, Continue/New/Cancel, day-specific difficulty, resetting kitchen contents, and failure checkpoint clearing. Run `fresh_process_only` in a second Godot process to verify that the in-memory checkpoint does not survive closing the previous process.

## Editing UI in Godot

- Main menu and continue prompt: `scenes/ui/main_menu.tscn` (Home / Confirmation).
- Pause/settings overlay: `scenes/ui/pause_menu.tscn`.
- Daily report: `scenes/ui/day_summary.tscn`.
- Game Over: `scenes/ui/game_over.tscn`.
- Shared panel/button styles: `resources/themes/menu_theme.tres`; primary actions use the PrimaryButton variation.

All UI nodes are saved in these scenes. Edit containers, labels, buttons, theme overrides and sizes directly in the Inspector. Main instances the pause and report scenes. Their Screen/Summary controls start hidden; temporarily enable Visible to preview in the editor. Confirmation is also hidden initially. Scripts use scene-unique names (%Name), so moving nodes within the same scene is safe; retain unique names and their types. Dynamic counts, day labels and outcome text are updated during play. The report root exports success/failure colors.
