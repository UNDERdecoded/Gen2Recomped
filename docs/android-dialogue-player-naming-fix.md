# Textbox docking and Platinum player naming

TextBox previously registered only its conventional rectangle for dynamic UI
docking. Platinum paints its caps one tile farther left and two farther right;
FireRed paints one tile farther on each side. Those caps were left behind in
the centered UI pass when the rest of the box moved to the safe-area bottom,
making them appear higher on tall phone screens.

Font.dialogueBoxBounds now reports the painted footprint. TextBox registers
that complete footprint so all border tiles move together. Ordinary Gen1/2
frames, Emerald's nine-tile frames, unframed windows, and undersized fallback
frames retain their original bounds.

Rowan's player-name prompt passes `female` for its header sprite, including
false for boys. Screens' Gen4 NamingScreen alias omitted that option, so both
player prompts declined the Gen4 keyboard. Rival naming passed no such option
and worked. The whitelist now includes `female`, which Gen4NamingScreen already
supports. Boy/girl player names, rival names and nickname routes are checked
through the real screen factories and callbacks.

Checks cover every supported version's frame convention, portrait/landscape
and desktop viewports, DPI 1/1.5/2.755 and a mobile bottom safe-area inset.
Local LOVE previews using extracted Emerald and Platinum assets confirmed
aligned side borders through the real renderer's docking pass. Hardware Android
verification is pending. These changes require a new build, not a ROM reimport.
