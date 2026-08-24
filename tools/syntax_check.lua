-- Load-checks Lua sources without running them.
--
-- Exists because two failure modes in this project are invisible until the
-- game boots and then look like "the feature silently did nothing":
--
--   * a plain syntax error in a module only reached from a pcall'd hook;
--   * "main function has more than 200 local variables" -- Lua 5.1 caps a
--     chunk's file-scope locals at 200, and RomExtractorGen2.lua sits on that
--     ceiling.  Adding one more `local` at file scope makes the whole module
--     fail to LOAD.  Hang constants off the class table instead.
--
--   luajit tools/syntax_check.lua $(git ls-files '*.lua')
--   luajittex --luaonly tools/syntax_check.lua src/**/*.lua
--
-- Exits non-zero when anything fails, so it drops straight into CI.
local files = {}
for i = 1, #arg do files[#files + 1] = arg[i] end

if #files == 0 then
  io.stderr:write("usage: syntax_check.lua <file.lua> [...]\n")
  os.exit(2)
end

local failed = 0
for _, path in ipairs(files) do
  local chunk, err = loadfile(path)
  if not chunk then
    failed = failed + 1
    io.stderr:write("FAIL " .. tostring(err) .. "\n")
  end
end

if failed > 0 then
  io.stderr:write(string.format("%d/%d file(s) failed to load\n", failed, #files))
  os.exit(1)
end
print(string.format("%d file(s) load cleanly", #files))
