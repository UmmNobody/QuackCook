# Intro comic cutscene

Open `scenes/cutscenes/intro_cutscene.tscn` in Godot. NewGame goes through this scene before day 1; Continue and retry from Game Over go straight to the kitchen. Finishing the last panel and Skip share the same guarded transition. The first-session tutorial still opens after entering the kitchen, before preparation time runs.

## Artwork and layout

`ComicBoard/Pages/Page1` holds start1–4; `Page2` holds start5–8. Each TextureRect uses the original 1920×1080 transparent PNG, preserving the authored positions and reading order. Revealed panels stay visible until the next page. The board scales uniformly to fit the viewport without cropping the images. Toolbar nodes live outside the board, at the top right.

To add a panel, duplicate a TextureRect under the desired page and change its texture. Sibling order determines reveal order. To add a page, duplicate a page Control and edit its panels. Remove nodes to reduce the panel count. Toggle page visibility in the editor to preview either composition; runtime visibility is managed automatically.

## Playback

- Click, Space, Enter or Right advances; clicking during an entrance finishes that entrance first.
- Auto Play defaults to OFF; its button toggles timed playback without advancing a panel.
- Default entrance: 0.45 s, moving upward 100 design pixels while fading in.
- Default hold: 3 s after the entrance has completed. The last panel is held before automatic completion too.
- Inspector on the root: Slide Seconds, Slide Distance, Panel Hold Seconds and Auto Play.
- For a specific panel, optional float metadata `hold_seconds` overrides the default hold duration (minimum 0.5 s).
- Skip works during either animation or reading. Button clicks do not also advance the comic.

`scripts/ui/comic_cutscene.gd` owns reusable playback and emits `finished`. `intro_cutscene.gd` connects that signal to GameManager to start day 1.

## Verification

Run `tests/intro_cutscene_scenarios.gd` with Godot `--headless --fixed-fps 60 --script`. It covers entrances, retained panels, page changes, auto/manual switching, completion, repeated Skip, NewGame confirmation, Continue and tutorial/preparation ordering. Native rendering also produces page previews in the task staging folder.
