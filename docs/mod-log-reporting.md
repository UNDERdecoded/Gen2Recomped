# Fixed-destination log reporting and bounded native HTTP

Declare a fixed HTTPS `log_url` and the `network` permission in the manifest.
API 2/3 reject invalid or ungranted declarations before executing the mod; legacy
declarations warn and discard an invalid destination.

```lua
local job, why = mod:postLog("diagnostic text", {format="text"})
-- Later: poll and release through the same interface as GET.
if job then
  local result = mod.fetch:poll(job)
  if result.status ~= "pending" then mod.fetch:release(job) end
end
```

The only option is `format`, either `text` (default) or `json`. Input is at most
65,536 bytes. JSON wraps it in `{ts, mod, format, body}`; its encoded payload is
bounded separately at 512 KiB. Unknown keys and invalid values submit nothing.
The endpoint and mod identity are captured when the API is created. Manifest
mutation, options and redirects cannot change the log destination. POST does not
follow redirects. No server response body reaches the mod, including error and
late/cancelled results. Public log results expose status, progress, HTTP status
and a stable failure diagnostic. The mod's existing network permission applies.

GET and logs share the existing three-worker queue, global 16-job ceiling and
four-pending-requests-per-mod ceiling. Queue time counts towards the timeout.
Log requests use 20 seconds; other internal requests cap at 30 seconds. Released
or timed-out jobs retain their physical worker slot until completion. Poll reads
only worker results and performs no network, pipe or filesystem reads.

Desktop POST reuses the bounded curl path. Payloads reside in worker-owned files
and never enter shell syntax; those files are removed after the request. Curl
configuration is disabled and explicit HTTPS protocol limits remain enforced.

The new mobile `boundedHttpVersion()` / `httpRequestBounded()` protocol carries
binary payloads as bounded Base64 fields. Android reuses the existing JNI route
with a mandatory bounded envelope and a separately validated URLConnection
adapter; legacy cloud HTTP is unchanged. iOS uses a separate Foundation adapter
and private ephemeral sessions, without cookie/credential storage. Both adapters
retain platform TLS verification, bound body accumulation, refuse non-HTTP URLs
and HTTPS downgrades, and cap GET redirects at five. A POST is always HTTPS and
cannot redirect. iOS retains native task slots until terminal delegate callbacks;
Android closes the current connection on the absolute request deadline.

An HTTP failure, timeout or cancellation does not prove that a server did not
accept the submitted log. The service does not retry POST automatically.

Verification includes real owned desktop TLS transfers, literal bytes, expanded
JSON payloads, reply suppression, redirect refusal and existing GET/file-download
regressions. `tools/qualify_native_http.py` executes the production Swift and Java
adapter logic with URLProtocol/URLConnection fixtures and typechecks iOS. Those
fixtures do not exercise mobile TLS stacks or physical devices. Native packaging,
real mobile TLS/device acceptance, and resource behavior under suspension remain
separate gates.

The fixed Switch runtime currently has no bounded HTTP binding; the service
reports unavailable there and does not attempt a subprocess. Its TLS/runtime
adapter still needs integration and qualification. A native source build and
matching Lua payload are required for the mobile protocol. This change does not
establish full mod gameplay or complete platform parity.
