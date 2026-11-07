# LÖVE 12 preview and voxel compute path

This is a staged migration, not a replacement of every platform runtime.
Upstream LÖVE 12 is a development build; 11.5 remains the stable release.
The source and Dramatic Shapes mod continue to work with 11.5.

## Windows preview

Build with Python's standard library:

```powershell
python tools/build_love12_preview.py --download
# Or reuse the verified outer GitHub Actions artifact:
python tools/build_love12_preview.py --artifact-zip tmp/love12-research/love12-main-windows-x64.zip
```

Run `dist/love12-preview/Start-preview.cmd`. This uses a separate
`Gen2Recomp-Love12Preview` save/settings identity; import a ROM in that profile.
The stable executable, global LÖVE installation and existing saves are not
replaced. Stable self-update payloads cannot override this preview's source.
The complete preview is also packed into
`dist/Gen2Recomped-love12-preview-win64.zip`.

`scripts/love12-runtime.json` pins upstream main commit
`b7daef0f7c1dc5888090f5d5b22d4eaf4ffd1d87`, artifact 10607357662,
and its official GitHub SHA256. The helper verifies the outer archive before
using its portable runtime, copies all DLLs from that same runtime, and never
executes the installer. Its download mirror is nightly.link; its bytes must
match GitHub's pinned digest. CI artifacts expire: an expired download needs
a reviewed new pin, not an automatic move to an unverified latest build.

The iOS build compiles LÖVE from source and pins the same commit in
`scripts/build_ios.sh`. It used to follow upstream `main`, so a release could
pick up an untested engine change. Move the pin deliberately and check the DS
field on a device when you do.

Sources: [upstream changes](https://github.com/love2d/love/blob/b7daef0f7c1dc5888090f5d5b22d4eaf4ffd1d87/changes.txt),
[artifact metadata](https://api.github.com/repos/love2d/love/actions/artifacts/10607357662).

## Rendering compatibility

LÖVE 12 transforms custom shader clip coordinates for its graphics backend.
Our 3D matrices already contain a canvas Y flip. `GraphicsCompat` in the mod
and `src/render/ClipSpaceCompat.lua` cancel the additional Y transform for
those custom shaders, preserving LÖVE's Vulkan/Metal depth conversion.
Ordinary 2D projection shaders keep LÖVE's normal transform.

Metal is the exception: LÖVE sets no Y flip there, so `love_ClipSpaceParams.x`
is always 1 and multiplying by it changes nothing, which leaves these shaders
upside down. `ClipSpaceCompat` negates Y outright when the renderer is Metal,
the first renderer tried on iOS. The mods' compat modules call it. There is
no presentation flip in `Renderer`; canvases reach it upright on every backend.
Metal itself is checked by simulation on OpenGL only, not on an Apple device.

Desktop 12 builds prefer OpenGL. On the tested RTX 3060, OpenGL 4.3 matches
the 11.5 terrain, shadow and reflection pixels exactly. Vulkan's primary
CPU/GPU terrain screenshots agree with one another, but an expanded versus
instanced reflection comparison failed; Vulkan is not certified for this
preview. `POKEPORT_GRAPHICS_BACKEND=vulkan` is an explicit development override.

## GPU generation and CPU fallback

The mod's **GPU MESH GENERATION** toggle defaults on. On a compatible LÖVE 12
driver, a compute shader expands each four-corner quad to six drawable
vertices in bounded buffers. Terrain classification, ROM decoding, topology
and scheduling remain CPU work. This does not move the whole mesher to the GPU.

The shader is compiled and a tiny real dispatch/readback validates the
driver while the mod loads, before walking. Live terrain builds do not read
GPU buffers back. Missing APIs, unsupported shaders, allocation failures or
dispatch failures select the CPU path. A failed block retains its original
corner data for CPU expansion; already completed parts remain valid. After
a compute failure that namespace stops retrying it. Turning the toggle off
uses CPU generation for new meshes without invalidating existing geometry.

The persistent cache remains the six-float CPU vertex format, reusable by
both runtimes. GPU storage uses explicit std430-compatible 32-byte alignment.

## Validation and remaining platform work

- Native 11.5 CPU fallback and native 12 OpenGL/Vulkan compute tested.
- 2,520 computed vertex channels equal CPU floats across workgroups.
- Unsupported shader, mid-build dispatch failure, explicit CPU selection,
  startup preflight and actual mod-loader initialization tested.
- Emerald Oldale, Route 114 and Route 119 screenshots; disk round trips;
  instanced/expanded shadows and reflections checked on OpenGL.
- Launcher and HGSS overworld captured under 12; HGSS custom model and sprite
  shaders compile and the scene is upright.
- Existing CPU stream/scheduler, cancellation, retirement and repeated
  eviction checks still pass.

Android still vendors its patched 11.5 runtime, Switch uses love-nx 11.5,
and iOS already builds a separate 12 source tree. Their native bridges,
packaging and hardware have not been rebuilt or certified here. Their CPU
mod improvements can ship independently of the Windows engine preview.
macOS, Linux packages, UWP and physical dual-screen/native bridge behavior
also remain unverified under the new engine. Do not change the stable
release workflow's 11.5 download URLs to a nonexistent 12 stable release.

GPU expansion alone did not produce a substantial overall map-load speedup
in the initial measurements. It is not a claim of hitch-free play or a
solution to all Switch/mobile frame drops.
