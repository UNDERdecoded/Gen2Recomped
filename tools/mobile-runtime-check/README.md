# Native mobile runtime capacity

Android currently links the vendored `android/<ABI>/libluajit.a` archives.
Source/header edits do not replace those archives. This builder creates new
isolated stock (60 captures) and experimental extended (120 captures) libraries,
matching public headers, an Android interpreter and a linked C API probe for
each selected ABI. It preserves the vendored source, existing binaries and
LuaJIT copyright notice. No application or player data is copied.

The source version is bound to the existing Android headers. Compilation uses
NDK 25.2.9519653 in CI, API 23 by default and Lua-5.2 compatibility in both
variants. Linux uses a matching 32/64-bit host toolchain; macOS supports the
64-bit cross-builds. The command layout follows the upstream
[LuaJIT cross-compilation instructions](https://luajit.org/install.html).

```sh
python3 tools/mobile-runtime-check/build_android.py \
  --ndk /path/to/android/ndk/25.2.9519653 \
  --abi arm64-v8a --output .local/qa/android-runtime-test/candidate
```

Every candidate includes the existing closure/debug/bytecode probe and a C API
executable linked against the same headers and static library. The builder
checks target ELF architecture and records hashes. Its reports explicitly keep
`targetExecutionQualified` and `releaseSelectable` false: Android execution and
the actual LÖVE/JNI/thread/FFI boundary must be exercised before packaging can
select a candidate. The existing application continues to use its current
runtime until that qualification and selection work is complete.

The workflow also executes both x86-64 candidates on an owned API-30 Android
emulator through `check_android_target.py`. Transfers are hash-checked before
the closure/debug/bytecode/GC and linked C API tests run. The tool requires an
explicit emulator serial, writes only its unique temporary directory, and
removes its own files afterward. ARM and 32-bit execution remain separate
requirements. This standalone VM test does not replace the LÖVE/JNI/thread/FFI
host gate, so its report also keeps release selection disabled.

iOS needs separately built Apple framework slices and interpreter-mode
qualification. Switch needs a rebuilt runtime and target execution. These
build artifacts establish neither full platform parity nor original-mod
startup, rendering or gameplay acceptance. Local QA uses the shared 20 GiB
reserve and owned output leases.

## Actual Android app-host gate

`qualify_android_love.py build` copies the tracked, fully materialized Android
source into one owned QA directory, selects x86-64 there and builds two distinct
test APKs through the existing Gradle/LÖVE/JNI project. Each uses the exact
stock-60 or extended-120 archive and matching headers from a candidate receipt.
The source checkout and normal application runtime are preserved. A fresh
application ID and provider authority prevent overlap with an installed game.
Only the small ROM-free payload is embedded; no mod, cartridge or player save
is copied.

```sh
python3 tools/mobile-runtime-check/qualify_android_love.py build \
  --build /path/to/android-runtime/candidate \
  --output .local/qa/android-love-build/candidate
python3 tools/mobile-runtime-check/qualify_android_love.py run \
  --serial emulator-5554 --build .local/qa/android-love-build/candidate \
  --output .local/qa/android-love-run/candidate
```

The build needs the pinned SDK/NDK, JDK 17 and a complete Android checkout.
The run refuses physical devices and existing app installations. It installs
only its fresh test apps on an explicit emulator, checks interpreter/JIT,
closure/debug/bytecode/GC behavior inside the real LÖVE 11.5 host, calls an FFI
callback, executes a separate LÖVE thread VM and verifies filesystem bindings.
Reports are written inside each test app's private directory; only installations
created by that invocation are stopped and uninstalled. Candidate, APK and
source hashes bind the evidence to the actual built inputs.

The `Android LÖVE runtime host` workflow performs this x86-64 acceptance gate.
Its result must be inspected before claiming host qualification. Reports keep
release selection disabled: ARM/32-bit and physical devices, rendering, input,
full original-mod gameplay, iOS and Switch still require their own acceptance.
