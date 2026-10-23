# Portable surf-mount render-hook example

General public-only helper for mods replacing a world render hook. No private
Player/FieldEffects imports, generation-specific module paths or host-name
branches. API 2 and API 3 use the same files on hosts providing the contract.
The documented Gen1 test extension is not a production compatibility workaround.

Load `Mounts.lua` via `mod:read` like `main.lua`, then:

```lua
local mounts = assert(exports.new(mod.renderData))
local rows, why = mounts:prepare(frame)
if not rows then return false end -- caller chooses its native fallback
-- Inside the caller's fenced world hook, under translate(-camera.x,-camera.y):
mounts:draw(rows, "ground")
for _, actor in ipairs(bodyActors) do
  mounts:draw(rows, "actorUnderlay", actor.id)
  -- Draw the body here in its normal terrain/actor order.
end
```

A 3D renderer may instead use source rectangles and ground anchors directly.
`prepare` owns/culls/releases PNG images and quads; `invalidate` releases them
idempotently when the mod/hook is disabled. No Canvas or world pipeline is owned
or automatically enabled. The caller owns graphics state and terrain ordering.
The helper applies the host's supplied flat camera-rounding rule.

See `docs/gen3-surf-mount-render-data-v1.md`. A body picture requires the separate
actor contract; riderPose alone is only a body-cell origin. Existing examples
and earlier contracts are not renamed by this PR.
