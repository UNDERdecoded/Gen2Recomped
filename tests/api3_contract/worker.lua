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
    ),
  "invalid worker arguments"
)
local codeRoot = (arg[0]:gsub("\\", "/")):match("^(.*)/worker%.lua$")
if mode == "invalidate" then
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
