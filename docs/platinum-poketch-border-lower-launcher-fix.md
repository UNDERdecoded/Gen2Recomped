# Pokétch border and lower launcher

The Platinum border palette already contains 256 entries, with the device
colours in slot 15. The extraction recipe relocated its first black row to
slot 15 instead, producing an opaque black shell. Existing tests checked
opacity but missed the lost colours. The recipe now retains the ROM palette;
the check also requires red buttons and a light bezel through `composeJob`.

Platinum's cache marker advances to v16 so an updated build replaces that
broken PNG on reimport. Other games' cache markers are unchanged.

The LCD uses a DPI-independent 256×192 canvas and clips within that canvas.
It restores both window and canvas destinations before drawing the shell,
which bypasses LCD/world shaders. Physical lower-screen draws clear inherited
world stencil, depth and shader state.

The launcher lower panel uses the live launcher palette, dark cards with
generation accents, and fixed eight-pixel logical text rasterized at the
panel's density. Selecting a game cannot change its font. Release-status
suffixes stay on the detailed main launcher rather than overflowing tiles.

Verified with ROM colour checks, render-target restoration checks, launcher
selection/touch checks, Android Pokétch touch checks, digital-watch checks,
and second-display transport checks. Local LOVE previews confirmed the ROM
bezel/buttons and sharp lower-launcher text. Physical AYN Thor verification
remains to be done on an updated Android build after reimporting Platinum.
