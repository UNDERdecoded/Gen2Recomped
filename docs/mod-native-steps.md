# Native step deliveries

Mods declaring `"steps"` in their manifest receive a scoped public service:

```lua
if mod.steps:available() then
  mod.steps:sync()
end
local walk, diagnostic = mod.steps:poll()
if walk then print(walk.steps, walk.from, walk.to) end
```

Availability is a permission-safe probe. Sync and poll require the permission;
stale facades also refuse operations after rollback, reload or teardown.
Sync requests the existing asynchronous HealthKit/hardware sensor path, including
OS consent where needed. A refused or unsupported native request returns false.
No consent is requested by the availability probe.

Each mod receives its own cumulative delta, independently of other mods and the
native walker. Receipts survive mod reload and application restart. Poll returns
at most 50,000 steps, retaining the remainder for later polls; multiple native
updates may coalesce into one delivery. Optional from/to timestamps bound the
retained measurement window, rather than identifying individual footsteps.
The first receipt includes the retained native journal backlog for that mod ID.

The native producer exclusively owns `steps_journal.json`. Its version, source,
stable epoch, cumulative total, timestamps and native measurement anchor are
published together through atomic replacement. iOS serializes asynchronous
HealthKit requests; Android coalesces sensor reads and serializes publication.
Android counter reset reanchors without inventing steps and preserves the epoch
and cumulative total. A failed publication leaves the previous measurement
anchor available for retry. Large genuine backlogs are retained rather than
discarded at the former per-sync clamp.

Migration copies an existing legacy pending delivery into the first journal
before requesting consent or waiting for a sensor. Lua leaves that legacy file
alone on versioned hosts, avoiding a competing read/delete during migration.
The walker stores its cursor and credited state together; unsuccessful saves
are retried without duplicating live credits. Mods commit independent receipts
before a successful poll returns. A process exit between receipt commit and
the caller handling its return cannot be acknowledged by this API; no exactly-once
application transaction or filesystem power-loss/fsync guarantee is claimed.

The mod receipt ledger has a 256 KiB / 1,024-owner limit. Native snapshots are
limited to 8 KiB, totals to the largest exactly representable JSON integer, and
malformed, oversized or backwards snapshots fail closed. No engine or mod reader
deletes the producer journal. Existing initialized journals that disappear are
diagnosed by the native bridge rather than silently recreated from an old anchor.

The native `love.system.stepJournalVersion()` capability is required. Older
mobile binaries retain their existing native walker path and report the new mod
service unavailable. Desktop and console builds without the bridge report false.
New mobile binaries must include the updated Swift/Java and LÖVE bindings as well
as the Lua payload; a Lua-only update cannot add the native protocol.

Verification includes the actual loader and walker, multiple consumers, failed
receipt publication, save/reload, simulated pre-commit restart, migration and
bounded backlog tests. `tools/qualify_native_steps.py` compiles and exercises the
real Swift/Foundation and Java journal sources, typechecks HealthKit against an
iOS SDK when provided, sends both produced snapshots through Lua, and checks
receipt publication in a real isolated LÖVE filesystem. The Java host test uses
a POSIX rename shim; its JSON dependency is checksum pinned. Sensor accuracy,
OS authorization UI, complete Android JNI packaging, background suspension and
physical iPhone/Android acceptance require native build/device checks.

For a local qualification pass the Swift compiler, macOS SDK, optional iOS SDK,
JDK, pinned JSON jar, Lua and LÖVE paths to the tool. Local runs use `qa_storage`;
`--qa-tools` selects an external helper directory when the checkout has none.
