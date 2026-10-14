# Kitchen loading screen

All gameplay entry points now use `scenes/ui/loading_scene.tscn` before `scenes/main.tscn`:

- New game: menu -> intro comic -> loading -> kitchen, day 1.
- Continue: menu -> loading -> fresh kitchen at the checkpoint day.
- Retry: final report -> loading -> fresh kitchen, day 1.
- Next day keeps the existing kitchen; it does not reload the scene.

Edit the actual Control nodes in `loading_scene.tscn` to customize the screen. The scene deliberately has no reference/preload to the heavy kitchen scene. GameManager opens and reveals the lightweight screen before calling `start_loading()`. The existing transition plays on both sides of loading.

`scripts/ui/loading_scene.gd` uses ResourceLoader background loading on platforms with threads. On single-threaded web exports it discovers resource dependencies with `get_dependencies()`, loads them in dependency order, and yields frames between resources. Strong resource references retain the cache until the kitchen takes ownership. This also works with exported binary resources; it does not parse source `.tscn` files. The progress percentage in this mode counts resources, not bytes or seconds. Enable **Force Incremental Loading** in the Inspector to test this path on desktop.

A large individual resource, scene instantiation, or first GPU shader compilation can still pause the main thread. This loading screen does not reduce the initial browser download of the exported game pack. It provides feedback while the kitchen resources are prepared after the game has started.

The day remains pending during loading and is consumed by the kitchen's existing `start_registered_run()` flow. Failed loads expose a Back to Menu button and preserve the checkpoint. No fake timed progress or minimum wait is added.

Validation commands (from the project directory):

```text
godot --headless --path . --script tests/loading_scenarios.gd
godot --headless --path . --script tests/loading_scenarios.gd -- --incremental
```
