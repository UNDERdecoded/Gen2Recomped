# GBC colour correction

Gold, Silver and Crystal can display cartridge RGB values through an optional
GBC display-response model. In **OPTIONS -> GBC COLOR**, choose **OFF**,
**ACCURATE** (SameBoy's Modern Accurate) or **HARSH** (Harsh Reality). The
launcher also offers **GBC COLOR (GEN 2)** under game defaults, including
per-generation overrides. The selection takes effect immediately in game.

OFF is the default and leaves the original render path unchanged. The option
does nothing on other generations or in OG, OG INV and CLASSIC monochrome
modes. The saved preference is retained when switching those modes.

ACCURATE corrects the GBC brightness curve and green/blue mixing while keeping
black and white. HARSH additionally models the original LCD's reduced contrast
and tinted black/white points. Neither is a calibration for a particular
physical screen or its lighting. Both use the CGB model with neutral light
temperature; this does not emulate an AGB panel or SameBoy's light-temperature
slider.

The colour mapping is adapted from
[SameBoy Core/display.c](https://github.com/LIJI32/SameBoy/blob/26a56bd6a122a6318a456abd80558408742d5adf/Core/display.c#L339),
`GB_convert_rgb15`, revision `26a56bd6a122a6318a456abd80558408742d5adf`.
Its Expat notice is retained in [licenses/SameBoy.txt](../licenses/SameBoy.txt).
See also [SameBoy's mode documentation](https://github.com/LIJI32/SameBoy/wiki/GB_set_color_correction_mode).

The renderer uses a cached 256x128 lookup texture per profile and a simple
two-sample shader. Interpolation between RGB555 entries keeps true-colour mod
gradients smooth. It processes the native world/UI composite before mod
post-processing and the independent GBC FX grid/glare. Launcher chrome and
touch controls are outside that composite. Mods taking over `render.compose`
own their presentation and bypass this native pass.

Enabling correction adds one screen-sized colour pass. Shader failure falls
back to the original image. Changing it does not modify caches, ROM-derived
palettes or gameplay state and needs no reimport.

## Verification

`luajit tests/engine/gbc_color_correction.lua` compares all 32768 RGB555 inputs
per profile with digests produced by compiling the pinned upstream conversion
function (CGB_E, neutral temperature). The hash starts at zero and processes
RGB bytes in increasing RGB555 order, `hash = (hash * 33 + byte) mod 2^32`.

`love tools/gbc-color-check` runs GPU checks with synthetic colours: desktop
and GLES shader validation, the entire RGB555 gamut, interpolated colours,
alpha/state preservation, DPI/resize handling and the native renderer path.
It uses a separate save-directory identity and no cartridge data. These
checks do not substitute for a real-ROM visual comparison or mobile hardware
testing.
