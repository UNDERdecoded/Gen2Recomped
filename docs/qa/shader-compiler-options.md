# Shader compiler options and canvas orientation

Explicit native-coordinate shaders must not be normalized a second time. The
compatibility compiler now recognizes `POKEPORT_NATIVE_CLIP_SPACE` and
`POKEPORT_LEGACY_CLIP_SPACE_ADAPTED` in the compiler's `defines` option, as well
as in source. Both named definitions and the array form preserve their original
arguments, including filenames, FileData, and the options table. Definition
presence counts even with a value of zero or false, matching the preprocessor.

This path avoids an additional file read, comment scan and source allocation;
no frame-rate improvement is claimed. A preprocessor guard also preserves
definitions supplied by inherited compiler options without inspecting option
metatables in the Lua wrapper. Identifiers with an `_EXTRA` suffix are distinct
and do not disable legacy normalization.

## Reproduction

Run `tests/engine/legacy_shader_compat.lua` with the engine test runner. For GPU
verification, set `SHADER_OPTIONS_ENGINE` to this checkout, an unused isolated
`POKEPORT_IDENTITY=oasc-gen2recomp-qa-shader-options-<unique>` and
`POKEPORT_GRAPHICS_BACKEND` to `opengl` or `metal`, then launch
`tools/shader-options-check` with LÖVE 12. Optional `SHADER_OPTIONS_OUT` saves
the native and independent reference portrait images. Run GPU backends serially.

The checker compares the wrapped compiler with the runtime's unwrapped
constructor, checks an independently upright reference, and verifies that
invalid shader sources still fail. It exercises combined/split source,
filenames/FileData, map/array/inherited definitions, direct/table render targets,
four sizes including portrait, and DPI scales 1 and 2. Native and already-adapted
definitions remain unchanged; ordinary matrix-based 2D and default legacy
coordinates retain their previous orientation.

## Source-bound results

- Production module SHA-256:
  `c99b3c9b9ab8be4801ba894cb2bfb7cc0d2deb88cb8de24adff8554bed863dca`.
- GPU checker SHA-256:
  `29539a3d522a8369347369b2fd312309d1743755200337800e6990ed9c065fba`.
- LÖVE 12 build `937eb3b`, macOS: OpenGL and Metal each pass **510 checks and
  240 exact full-RGBA image pairs** on those bytes.
- Existing legacy orientation GPU checker: **304 checks / seven cases** on each
  backend, including embedded HUDs, culling, matrices and state restoration.
- Independent upstream patch: **119/119** targeted CPU checks. Composed fork:
  **324/324** engine suites, **3/3** SDK suites, and B30 profile pass.
- Before correction, the new GPU checker fails because a shader explicitly
  marked native in compiler options is rewritten. Previous production module
  SHA-256: `b23fd6d20f136f54f78793839151a5f8d0abd76793da7eb541fc5802a47d00ca`.

A fresh unchanged supplied Johto package also failed before camera verification
with a dynamically generated function exceeding LuaJIT's 60-upvalue limit. The
same package inventory fails identically on the parent composed fork without
this correction. Both failures are retained; neither is gameplay acceptance.
Windows GPU execution and full mod compatibility remain unverified. No ROMs,
mod sources/assets, imported caches or player profiles are included.
