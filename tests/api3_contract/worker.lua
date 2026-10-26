-- Separate process per engine/version: modules and runtime buses cannot leak.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = nil
local root, backend, version, mode = arg[1], arg[2], arg[3], arg[4]
assert(
  root
    and backend
    and version
    and (
      mode == "normal"
      or mode == "rollback"
      or mode == "scaffold"
      or mode == "warp"
      or mode == "world_edits"
      or mode == "npcs"
      or mode == "wild_battle"
      or mode == "invalidate"
      or mode == "flags"
      or mode == "script_flags"
      or mode == "script_state"
      or mode == "script_gifts"
      or mode == "script_world"
      or mode == "script_motion"
      or mode == "script_travel"
      or mode == "script_battles"
    ),
  "invalid worker arguments"
)
local codeRoot = (arg[0]:gsub("\\", "/")):match("^(.*)/worker%.lua$")
if mode == "script_battles" then
  dofile(codeRoot .. "/script_battles.lua").run(root, backend, version)
elseif mode == "script_travel" then
  dofile(codeRoot .. "/script_travel.lua").run(root, backend, version)
elseif mode == "script_motion" then
  dofile(codeRoot .. "/script_motion.lua").run(root, backend, version)
elseif mode == "script_world" then
  dofile(codeRoot .. "/script_world.lua").run(root, backend, version)
elseif mode == "script_gifts" then
  dofile(codeRoot .. "/script_gifts.lua").run(root, backend, version)
elseif mode == "script_state" then
  dofile(codeRoot .. "/script_state.lua").run(root, backend, version)
elseif mode == "script_flags" then
  dofile(codeRoot .. "/script_flags.lua").run(root, backend, version)
elseif mode == "flags" then
  dofile(codeRoot .. "/flags.lua").run(root, backend, version)
elseif mode == "invalidate" then
  dofile(codeRoot .. "/invalidate.lua").run(root, backend, version)
elseif mode == "wild_battle" then
  dofile(codeRoot .. "/wild_battle.lua").run(root, backend, version)
elseif mode == "npcs" then
  dofile(codeRoot .. "/npcs.lua").run(root, backend, version)
elseif mode == "world_edits" then
  dofile(codeRoot .. "/world_edits.lua").run(root, backend, version)
elseif mode == "warp" then
  dofile(codeRoot .. "/warp.lua").run(root, backend, version)
else
  dofile(codeRoot .. "/run.lua").run(root, backend, version, mode == "rollback", mode == "scaffold")
end
