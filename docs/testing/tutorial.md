# Tutorial carousel / onboarding walkthrough

The guide automatically opens on the first registered kitchen run in each application session (including running main.tscn directly). `GameManager.tutorial_seen` is memory-only, like the day checkpoint. Returning to the menu, continuing, retrying or starting a new game in the same process does not show it automatically again. Restarting the application resets this flag.

Reading pauses preparation, cooking, spawning, AI and physics. Close or the `quit` shortcut (currently Tab) resumes the world. The shortcut closes the guide without also opening settings; the Close label reads its key from InputMap. Settings and summary cannot open the guide behind another modal. An unconscious player cannot interact with the sign. Opening cancels throw charging while retaining any held item.

## Edit pages without changing code

Open `scenes/ui/tutorial_popup.tscn` and find `Screen/Panel/Margin/Content/Pages`.

1. Duplicate any Page child to add a page, delete a Page to remove it, or reorder its siblings to change reading order.
2. Each Page has an `Image` TextureRect. Drag the drawing into its **Texture** property; it scales to fit without cropping or stretching. The numbered placeholder hides automatically when a texture exists.
3. All Control children directly under Pages count as pages. Runtime page numbers and navigation bounds are derived from this order; node names need not contain numbers.
4. Each page may contain additional labels or custom UI. Preserve the optional `Image` and `Placeholder` names if using automatic artwork/placeholder handling.
5. Screen starts hidden. Enable Visible temporarily to preview it in the editor, and show the Page being edited. Runtime displays only the selected page regardless of saved visibility.

Five illustrated pages use `assets/textures/ui/tutorial/tutorial1.png` through `tutorial5.png`, in filename order: how to play, fried chicken, mixed vegetables, rice, and controls. The dedicated `resources/themes/tutorial_theme.tres` provides the black, chalk-white and mustard palette. Other menus keep their existing themes. Previous/Next stop at the ends. Close remains available on every page; deleting every page shows an empty-state message and still allows closing. Every reopening begins at page one.

## World object

`Main/Kitchen/Interactables/TutorialSign` instances `scenes/props/interactive/tutorial_sign.tscn`. It uses the Book model at the position authored in main.tscn. Move the instance in the editor to change its placement. It is a StaticBody3D with collision, Focusable/Interactable groups and outline feedback; it cannot be picked up or moved by forces. Aim and click to open the guide, with or without a held item.

## Responsibilities

- `GameManager`: session flag, opening guards, pause/mouse ownership, scene-unload cleanup and close-shortcut behavior.
- `tutorial_popup.gd`: page enumeration, numbering, artwork placeholders and navigation.
- `tutorial_sign.gd`: focus and world interaction.
- Both the popup and sign use saved scene nodes, not runtime-built UI.

Run `godot --headless --path <project> --fixed-fps 60 --script res://tests/tutorial_scenarios.gd`. Native mode accepts `-- <screenshot-directory>`. Tests cover first launch, pause, navigation, world interaction, adding/reordering/removing pages, artwork, empty/single-page guides, active service, scene unload, Continue and New Game behavior.
