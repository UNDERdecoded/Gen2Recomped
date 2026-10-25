# Experimental runtime upvalue qualification

The native engine's current stock LÖVE runtime accepts at most 60 captured
locals per Lua function. A supplied Gen2 structural renderer extension exceeds
that limit, although its original base module compiles. Increasing the engine
API surface cannot make that generated function compile in a VM with the same
limit.

The patch here is an **experimental dependency patch**, not an engine-side
source rewriter. It applies to LuaJIT commit
`a4c064539ea931274d407e1249b4bb575424a0f4` and raises `LJ_MAX_UPVAL` to 120.
The recorder's own source notes a 127 limit; this is not proof that every
architecture is safe at 120. The tools do not modify an existing installation.
Packaging must explicitly select qualified components as described below.
No supplied renderer source/assets or cartridge data are included.

Always use a separate clean dependency checkout/build directory. On macOS the
local experiment builds with `MACOSX_DEPLOYMENT_TARGET=11.0` and
`make -j4 XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT`. Its LÖVE test app is a separate
copy with an arm64-only replacement Lua framework and ad-hoc signing. The
original stock app and dependency checkout remain unchanged. That local
experiment alone does not qualify Windows or a universal Mac app; the native
matrix and component staging below cover those separate requirements.

## Reproducible qualification builds

`qualify.py` builds both variants from the same clean, pinned Git input, without
modifying that checkout. It refuses existing output directories and checks that
the dependency patch applies to the pinned blobs. On local participating
checkouts it uses the shared QA storage leases. For example:

```sh
python3 tools/runtime-upvalue-check/qualify.py \
  --luajit-source /path/to/clean/LuaJIT \
  --output .local/qa/runtime-capacity-test/candidate --engine-tests
```

The Windows build requires an x64 MSVC developer environment. Unix uses the
host C compiler and make; macOS defaults the deployment target to 11.0 unless
the caller explicitly supplies one. The output includes per-step logs, a
source/tool/library hash report and separate licensed stock/extended artifacts.
These are qualification artifacts, not a replacement installation or a release.

On Windows the builder explicitly selects MSVC's linker and Git for Windows
Bash, avoiding the unrelated Git Unix `link` utility and System32's WSL
launcher. Shared fixture source paths accept Windows separators, and tests
that inspect source/text goldens normalize checkout CRLF only. Their native
behavior checks and reviewed fingerprint values are unchanged.

The `Native runtime capacity` workflow schedules this same check on Linux x64,
Windows x64, Intel macOS and arm64 macOS using explicit
[GitHub runner labels](https://github.com/actions/runner-images#available-images).
Both variants must pass the closure/C API checks and the engine's quick tiers;
the workflow does not publish a GitHub release.

On Windows and both macOS architectures, `love_abi.py` additionally checks the
candidate inside a separate copy of the actual pinned LÖVE12 host. It verifies
the official artifact's SHA-256 before extraction, requires the passing engine
qualification and exact candidate library hash, then runs both stock and
extended closure probes, an FFI callback and a secondary LÖVE thread VM. Each
host uses a unique QA identity; graphics and audio are disabled. Only reports,
logs and licensed candidate components are uploaded, not an application or
game profile. macOS adjusts the copied framework's install name and ad-hoc
signs and verifies that copied app. This is a host ABI gate, not a GPU or
gameplay test, nor proof that a universal app has been packaged correctly.

For an already qualified local macOS library:

```sh
python3 tools/runtime-upvalue-check/love_abi.py \
  --runtime-archive /path/to/pinned/love-macos-artifact.zip \
  --qualification .local/qa/runtime-capacity-test/candidate/report.json \
  --library .local/qa/runtime-capacity-test/candidate/artifacts/extended/libluajit.so \
  --output .local/qa/runtime-host-test/candidate
```

## Qualified desktop components

After every native matrix job passes, the workflow combines the two Mac
libraries and stages the Windows library as `qualified-desktop-runtime`.
`component.py` verifies the capacity/host receipt pairing, the exact library
bytes, native architecture, both variants' engine/C API gates and a matching
engine source tree. The universal Mac library must contain both original
qualified slices byte-for-byte. It includes the LuaJIT license notice and
original receipts. These artifacts contain no application, ROM or mod data.

The engine tree is recorded at qualification time and must still match the
source selected for packaging. Older reports without that binding are not
eligible components. The local staging command uses QA leases and refuses
existing outputs. Given the separately extracted native CI artifacts:

```sh
python3 tools/runtime-upvalue-check/component.py --platform macos \
  --candidate /path/to/runtime-capacity-macos-x64 \
  --candidate /path/to/runtime-capacity-macos-arm64 \
  --output .local/qa/desktop-components/candidate/macos
```

`build_native_preview.py --qualified-runtime /path/to/component.json` opts
into that platform's checked component. It still verifies the official host
archive, copies only into its own package, preserves preview isolation, and
records the override and final installed-library hash. The Mac framework is
renamed/signed only in that package. The normal builder default remains the
official stock runtime. `package_native_release.py` accepts paired
`--windows-runtime-component` and `--macos-runtime-component` inputs; an
extended-runtime release cannot silently ship only one qualified platform.
The standalone `.love` still needs the corresponding extended runtime.
The Mac minimum system version is read from the actual library load commands;
the package raises its advertised minimum when necessary and records it in
the manifest and README. A component cannot lower the base app's requirement.

Component and package checks do not replace actual fused-application GPU,
input, gameplay or long-session verification before release claims.

## Individual probes

From the engine repository root, run both interpreters:

```sh
/path/to/stock/luajit tools/runtime-upvalue-check/check.lua 60
/path/to/experimental/luajit tools/runtime-upvalue-check/check.lua 120
```

The ROM-free Lua probe exercises interpreter and JIT calls, shared sibling
captures, repeated full GC, high-index debug reads/writes and bytecode round
trips at 1, 8, 32, 60, 61, 64, 96 and 120 captures. Unsupported counts above the
selected minimum are reported; rejection at/below the requested minimum fails.
Debug replacement of constant upvalues flushes existing traces first, matching
[stock LuaJIT's debug-surgery behavior](https://github.com/LuaJIT/LuaJIT/issues/968).
An earlier probe omitted that flush and failed at 64 in its JIT phase; that
result is retained as an invalid test assumption, not a successful VM result
or a reason to silently disable JIT for large closures.

Compile `c_api.c` against the *same candidate headers and static library*, then
run it with 60, 61, 64, 96 and 120 as arguments. It pushes those captures through
the actual Lua C API, repeatedly invokes the C closure and collects garbage.
For example on macOS:

```sh
cc -I/path/to/candidate/src tools/runtime-upvalue-check/c_api.c \
  /path/to/candidate/src/libluajit.a -lm -o /path/to/own-output/c-api-upvalues
/path/to/own-output/c-api-upvalues 120
```

These microchecks must accompany engine regressions and real GPU verification.
A generated extension compiling/initializing is not proof that all its Pokemon
models, movement, combat, shadows and other effects are equivalent to Gen1.
Native platform, architecture packaging and dependency ABI gates must pass
for the selected source before packaging. They do not establish Windows GPU,
complete native renderer/gameplay, long-session or saved-bytecode migration
acceptance. See the source-bound runtime experiment receipt under
`docs/qa/native-foundation/` for completed evidence and exact limits.
