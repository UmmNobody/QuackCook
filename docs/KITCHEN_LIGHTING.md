This describes the previous warm preset. The active preset is now documented in KITCHEN_DAYLIGHT.md.

# Kitchen lighting preset

Open `scenes/world/kitchen_lighting_test.tscn` and press F6. Close the Kitchen Guide with Esc to see the room. The same preset is active in `scenes/main.tscn` when the normal game starts.

The preset runs at runtime, so the editor viewport does not show the final lighting. It preserves imported base colors and textures, uses soft three-band shading, warm ceiling lights, and subtle outlines on selected props and food. Glass, emissive lamps, unshaded UI meshes, and existing custom shaders remain unchanged.

Select `KitchenVisualStyle` in the main scene to adjust Ambient Strength, Ceiling Strength, Shadow Color, Warm Light Color, or Subtle Prop Outlines. Changes take effect on the next run. Disable Enabled and restart to view the original setup.

Only `scenes/main.tscn` was edited among existing project files. Added files: `scripts/visuals/kitchen_visual_style.gd`, `shaders/kitchen_soft_toon.gdshader`, and the inherited test scene. Imported model, collision, animations, and gameplay scripts remain unchanged.

Verified in Godot 4.7 Compatibility on an RTX 3060 Laptop GPU: runtime shader compilation, player movement, 6 ceiling lights (2 with shadows), 158 kitchen collision shapes, 5-second shutter animation, spawned food shading, focus outline toggling, and food cut-state switching. This is a functional smoke test, not a full gameplay or performance benchmark.

