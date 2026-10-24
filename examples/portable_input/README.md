# Portable input overlay example

Copy this directory into `mods/`. The same `main.lua` runs on Gen1Recomp and
Gen2Recomped. `exports.events` journals the three raw input hooks;
`exports.capture(true)` captures complete input events and `capture(false)`
forwards them. `exports.stop()` removes the subscriptions. The exported `api`
lets the headless contract runner add further public wrappers for error and
priority checks.

Keep capture paired across presses and releases. Forwarding a press and
swallowing its release leaves that native input held. The example starts
with capture disabled and leaves native input active.

The manifest uses API 2 for compatibility with current standalone hosts. The
contract checker also loads this exact entry chunk with unified API-2 and
API-3 manifests when those host features are installed. See
[the hook contract](../../docs/portable-input-hooks.md).
