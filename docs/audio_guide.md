# Audio integration

## Asset folders

- `assets/audio/music/main_menu.ogg`: looping menu/settings/credits music.
- `assets/audio/sfx/kitchen/`: frying, burning, refill, opening/closing lever.
- `assets/audio/sfx/doors/`: prisoner door and kitchen shutter.
- `assets/audio/sfx/player/`: dash and throw.
- `assets/audio/sfx/prisoners/`: damage quacks, angry quack, double quack.
- `assets/audio/sfx/ui/`: clock ticks, hover, and final-report Game Over sting.
- `assets/audio/sfx/cutscenes/`: remaining comic-panel sound effects.

Import sidecars were moved with the files and retain their UIDs. AudioManager's
SOUNDS dictionary maps short names to the new paths; shared sounds are not copied.

## Playback and controls

All effects use SFX, including the final-report sting. Menu music uses Music and
continues across menu/settings/credits without restarting. Both cutscenes and
entering the kitchen stop music. The sliders control the corresponding buses.
SFX slider release previews quack1 once; moving the slider does not spam audio.
Button hover automatically includes both Button and TextureButton nodes.

Gameplay one-shots belong to their source and stop on scene removal. Spatial
effects (prisoners, door, refill and lever) fade with distance. The stove has one
scene-authored CookingAudio voice: frying while food is in a pan on the stove,
burning once food becomes BURNT in either pan or pot, silence when food/cookware
is removed. Burning replaces frying. Cooking loops use cached duplicate streams
with looping enabled, leaving original resources unmodified. CookingAudio's
volume is -8 dB and can be changed in the stove scene's Inspector.

Accepted damage randomly selects quack1/quack2. Rejected hits during player
invulnerability are silent. Patience-exhaustion anger plays at the actual tray
release; a prisoner without a tray quacks when entering combat instead.
Clock ticks vary pitch from 0.94 to 1.06 and fire once per displayed second.
Lever sounds require an accepted player interaction. Automatic kitchen changes
still sound the shutter, without an artificial lever click.

## Comic panel sound editing

Each panel TextureRect has Inspector metadata:

- `sound`: AudioManager short sound name; empty means silence.
- `second_sound`: optional delayed second cue.
- `second_sound_delay`: delay from panel entrance, in seconds.

Intro: noti, door1, gun, handcuff, judge + quack_double after 1.5 seconds,
quack_angry, shirt, shirt.

Game Over: door1, quack1, handcuff, silence, electricity, dink.

Sounds start on panel entrance. Advancing stops the previous panel's voices and
cancels its delayed cue. Clicking to finish the current slide does not restart
audio. Skip stops all panel audio immediately. The gameover sting plays only
when the final run report opens, not on daily reports.

Validation: `tests/audio_scenarios.gd` covers all 25 imports, bus/loop routing,
hover/slider audio, all comic assignments, delayed-cue cancellation, stove
transitions, accepted damage/dash/throw/refill, clock variation, and lever/shutter
actions in a real kitchen.
