# Xbox controller (Gen 4 and the launcher)

SDL game-controller mapping through `love.gamepad*` (an "Xbox One For Windows"
pad reports as a gamepad; the triggers arrive as axes and are edge-detected at
0.5 / 0.3 in `Input.AXIS_BUTTONS`). Raw `joystick*` events are used only for
sticks SDL has no mapping for.

| Xbox | Action | Gen 4 meaning |
|---|---|---|
| A | A | confirm / talk / tap (cursor mode) |
| B | B | cancel; hold to run in the field |
| Y (north) | X | field start menu (DS X) |
| X (west) | Y | registered key item (DS Y) |
| Start | Start | start menu |
| Back/View | Select | Select (reorder moves / bag items, Pokétch clear) |
| LB | L | raises the Pokétch from the field (L or B lowers it) |
| RB | R | next Pokétch app; camera tilt in the field |
| D-pad / left stick | directions | move, menus (held = repeat) |
| RT | TOUCH | toggle the lower-screen cursor (below) |
| LT | CHAT | online chat only |
| L3 / R3 | zoom out / in | field zoom |

All rows are rebindable in the CONTROLS screen (pad capture works for buttons,
triggers and right-stick directions; the TOUCH row is new).

## Left stick

Press at 0.5, release under 0.3. Eight-way input maps to four directions with
a 1.3x diagonal bias: a held direction keeps its axis until the other axis is
clearly stronger, so a 45-degree wobble does not flip between two directions.
With two controllers the one deflected furthest drives the stick; each pad has
its own button sources, so two pads holding a button are one press and the
button stays held until both release.

## Lower-screen cursor (the DS touch screen)

RT toggles a crosshair in the bottom screen's 256x192 space (dual-screen games
only). While it is on: left stick and D-pad move it (the stick is quadratic for
fine control), A presses and drags (hold A and move), and every other button
keeps its normal job (B still backs out). It maps through
`SecondScreen.fromLocal`, the inverse of what every screen's touch handler
already does, so it works in swap, inset, vertical/horizontal and `display`
modes and drives every pointer-only screen: Pokétch apps (drawing pad,
dowsing, calendar, calculator, roulette, move tester, party apps), the battle
bag/party touch screens, Underground, contest and photo dress-up, Poffin
cooking, mining, naming-screen touch keys. It switches itself off whenever the
top screen changes (so the stick can never stay stolen), and refuses to start
over the field when no lower screen is showing.

Pokétch without the cursor: LB opens it, D-pad left/right or RB change app, A
presses the app's main button, B/L/Start close.

## Hotplug

`love.joystickadded` is forwarded (the touch overlay steps aside); removal
resets input and lifts the virtual finger. Controllers added or reconnected
mid-game send ordinary gamepad events.

## Tests

`python tools/run_lua_check.py tools/gen4_xbox_pad_check.lua`
