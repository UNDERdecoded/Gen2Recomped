# Capture the completed window frame

Use `require('src.render.WindowFrame').capture(callback)` to request the next
completed window image. It returns false plus a reason when the bounded
16-request queue is full. Requests queued before a draw share one current
independent readback. Requests made from a draw/capture callback are delivered
on the following draw. Shutdown cancels requests that have not been delivered.

The callback receives `(imageData, frameInfo)`. The RGBA image is borrowed for
that callback only; encode it or copy it there, and do not release or retain
it. This is the same owned final target delivered to the window, including
native UI and mod HUDs. Observed/captured frames drain asynchronous GL recovery
and use current pixels. Healthy direct backends retain native capture ordering.

```lua
local Frame = require('src.render.WindowFrame')
assert(Frame.capture(function(data)
  assert(love.filesystem.write('capture.png', data:encode('png')))
end))
```

On macOS with an undefined OpenGL system framebuffer, a raw
`love.graphics.captureScreenshot` can encode an inverted/channel-swapped system
image even while the Cocoa recovery layer displays the correct RGBA frame.
Capturing the completed target avoids that invalid source; it does not flip or
recolour an exported picture. Existing native `Game.capturePath` captures use
the same current-frame route. No screenshot is inferred from a previous frame.

The CPU lifecycle/ordering tests cover queued/coalesced/reentrant/direct
requests, queue bounds, shutdown and callback-error image lifetime. Actual GPU
and owned OS-window evidence are a separate acceptance surface.

The [source-bound hardware receipt](qa/complete-frame-capture/gpu.json) records
FireRed/Emerald on macOS OpenGL and Metal. All sixteen fresh owned-window
proofs pass. Encoded PNGs from the queued API and the native driver are byte
identical in each same-frame pair; explicit red/blue/top markers check channel
order and orientation. These runs use fresh owned identities, a QA field and
native summary, and real resize/return. The introduction is bypassed; no
story, complete-game, general context-loss or performance acceptance is implied.
Raw system captures reproduce the invalid-source problem separately.

This change depends on the LÖVE-12 coordinate compatibility in PR #193. Healthy
non-macOS/direct frames retain the native path. Metal uses a retained final
GPU target without readback during ordinary frames. Only detected undefined
macOS OpenGL framebuffers use the owned Cocoa layer; regular recovery may use
one-frame pipelined readback latency, while captures/observers force current
independent data. The layer, CPU/GPU buffers and pending requests are owned and
retired on resize/shutdown. No other application's window is selected.

The four focused CPU suites pass (1,162 frame checks, 1,431 asynchronous
checks, 1,296 Cocoa checks and 108 function-pointer lifetime checks). The
standalone quick gate passes 70/79 engine suites, 3/3 SDK suites and B30. Its
exact PR-193 base passes 65/75 engine suites, 3/3 SDK suites and B30 under the
same setup: there are no new failure lines. Nine existing engine suites still
fail on both revisions. The existing static quit test also starts passing
because its first-text-match probe now selects the run-loop quit branch
instead of the reshaped error-screen branch; this is not an Android lifecycle
fix. The composed fork separately passed all 320 suites before this capture
API was added; that is not a standalone-branch all-pass claim.
