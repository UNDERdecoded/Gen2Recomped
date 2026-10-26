-- Real disk discovery must execute the requested mod, including an external
-- absolute directory. Zero loader errors alone cannot establish this.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local cwdPipe = assert(io.popen(FsIo.isWindows and "cd" or "pwd"))
local cwd = assert(cwdPipe:read("*l"))
cwdPipe:close()
local relative = "tests/modkit/fixtures/path probe"
local absolute = cwd .. "/" .. relative
local payload = "Unmodified bytes from the selected mod directory.\n"

for _, path in ipairs({ relative, absolute }) do
  local data = T.fixtures.fresh()
  local run = T.sdk.loadMod(path, { data = data })
  local exports = run.loader.exports.path_probe
  T.eq(#run.errors, 0, "selected mod has no loader errors")
  T.check(exports and exports.executed, "selected mod entry actually executed: " .. path)
  T.eq(exports and exports.payload, payload, "mod:read resolves against the selected directory")
  T.eq(data.items.FIX_POTION.price, 271, "selected mod content merged into the fixture")
  T.check(run.mod and run.mod.manifest.id == "path_probe", "loadMod returns the discovered mod")
  run.release()
end

-- An explicit repo root must still allow an absolute mod outside that root.
local run = T.sdk.loadMod(absolute, { root = "tests/fixture_data" })
T.check(
  run.loader.exports.path_probe and run.loader.exports.path_probe.executed,
  "absolute alias is independent of the relative filesystem root"
)
T.eq(#run.errors, 0, "external absolute alias has no loader errors")
run.release()

local fs = FsIo.new("tests/modkit/fixtures")
T.eq(fs.read("path probe/payload.txt"), payload, "relative reads still use the explicit root")
T.eq(fs.read(absolute .. "/payload.txt"), payload, "absolute reads retain their original location")
T.eq((fs.getInfo(absolute) or {}).type, "directory", "absolute mod directory is discoverable")
T.eq(type(fs.load(absolute .. "/main.lua")), "function", "absolute entry file compiles")

-- Exercise every path-taking operation under both platform policies without
-- requiring a Windows host or writing into the immutable fixture.
local oldOpen, oldLoad, oldList, oldWindows = io.open, loadfile, FsIo.listDir, FsIo.isWindows
local seen, written
io.open = function(path)
  seen = path
  return {
    read = function()
      return "bytes"
    end,
    close = function() end,
    write = function(_, body)
      written = body
    end,
  }
end
loadfile = function(path)
  seen = path
  return function()
    return "chunk"
  end
end
FsIo.listDir = function(path)
  seen = path
  return { "entry" }
end
local ok, err = pcall(function()
  local cases = {
    { false, "/external/mod/main.lua", "/external/mod/main.lua" },
    { false, "relative/main.lua", "test-root/relative/main.lua" },
    { false, "C:/relative-on-posix", "test-root/C:/relative-on-posix" },
    { true, "C:/external/mod/main.lua", "C:/external/mod/main.lua" },
    { true, "D:\\external\\mod\\main.lua", "D:\\external\\mod\\main.lua" },
    { true, "\\\\server\\share\\mod\\main.lua", "\\\\server\\share\\mod\\main.lua" },
    { true, "\\external\\mod\\main.lua", "\\external\\mod\\main.lua" },
    { true, "/external/mod/main.lua", "/external/mod/main.lua" },
    { true, "C:drive-relative.lua", "test-root/C:drive-relative.lua" },
    { true, "relative/main.lua", "test-root/relative/main.lua" },
    { false, "", "test-root" },
    { true, "", "test-root" },
  }
  for _, case in ipairs(cases) do
    FsIo.isWindows = case[1]
    local adapter = FsIo.new("test-root")
    for _, op in ipairs({ "read", "write", "getInfo", "load", "getDirectoryItems" }) do
      seen = nil
      adapter[op](case[2], "written bytes")
      T.eq(seen, case[3], op .. " resolves " .. case[2])
    end
  end
  T.eq(written, "written bytes", "write forwards bytes unchanged")
end)
io.open, loadfile, FsIo.listDir, FsIo.isWindows = oldOpen, oldLoad, oldList, oldWindows
assert(ok, err)
T.finish("modkit filesystem paths")
