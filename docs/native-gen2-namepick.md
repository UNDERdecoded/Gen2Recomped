# Native Gen2 player-name choice

The player-name step in Gen2 Oak speech now opens `Gen2NamePick`, rather than
using the generic preset menu attached to the naming keyboard. Its original
player portrait moves from tile column 6 to 13, one tile per update, before
input is admitted. A preset moves the portrait back before the original Oak
step resumes. B cannot dismiss this required choice. The class and tile layout
follow Gen1Recomp's separate Gen2 NamePick owner; original source provenance is
retained in the implementation.

NEW NAME opens the existing native Gen2 keyboard through `Screens.push`, so
screen registry overrides still apply. It retains the actual gender and field
length without turning an eight-slot player field into box entry. START selects
END and A confirms; empty input keeps the actual supplied preset. Completion is
once-only, and a keyboard whose original caller was removed cannot commit to it.
The public picker constructor leaves dismissal to its caller. Native Oak owns
its picker dismissal, player-name write and original continuation.

Portraits and form-specific names use the engine's actual imported player data.
The class spelling `src.ui.gen2.NamePick` addresses this same native owner.
Ordinary non-Gen2 and rival naming retain their existing route. Screens with no
presets can still open the keyboard directly. No mod-specific name flow is added.

ROM-free tests cover input blocking during both directions of movement, input
wrap, B rejection, native keyboard/empty-name ownership and actual Oak dispatch
for Gold, Silver and Crystal. Exact-source GPU acceptance of the new picker,
ROM naming-program/menu-art import, remaining raster/header details and a full
unmodified-mod story/save/link playthrough are separate unfinished work.
