# Emerald location banners

The former banner used the selected dialogue border in a 160×32 box and the
dialogue face, without animation. Emerald now extracts all six popup themes
from the ROM: wood, marble, stone, brick, water and stone2. It also reads the
native section-to-theme table and the underwater palette. The composed frame
is 96×40 at the upper left, with an 80×24 interior. Text uses FONT_NARROW,
centered in 80 pixels, with its baseline origin at (8 + centered offset, 11).

Verified retail US offsets are background tiles 0x57C684, outline tiles
0x57DD04, six palettes 0x57F384, underwater palette 0x57F444 and section
themes 0x57F464. All five occur in LoadMapNamePopUpWindowBg's literal pools.
Art comes from the imported ROM; no replacement artwork is bundled.

The popup waits 31 ticks, slides down 40 pixels in steps of two, holds 121
ticks and slides out again. A new section encountered during a running
popup queues behind its exit. Script locks, successful interactions and
opening Start dismiss it. FLAG_HIDE_MAP_NAME_POPUP (0x4000) suppresses it
during native story sequences, and repeated entry into the same section
does not restart it. The Kanto section gap and underwater palette override
follow the native lookup rules.

Sources: [popup implementation](https://github.com/pret/pokeemerald/blob/master/src/map_name_popup.c),
[window geometry](https://github.com/pret/pokeemerald/blob/master/src/menu.c),
[popup suppression flag](https://github.com/pret/pokeemerald/blob/master/include/constants/flags.h).

Verification:

- `python tools/run_lua_check.py tools/emerald_popup_check.lua`: actual ROM
  extraction, every announcing map's theme, animation states, queued
  transitions, dialogue dismissal, story flag and Start menu dismissal.
- `EMERALD_REPO=<repository> lovec tools/emerald_popup_render`: six actual
  LOVE renders inspected in contact-sheet.png, including underwater.

The Emerald cache revision changed to regenerate these assets on import.
Existing cached imports need to be reimported. Mobile hardware and an emulator
framebuffer comparison have not been performed; complete Emerald parity is
still an ongoing task.
