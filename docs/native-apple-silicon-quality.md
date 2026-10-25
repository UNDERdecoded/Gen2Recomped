# Apple Silicon desktop quality

`Performance.detect()` treated every non-mobile ARM host as a low-end
handheld, including macOS. The supplied Johto package correctly identified
the M3 CPU/GPU as capable, but its AUTO policy also consumed that engine
classification and started at LOW. In a fresh Crystal GPU test this selected
the 720p-class scene budget, flat sky, disabled clouds and disabled shadows.

macOS now uses the existing desktop core-count policy on Apple Silicon, as
Intel Macs already did. Explicit LOW/BALANCED selections remain available;
ARM Linux handhelds and mobile detection retain their existing behavior.
No mod-specific quality preset or saved setting is forced by the engine.

At fork source `7b05320fcc85c13f445f928586d5cd91ea39e16b`, a fresh profile
reports engine HIGH. The unchanged supplied package starts at MEDIUM under
its own conservative Gen2 AUTO policy, with the balanced scene resolution,
full sky, clouds and low-quality shadows enabled. The previous LOW default
was a classification error, not an intrinsic limit of native Gen2 rendering.

For the 800×720 logical / 1600×1440 physical test window, measured color
targets are:

| Selection | Scene color target | Presented world |
| --- | --- | --- |
| Previous fresh AUTO / LOW | 800×720 | 1600×1440 |
| Corrected fresh AUTO / MEDIUM | 1200×1080 | 1600×1440 |
| NATIVE, AA OFF | 1600×1440 | 1600×1440 |
| NATIVE, AA 2X | 2263×2036 | 1600×1440 |

The active drawWorld pipeline already receives physical pixel dimensions.
Its private adapter translates these correctly; the older compose helper's
logical-size fallback does not explain this active-path reduction. Inspecting
the helper alone would give the wrong diagnosis. Window, scene, readable-depth
and presentation-target sizes must be distinguished.

The existing performance suite passes 42 assertions, including six new Mac
regressions for detection, AUTO resolution, published tier, explicit selections
and the desktop core-count floor. GPU verification is source-bound in the
[quality receipt](qa/native-foundation/johto-native-apple-silicon-quality.json).
The comparison uses actual imported Crystal and all 27,329 supplied mod files
unchanged, with fresh isolated QA profiles, skipped introduction and a selected
town position. It is image-size/camera smoke coverage, not a frame-rate benchmark
or normal story acceptance. Native/AA presets are changed through the real mod
option event interface only in those QA profiles.

Sharper edges do not establish complete renderer parity. The generated
Stadium overworld extension still exceeds the stock runtime's 60-upvalue
limit; the base voxel scene is visible, but model/occlusion parity remains
open. A preliminary 4X comparison produced sharper images but its second
owned-window proof failed the stale-frame check. It is not accepted as a
successful 4X run, and 4X is not made the default. No source/assets/screenshots,
ROM data or saves from the supplied package are published.
