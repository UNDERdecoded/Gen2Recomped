# Gen4 X/Y bindings

Keyboard defaults: `/` triggers X and `'` triggers Y. Keyboard `X` retains
its existing B/cancel action. X opens the field menu; Y uses the registered
item through the existing Gen4 input aliases.

Controller defaults use DS face positions for X/Y: SDL north (`y`, Xbox Y,
PlayStation Triangle, Nintendo X) triggers X; SDL west (`x`, Xbox X,
PlayStation Square, Nintendo Y) triggers Y. Standard raw-controller buttons
4/3 serve X/Y; drivers with different numbering can be rebound. Existing A/B
platform defaults remain in place.

Gen4's Controls menu exposes X/Y beside the other actions. It uses the live
platform default table for controller bindings, including Nintendo labels on
Switch. The keyboard names SLASH and QUOTE distinguish them from the column
separator. Capture, swap, clear, saved overlays and reset-all follow the existing
Controls workflow. Earlier generations omit the two DS-only menu rows.

Verified keyboard/controller press and release, raw-controller capture,
platform labels, key/pad swaps, clearing and reset-all through the actual Input
and BindingsMenu modules. Existing mobile and lower-display touch tests pass.
These changes require an updated build and no ROM reimport.
