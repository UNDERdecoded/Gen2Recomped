# Native callback failures in diagnostics

An entry can load successfully and fail later in `game.ready` or another
event. Such errors must reach the active loader's `status().errors` feed as
well as the log. Otherwise a mod's engine-error page and a smoke-test driver
can report an empty list while an installed capability failed to initialize.

The native event bus attributes the event name and original cause to its
subscribing owner. It continues dispatching remaining listeners. A repeatedly
failing listener reports once until it recovers, changes its error or uses a
different diagnostics feed. This avoids per-frame log/feed growth for the
same persistent failure. A retired bus cannot add errors to a new session.

This makes missing engine contracts visible; it does not implement those
contracts or turn an incomplete client initialization into successful gameplay.
ROM-free coverage uses real SDK registration, the native bus and loader status,
including repetition, recovery, ownership and session replacement.
