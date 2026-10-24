local C = {}
function C.run(root, backend, version, api, format)
  local F = dofile(root .. "/tests/rom_text/fixture.lua")
  local rows = {}
  local gen = require("src.core.GameVersion").generation(version)
  if gen ~= 2 and gen ~= 3 then
    local f = F.new(root, backend, version, "replace", api, format)
    f.T.eq(f.e.available, false, "unsupported generation does not advertise engine prose")
    f.close()
    return { { available = false } }
  end
  for _, mode in ipairs({
    "replace",
    "patch",
    "register",
    "remove",
    "delete",
    "rollback",
    "no-mod",
    "same-label",
    "namespace-prefix",
    "empty-script",
  }) do
    if (mode ~= "same-label" and mode ~= "namespace-prefix" and mode ~= "empty-script") or gen == 2 then
      local f = F.new(root, backend, version, mode, api, format)
      local failed = mode == "rollback" or gen == 2 and mode == "register"
      f.T.eq(#f.result.errors > 0, failed, "prose registry load outcome " .. mode)
      local a, b = f.prose()
      if
        mode == "replace"
        or mode == "patch"
        or mode == "same-label"
        or mode == "namespace-prefix"
        or mode == "empty-script"
        or gen == 3 and mode == "register"
      then
        f.T.eq(a, gen == 2 and "GOLD is awake!" or "TAKE FRIEND", "actual native reader sees effective prose")
      elseif gen == 2 and (mode == "remove" or mode == "delete") then
        f.T.eq(a, "GOLD fallback", "removed Gen-2 engine prose uses native fallback")
      else
        f.T.eq(a, gen == 2 and "GOLD woke up!" or "BASE1", "rollback/default uses original native prose")
      end
      local row = { mode = mode, failed = failed, native = a, description = b }
      if f.e then
        row.before, row.after = f.e.before, f.e.after
        f.T.raises(function()
          f.e.api.content.rom_text:override(f.label, "LATE")
        end, "frozen", "late prose write rejected")
      end
      if mode == "same-label" or mode == "namespace-prefix" or mode == "empty-script" then
        f.T.eq(f.e.scriptBefore, nil, "engine-prose label is absent in VM registry")
        f.T.eq(
          f.e.scriptAfter,
          mode == "empty-script" and "" or "SCRIPT ONLY",
          "same-spelling script gets separate record"
        )
        f.T.eq(
          f.script(),
          mode == "empty-script" and "..." or "SCRIPT ONLY",
          "actual script reader sees its own namespace"
        )
        row.script = f.script()
      end
      if mode == "namespace-prefix" then
        f.T.eq(f.e.prefixValue, "AUTHORED PREFIX", "authored prefix spelling remains its own ID")
        row.prefix = f.script("__portable_script_text__:" .. f.label)
        f.T.eq(row.prefix, "AUTHORED PREFIX", "actual VM distinguishes authored prefix label")
      end
      rows[#rows + 1] = row
      f.close()
    end
  end
  if gen == 3 then
    local all = F.new(root, backend, version, "storage-all", api, format)
    all.T.eq(#all.result.errors, 0, "all storage bindings load")
    local native = all.storageRows()
    for i, row in ipairs(native) do
      all.T.eq(row.label, "MOD_ROW_" .. i, "native storage action binding " .. i)
      all.T.eq(row.description, "MOD_DESC_" .. i, "native storage description binding " .. i)
    end
    rows[#rows + 1] = { mode = "storage-all", native = native }
    all.close()
  end
  return rows
end
return C
