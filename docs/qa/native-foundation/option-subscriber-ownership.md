# Native lifecycle and option subscriber ownership

Wrappers installed by a native option toggle or action must belong to the
subscriber that installed them, so the existing source-call attribution and
owner teardown can find them. Synchronous `mods.loaded`, `game.ready`,
`mod.options_changed` and `mod.option_action` callbacks on the current session's
bus now use the existing shallow mutation journal with their actual owner.
The old aggregate lifecycle journal remains for coroutine callers. Callback
coroutine identity, event ordering, error containment and the native frame-event
paths are retained. Unknown/foreign later replacements remain untouched by an
owner's unwind. This does not capture arbitrary per-frame module mutations.

A retained require closure loses its snapshot references and namespace admission
authority when the window closes, including a close during module loading.
Close is idempotent. Journal execution preserves trailing nil return values.
No private controller body, manifest rewrite or alternate gameplay loop is used.

Qualification on fork main `73b2c0f8`:

- Frozen source `18e8a8ee37`: 168 selected CPU groups pass, including 133 new
  checks through actual SDK loading, the native options manager, action rows,
  five GBA editions and Crystal. Focused run `4a7aafe473`: 10 groups pass.
- The identical 133-check fixture on unmodified native predecessor `83836402`,
  run `90b90e0413`, reproduces 44 failures. Native controllers were not overlaid.
- Older-public component `5987b723`, composition `5ab6f3e79f`: 64 groups pass,
  including the same 133 checks and 17 native diagnostic checks. It retains the
  older classic event walk, reuses the already offered namespace-journal
  prerequisite, and adapts attributed errors to its existing Runtime feed.
  The Loader change is a checked four-line hunk over the previously qualified
  older composition, not a replacement with the newer Loader.
- The fork's 10,000 single-listener event probe remains at 0 KB allocations on
  its lean path with JIT off. This is a frame-event allocation check, not FPS
  or older-public lean-path acceptance.

These are local CPU qualifications; hosted CI and unchanged-mod GPU acceptance
of this packet remain separate. The earlier Ruby scene qualification predates
these event changes. Typed contact continuation and Action Card remain pending.
All runs use owned QA profiles/copies and a 20 GiB free-space floor, preserving
the requested 8 GiB reserve. No player profiles or private mod files are edited.
