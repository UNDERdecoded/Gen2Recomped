# Zoom across map transitions

Gen1–3's world canvas was capped to the current map's extent, then enlarged to cover the window. This overrode the user's selected pixel scale in small buildings and narrow routes. Several successive zoom levels produced the same image, and crossing to a different-sized map changed the apparent maximum zoom-out.

The renderer now keeps the full requested view and presentation scale for Gen1–3. Existing border-tile and connected-map rendering fill that view. Gen4 retains its bounded 3D terrain behavior. Window size, performance settings, mod zoom-range hooks, and the input gate during active scripts/transitions still control zoom as before.

`tools/map_transition_zoom_check.lua` covers nine games, four window sizes, all available zoom steps, seven map-bound configurations, tilted rendering, and the transition input gate. Gen4 indoor framing and native-camera/Dramatic Shapes routing checks also pass. No cache reimport or mod-folder update is required for this engine-level change.
