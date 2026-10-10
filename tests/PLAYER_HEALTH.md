# Player health

Player scene: `scenes/Player.tscn`. Select the Player root to configure:

- `Max Health`: 100 by default.
- `Invulnerability Duration`: 0.5 seconds after an accepted hit and after recovery.
- `Stun Duration`: 2 seconds unconscious at zero HP.
- `Hit Push Speed` / `Hit Push Deceleration`: horizontal knockback speed (2.8 m/s) and how quickly it stops (10 m/s²).
- `Hit Turn Min Degrees` / `Hit Turn Max Degrees`: random view-turn strength (5–12 degrees).
- `Hit Turn Attack Time` / `Hit Turn Return Time`: one quick turn (0.045 s), then a smooth return (0.3 s). Direction and strength are chosen once per accepted hit, with pitch, yaw and roll. There is no projection-offset screen shake; mouse input during the impact is retained.
- `Knockout Push Speed` / `Knockout Up Speed` / `Knockout Tumble Speed`: launch and tumble of the temporary ragdoll (3.2 m/s, 0.7 m/s upwards, 2 rad/s).

Prisoner root: `Combat Settings > Attack Damage` defaults to 10 per animation impact.
Damage is delivered at the existing punch/kick impact timestamps.
The player's shared immunity timer prevents multiple enemies/combo hits from stacking during the protection window.

Every accepted hit pushes the player horizontally away from the attacker. With no attacker, it pushes backwards relative to the player's facing direction. This external velocity is separate from walking, decays over time and uses the normal wall/queue collision mask. Immune, unconscious or paused players receive neither damage nor additional feedback.

Zero HP cancels any charged throw and locks movement, jumping, mouse look, pickup, serving, drop input and throwing. The standing collision is temporarily disabled and `scenes/player_ragdoll.tscn` is instantiated. Since the player has no skeletal character model yet, this is a six-part capsule body connected by joints, with actual rigid-body gravity, collisions and a small launch impulse. Edit its parts and joints directly in the scene. The camera follows the physical head; held items stay held. The body collides with the world but does not push living prisoners out of their queue positions.

The world and enemies continue updating. A full-screen blur/dim effect and recovery countdown appear; the HP HUD remains readable. At the end of the stun, a floor ray and standing-capsule overlap query find a clear spot near the fallen torso, with pre-fall/last-grounded positions as fallbacks. A sweep rejects get-up paths through walls and a height check prevents popping up onto nearby countertops. If every candidate is blocked, recovery retries until a safe position is available instead of embedding the player in geometry. Recovery removes the ragdoll, restores standing collision and upright view, refills HP and grants the existing immunity interval. No GameManager/day-loop changes are involved.

Recovery restores full HP as an initial gameplay choice; there is no death/Game Over from player HP yet.
`health_changed`, `unconscious_started` and `recovered` signals are available for later integration.
Call `reset_health()` for a fresh run. Timers use game delta and respect normal SceneTree pause.

## Validation

For visual verification, play `scenes/main.tscn`, provoke a prisoner and let it attack. Confirm a small backward push and one random view turn per accepted hit. At zero HP, the camera falls with the ragdoll and the blur appears. After recovery, walking and mouse look work again; the held item must not be thrown by releasing an old mouse press.

Run `godot --headless --path <project> --fixed-fps 60 --script res://tests/player_impact_scenarios.gd`. It checks displacement, immunity, randomized turns, input during feedback, the six-part fall, held-item behavior, pause, recovery beside a wall, actual kitchen recovery and unloading a scene mid-stun. Native rendering can save screenshots with `-- <output-directory>`.
`tests/game_manager_scenarios.gd` verifies that an angry prisoner can reach and damage the player in the actual kitchen. Day-loop and menu scenarios verify that pausing preserves gameplay timers and HP.
