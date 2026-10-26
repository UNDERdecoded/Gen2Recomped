# Native background jobs

Mods declaring the `background` permission receive `mod.job`. Its
`available()` method returns false without that permission or without the
required LÖVE thread facilities. Other methods require the permission.
The existing `compute` permission remains the separate direct-thread API.

```lua
if mod.job:available() then
  local handle, err = mod.job:run("workers/prepare.lua", {count=10000},
    {maxSeconds=5})
  -- Retain handle and poll it from a later update callback.
end
```

The worker file is relative to its own mod, contains source Lua, and receives
the argument as `...`. Its return value becomes the result. Arguments,
results and progress contain plain acyclic tables, finite numbers, strings,
booleans or nil. Functions, userdata, metatables and engine objects cannot
cross Lua states. Numbers retain double precision. Each argument/result
message is limited to 4 MiB, 100,000 nodes and 16 nesting levels; progress
messages are limited to 64 KiB and retain only the latest update.

`mod.job:poll(handle)` returns a detached table with `status` equal to
`pending`, `ok`, `error` or `cancelled`, plus `result`, `err` and `progress`
where applicable. False and nil are valid successful results. Polling does
not consume a result. Call `release(handle)` after processing the result.
`cancel(handle)` requests cancellation; `release(handle)` also cancels any
pending work and retires its public handle. Handles belong to one loader
and mod. Unknown handles return an error status or false for cancel/release.

At most two retained handles per mod and four workers globally are allowed.
A released worker continues to occupy its physical slot until its thread
has actually stopped. The default time budget is five seconds, capped at
30 seconds, or 300 seconds with `assetIO=true`. Script source is limited to
2 MiB. Invalid options, paths and unavailable workers return `nil, reason`
from `run`.

Workers have copied math/string/table helpers, guarded protected calls and
coroutines, and `job.progress(value)`. They cannot access `love`, `mod`,
`io`, `os`, `ffi`, `debug`, `package`, a module loader, or host filesystem
paths. Worker JIT is disabled so instruction hooks can interrupt Lua loops,
including loops in protected calls and coroutines. A native C function may
finish before a Lua hook can run. This is not a per-VM memory quota.

With `{assetIO=true}`, workers additionally receive:

| Method | Behavior |
| --- | --- |
| `job.imports:info(id)` | Metadata for a declared mod import |
| `job.imports:read(id, offset, length)` | An explicit bounded range using the existing import rules |
| `job.cache:info(key)` / `exists(key)` | Inspect this mod's byte cache, including its own staged output |
| `job.cache:read(key)` | Read a staged or existing byte value |
| `job.cache:write(key, bytes)` | Stage byte output for publication after successful completion |

Import data is read only. Cache output reuses the native mod cache and is
limited to 64 MiB per value, 256 MiB and 256 keys per job. Staging files are
verified in chunks. A failed or cancelled job preserves the previous cache;
a successful job publishes all its staged keys before reporting `ok`.
A private journal recovers interrupted publication when the cache next
opens. These are application-level recovery rules, not a filesystem power
loss/fsync guarantee. Invalid cache keys abort the job without publishing.

CPU work runs in a separate Lua state. The main update loop brokers scoped
I/O and commits, so large file operations can still cost frame time. Data
folder changes abort pending work. Reload, rollback, returning to the
launcher and accepted application quit cancel owned jobs; an editor quit
veto preserves them.

The ROM-free probe runs through
`python3 tools/qualify_native_jobs.py --love /path/to/love` (`lovec.exe` on
Windows). Local Unix runs require the workspace's `qa_storage` helpers; if
they are outside this checkout, pass `--qa-tools /path/to/their/directory`.
It bundles only the test and worker bootstrap dependencies, uses
a fresh QA identity, and verifies real worker completion, scoped reads,
transactional output, timeout, cancellation and physical thread retirement.
These checks do not establish GPU rendering, phone/console launch or gameplay.
