# Daylight revision

Run scenes/world/kitchen_lighting_test.tscn with F6 (or play the main game). Close the Kitchen Guide with Esc. The floor material and sky are saved in the scenes and visible in the editor. Other stylized materials and lighting are still applied at runtime.

This replaces the warm preset with neutral daylight, muted blue sky and moving clouds, using the supplied SourceCode (3).zip sky shader and SourceCode (4).zip toon shader. Adaptations preserve imported colors/UV/normal maps, correct clamp argument order and horizon divisions, and prevent per-light shadow tint from illuminating objects outside the light range. Rim and pattern effects are disabled for this preset.

The concrete floor (Part.025 / QC_Floor_Concrete) now uses subtle gray-green square tiles with a 0.85 unit tile size, world-space mapping and no photographic normal map. Other materials, including the dark road, are preserved.

Floor mask: Kenney Pattern Pack 1.1, pattern_14.png (CC0), https://kenney.nl/assets/pattern-pack . Original mask and license are under assets/textures/kitchen_daylight. Colors are set by the shader, not painted into the texture.

Sky controls: resources/visuals/kitchen_daylight_sky.tres > Sky Material. Lighting controls: KitchenVisualStyle node in main.tscn. Shader defaults control tile/grout colors and tile size. Gameplay scripts, GLB, collision, and animation data were not modified.

Validation: Godot 4.7 Compatibility GPU run passed player movement, floor shader application, spawned food shading, focus toggling, cut-state switching, 158 collision shapes, and 5-second shutter animation. Two GLES texture-allocation warnings (349524 bytes each) remain at engine shutdown; no runtime shader compilation error was observed. No sustained performance or leak benchmark was performed.


Floor editing: select Part_025 in main.tscn or quackcook_kitchen.tscn, then Geometry > Material Override. The shared resource is resources/materials/kitchen_floor_tiles.tres; edit Tile Color, Grout Color and Tile Size under Shader Parameters. Floor conversion was removed from the runtime style script. Verified on instantiated scenes before adding them to the scene tree (no _ready execution), and verified that runtime styling preserves the same resource.

