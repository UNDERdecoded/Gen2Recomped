-- Separate process per engine/version: modules and runtime buses cannot leak.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = nil
local root, backend, version, mode = arg[1], arg[2], arg[3], arg[4]
assert(
  root and backend and version and (mode == "normal" or mode == "rollback" or mode == "scaffold"),
  "invalid worker arguments"
)
local codeRoot = (arg[0]:gsub("\\", "/")):match("^(.*)/worker%.lua$")
dofile(codeRoot .. "/run.lua").run(root, backend, version, mode == "rollback", mode == "scaffold")
