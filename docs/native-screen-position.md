# Native screen positioning

The source Gen1/Gen2 option `screenPos` selects CENTER, UPPER or TOP. The
newer fork listed that key in its Gen2 video group but had no descriptor,
runtime module or compositor application. This older native host also lacks
the setting and source helper. Add the actual option, apply it on load,
and keep the default CENTER geometry.

`ScreenPosition` retains the source normalization/cycling/lift contract.
The native renderer applies the lift in whole framebuffer pixels, converts
it using its actual vertical DPI, and shares the result between world and
UI origins. The world canvas grows below the raised camera to keep covering
the window. Source Game2 drawable queries and native Gold menu queries
observe the same positioned rectangle. Safe-area top insets bound the lift;
active touch-skin and native split-screen owners keep their own origin.
Selecting a position while a skin owns the viewport leaves the stored
selection intact and displays SKIN.

The source helper is adapted from Gen1Recomp revision
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, copyright BOIS CLUB GAMES, LLC,
under the retained GPLv3/Section 7 terms in
`licenses/GEN1RECOMP-TOUCH-SKINS.md`. Native integration by Roxas2712 retains
those terms. No mod, protected Gen1 install or player profile is changed.

Implementation `f137c679` passes 1,145 selected contract checks across eight
editions, portrait/landscape/Retina sizes, all three positions, safe insets,
the actual skin parser, source queries and native option input/save/boot
application. Existing frame-query 4,454, chrome 116, viewport 56, skin 59,
playfield 585 and battle-window 315 checks also pass. A later probe adds
actual final world/UI blit observations; that extended probe has not yet
been run at this checkpoint.

Complete composed-tree tests, actual GPU/window acceptance, every custom
skin/device and final release qualification remain open. This offer is stacked on PR397 and its existing viewport/chrome prerequisites.
It uses this older host's actual `Renderer:endFrame` and flat options menu,
without adding the newer fork's `frameRects` or grouped-menu methods. Its independent qualification on offered source `b83c8fa4` passes 1,031
screen-position checks, including actual world/UI blits and real flat-menu
input/save/boot application. Its existing 4,454 frame-query and 116 chrome
checks also pass. The managed frozen host is cleaned after successful exit.
These are selected plain-Lua/compositor-stub proofs, not GPU or full-suite
qualification of this older host.

Existing engine authors' rights remain effective. Independently owned integration/test
contributions by Roxas2712 are offered under
<https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md>,
including the specific Cedric / UNDERdecoded permission with visible credit.
The source helper and its integration retain their existing GPLv3/Section 7
provenance and terms; that offer does not narrow earlier grants.
