# Mobile control gestures

Visible virtual buttons now take priority over main-screen pointer handlers.
A control owns its move/release events until the contact ends, including when
its press opens a new screen. Lower-display events do not release primary
overlay controls. The D-pad returns immediately after capture, preventing
free-camera handling from replacing its ownership and leaving a direction
held. Sliding outside the pad releases movement; live-contact polling recovers
OS cancellations; pointer-id reuse releases the previous hold.

Gen4 has the DS face-button diamond: X north, A east, B south, Y west. X feeds
the field menu action and Y the registered item action through the existing
START/SELECT shortcuts. The controls editor can store X/Y positions alongside
the other buttons. Other generations retain their two-button layouts.

Portrait donation buttons use normal-sized text and dimensions, without the
extra stacked header row. Landscape retains the doubled button.

Verified through 189 automated checks covering eight versions, screen changes,
rapid B taps, repeated Platinum menu navigation, starter left/right movement,
multi-touch, OS cancellation, native X/Y actions, and dual-display separation.
Existing Android Pokétch and second-display tests pass. Local LOVE previews
verified the phone diamond and compact portrait donation header. Physical
Android device verification remains pending; these changes need an updated
build but do not require a ROM reimport.
