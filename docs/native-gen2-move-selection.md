# Native Gen2 move-selection screen contract

FIGHT now exposes the native Gen2 screen phase `moves`, allowing existing
presentation clients to paint their move controls. `playerMoves()` reads the
actual current chooser’s move instances and PP, including temporary movesets.
The existing controller still owns navigation, cancellation and turn resolution.
Other generations retain `moveSelect`; older Gen2 `moveSelect` states remain
valid for native input and classic/wide rendering.

ROM-free regression checks drive actual FIGHT, navigation, cancellation,
reopening and native turn/PP resolution across Gen2 and other editions. They
also observe actual native move-name drawing and current moveset identity.
These checks do not establish complete mod, GPU or release compatibility.
