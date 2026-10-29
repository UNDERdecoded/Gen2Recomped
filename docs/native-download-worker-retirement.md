# Physical download worker retirement in transport QA

Prepared on the existing offered HTTP/logging PR273 head523bf0bd. Production
transport and request/queue bounds are unchanged. The actual worker fixture
forwards original responses before reporting native request completion on a
QA-only channel. Before filling the queue, it waits for preceding physical
responses; a separate real-worker barrier proves that cancellation retains a
credit until physical retirement and returns exactly one credit afterward.
The existing cold-start/publication barriers, overflow, cancellation,
file-preservation and shutdown checks remain active.

This also carries the independently qualified newer cold-start/publication
test synchronization into this older offer. Its existing45-second external
fixture process deadline remains unchanged. A newer fork composition passes
the actual official LOVE11.5 TLS fixture (1512checks), all949/4 official
ROM-free suites and70CI checks. Those receipts do not qualify this older
combined host. Its own committed source `d8c7deb0` independently passes the
actual official LOVE11.5 owned-loopback TLS fixture:1521 checks/595pump ticks
in6.98seconds, with the original45-second process deadline unchanged. All134
regular runtime files match the official archive byte-for-byte. Receipt:
`upstream-download-retirement-1793247736116883000/receipt.json`. The installed
storage helper manages the ephemeral fixture, processes and unique profile;
only Python process/storage ownership is instrumented, not Lua assertions,
worker responses or transport behavior. No GPU, release,
all-sprite-download or selected actor-art acceptance is claimed.

Integration/tests by Roxas2712 are offered under
https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md,
including its specific Cedric / UNDERdecoded permission with visible credit.
Existing authors' rights, source notices and prior grants remain applicable.
