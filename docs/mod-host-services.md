# Native date/time and device services

Mods can format a captured Unix timestamp with the live game's presentation
preferences:

```lua
local date = mod.datetime:date(game, capturedAt)
local time = mod.datetime:time(game, capturedAt)
local combined = mod.datetime:dateTime(game, capturedAt)
local state, percent = mod.device:powerInfo()
```

The native Options menu exposes DATE FORMAT (`DEVICE`, `DD-MM-YYYY`,
`MM-DD-YYYY`, `YYYY-MM-DD`) and TIME FORMAT (`DEVICE`, `24 HOUR`, `12 HOUR`).
They use the existing shared options file and cannot be overridden by generation.
The generation-specific Options screens reuse these engine rows. DEVICE reads
the existing process time locale without changing it; C/POSIX or unavailable
locales fall back to day-first dates and 24-hour time. Explicit time formats
display hours and minutes. Invalid or missing timestamps return `----`, never
the current time. Formatting changes no game state.

Power information delegates to the host's existing LÖVE power service. The
state is `unknown`, `battery`, `nobattery`, `charging`, or `charged`; percent
is an integer from 0 through 100, or nil when unavailable. Unsupported hosts
and native probe failures return `unknown, nil`. Each mod receives its own
facade and no other `love.system` operations. Neither service needs a permission.

Verification: `luajit tests/engine/native_host_services.lua` covers formatting,
locale preservation, shared option persistence and menu rows, per-mod facade
isolation, native power failures and installation through the actual mod loader.
This does not verify battery reporting on physical phones or consoles. Step
deliveries and log uploads are separate services and remain outside this change.
