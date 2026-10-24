local C = {}
function C.run(root, backend, version, api, format)
  local F = dofile(root .. "/tests/text_sources/fixture.lua")
  local rows = {}
  local modes = { "override", "patch", "register", "remove", "delete", "patch-delete", "rollback", "no-mod" }
  for _, mode in ipairs(modes) do
    local id = mode == "register" and "NEW_TEXT" or "PORTABLE_TEXT"
    local f = F.new(root, backend, version, api, format, mode, id, "Hi {PLAYER}!\\n50%\\pBye\\lEnd")
    local T = f.T
    T.eq(#f.result.errors > 0, mode == "rollback" or mode == "delete", mode .. " load outcome")
    local value = f.source(id)
    if mode == "no-mod" or mode == "rollback" or mode == "delete" then
      T.eq(value, "BASE", mode .. " restores base")
    elseif mode == "remove" or mode == "patch-delete" then
      T.eq(value, nil, mode .. " removes native text")
    else
      T.eq(value, "Hi {PLAYER}!\n50%\fBye\vEnd", mode .. " native controls")
    end
    local row = { mode = mode, source = value, failed = #f.result.errors > 0 }
    if f.e then
      row.before, row.after = f.e.before, f.e.after
      row.ids = f.e.ids
      T.eq(f.e.api.content.text:has("KEEP"), true, "has preserves unrelated text")
      T.raises(function()
        f.e.api.content.text:override(id, "LATE")
      end, "frozen", "late text writes rejected")
    end
    if value then
      -- Real native readers, never Runtime.call producer stubs. Formatting
      -- details differ; exact source/control comparison is the shared contract.
      local shown = f.dialogue(id)
      T.check(
        shown:find((mode == "no-mod" or mode == "rollback" or mode == "delete") and "BASE" or "Hi", 1, true)
          ~= nil,
        "native reader sees effective source"
      )
    end
    rows[#rows + 1] = row
    f.close()
  end
  local gen = require("src.core.GameVersion").generation(version)
  if gen == 2 then
    local f = F.new(root, backend, version, api, format, "override", "55:4067", "SCRIPT PATCH")
    f.T.eq(f.source("55:4067"), "SCRIPT PATCH", "portable bank/address reaches native script pool")
    f.T.eq(f.dialogue("55:4067"), "SCRIPT PATCH", "native VM displays physical ID override")
    rows[#rows + 1] =
      { mode = "bank-address", before = f.e.before, after = f.e.after, native = f.source("55:4067") }
    f.close()
    local authored = F.new(root, backend, version, api, format, "register", "55:ABCD", "AUTHORED")
    authored.T.eq(authored.source("55:ABCD"), "AUTHORED", "authored ID case is preserved")
    authored.T.eq(authored.dialogue("55:ABCD"), "AUTHORED", "native script reads exact authored label")
    rows[#rows + 1] = { mode = "authored-case", after = authored.e.after, ids = authored.e.ids }
    authored.close()
  end
  local corpus = F.new(root, backend, version, api, format, "corpus", "PORTABLE_TEXT", "unused")
  corpus.T.eq(#corpus.result.errors, 0, "source corpus loads atomically")
  for i, observation in ipairs(corpus.e.corpus) do
    corpus.T.eq(
      corpus.source("CORPUS_" .. i),
      observation.read,
      "canonical source reaches native storage " .. i
    )
    if not observation.accepted then
      corpus.T.eq(observation.read, "seed", "refused source leaves previous value")
    end
    rows[#rows + 1] = {
      mode = "source-" .. i,
      accepted = observation.accepted,
      value = observation.value,
      read = observation.read,
    }
  end
  corpus.close()
  return rows
end
return C
