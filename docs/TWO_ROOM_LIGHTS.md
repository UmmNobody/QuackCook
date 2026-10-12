# Two room lights

The main scene now contains exactly two SpotLight3D nodes under Environment/RoomLighting:
- KitchenRoomLight: centered below the kitchen ceiling, 80 degree cone.
- HallRoomLight: centered below the hall ceiling, 84 degree cone.

Both lights cast shadows. A saved WorldEnvironment supplies neutral ambient fill (energy 0.60) to keep distant corners readable. The sky uses its daytime parameter instead of depending on a DirectionalLight3D. The previous sun and six runtime ceiling lights have been removed. The material styling script no longer creates lights or overrides the saved environment.

Edit the lights and WorldEnvironment directly in main.tscn. No geometry or gameplay scripts were changed. Existing lamp models remain decorative. Runtime verification found exactly two lights, two shadow-enabled spotlights, and 189 unchanged mesh nodes. No render or frame-rate benchmark was performed.
