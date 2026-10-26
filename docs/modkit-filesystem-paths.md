# Absolute mod directories in the SDK harness

`T.sdk.loadMod()` aliases the selected directory into the loader's `mods/`
search path. Previously, passing an absolute directory caused `tests.fs_io`
to prepend its repository root anyway. An existing `/external/mod` became
`.//external/mod`; discovery then found no mod and could return zero loader
errors without executing its entry chunk.

The IO adapter now preserves absolute paths for every filesystem operation.
Relative paths continue to resolve beneath the configured root. Windows
drive-rooted, UNC and current-drive-rooted paths follow the same rule;
`C:relative.lua` remains relative. This changes the test adapter, with no
production Lua source or game/save format changes.

The new SDK case uses an immutable, ROM-free mod fixture in a directory
containing a space. It checks relative and absolute discovery, an absolute
mod outside an explicitly configured root, actual entry execution,
`mod:read()` bytes and a merged item patch. A zero-error empty load fails
these assertions. It also checks all five adapter operations against both
platform policies. Windows path-policy checks are simulated; the real-disk
checks were executed on macOS, not on a Windows machine.

Run from the repository root:

```sh
POKEPORT_DATA_DIR=tests/fixture_data luajit tests/modkit/cases/filesystem_paths.lua
POKEPORT_DATA_DIR=tests/fixture_data luajit tests/run_modkit.lua
```

The targeted case passes **77/77** checks and the SDK tier passes **4/4**
suites. Loading the unchanged parent adapter instead fails **38/77**
checks, including actual absolute mod discovery and entry execution.

The separate legacy `tests/modkit_tests.lua` developer-tooling suite was
also compared with a ROM-free Data bootstrap and `MODKIT_LUAJIT` set to the
test interpreter. Both adapters pass **126/129** checks with exactly the
same three failure lines: the expected default fallback move and two
console text-entry checks. Those existing failures are not counted as a
green suite. Initial runs with missing Data initialization or interpreter
configuration were retained separately from this comparison.

The [verification receipt](qa/modkit-filesystem-paths.json) pins the parent,
changed files and local log hashes. Full gameplay, whole-mod compatibility
and hosted CI are separate acceptance scopes.
