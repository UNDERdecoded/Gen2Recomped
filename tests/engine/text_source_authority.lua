package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local F = dofile("tests/text_sources/fixture.lua")
local old = V.get()
local function reload(data)
  -- Isolate this registry's retirement from the pre-existing builtin
  -- duplicate-registration issue on an already-merged fixture dataset.
  for root in pairs(require("src.mods.Builtins").namespaceRoots()) do
    if root ~= "text" and root ~= "constants" then
      data[root] = nil
    end
  end
  return T.sdk.loadNone({ data = data })
end
for _, version in ipairs({ "red", "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local api, format = unpack(mode)
    local f = F.new(".", "gen2", version, api, format, "override", "PORTABLE_TEXT", "X\\nY\\pZ\\lQ")
    T.eq(#f.result.errors, 0, "all legacy/opt-in modes load")
    local unified = api == 3 or format == "unified"
    T.eq(
      f.data.text.PORTABLE_TEXT,
      unified and "X\nY\fZ\vQ" or "X\\nY\\pZ\\lQ",
      "native source bytes remain unchanged outside unified boundary"
    )
    T.eq(f.e.after, f.data.text.PORTABLE_TEXT, "public source matches mode")
    T.raises(function()
      f.e.api.content.text:override("KEEP", "late")
    end, "frozen", "all modes freeze content")
    f.close()
    if unified then
      local pool = f.data.text
      pool.UNRELATED = "external"
      local r = reload(f.data)
      T.eq(pool.PORTABLE_TEXT, "BASE", "reload retires successful adapter write")
      T.eq(pool.UNRELATED, "external", "reload retains unrelated external writes")
      T.eq(f.data.text, pool, "reload retains native table identity")
      r.release()
      local edited = F.new(".", "gen2", version, api, format, "override", "PORTABLE_TEXT", "MODDED")
      edited.data.text.PORTABLE_TEXT = "EXTERNAL"
      edited.close()
      local keep = reload(edited.data)
      T.eq(edited.data.text.PORTABLE_TEXT, "EXTERNAL", "retirement cannot overwrite intervening edit")
      keep.release()
      local replacement = F.new(".", "gen2", version, api, format, "register", "NEW_TEXT", "MODDED")
      replacement.data.text = { REPLACED = "other dataset" }
      replacement.close()
      local other = reload(replacement.data)
      T.eq(replacement.data.text.NEW_TEXT, nil, "retirement does not add data to replacement table")
      other.release()
      for _, source in ipairs({ "{PLAYER}", "{STR_VAR_1}", "{STR_VAR_2}", "{STR_VAR_3}" }) do
        if V.generation(version) == 3 then
          local tokens = F.new(".", "gen2", version, api, format, "override", "PORTABLE_TEXT", source .. "!")
          local expected = ({
            ["{PLAYER}"] = "PROBE!",
            ["{STR_VAR_1}"] = "ONE!",
            ["{STR_VAR_2}"] = "TWO!",
            ["{STR_VAR_3}"] = "THREE!",
          })[source]
          T.eq(
            tokens.dialogue("PORTABLE_TEXT"),
            expected,
            "real GBA command resolves common token " .. source
          )
          T.eq(tokens.e.after, source .. "!", "read exposes common token without changing native alias")
          tokens.close()
        end
      end
    end
  end
end
for _, api in ipairs({ 2, 3 }) do
  for _, body in ipairs({
    'mod.content.text:override("PORTABLE_TEXT", "EARLY"); mod.content.text:override("BAD", {})',
    'mod.content.text:override("PORTABLE_TEXT", "EARLY"); mod.content.text:get(nil)',
    'mod.content.text:override("PORTABLE_TEXT", "EARLY"); mod.content.text:register("KEEP", "duplicate")',
  }) do
    local f = F.new(".", "gen2", "gold", api, "unified", "none", "PORTABLE_TEXT", "", body)
    T.check(#f.result.errors > 0, "invalid entry is rejected")
    T.eq(f.data.text.PORTABLE_TEXT, "BASE", "invalid entry rolls earlier write back")
    T.eq(next(f.result.loader.content.text.ops), nil, "invalid entry adds no content ops")
    f.close()
  end
  local f = F.new(
    ".",
    "gen2",
    "gold",
    api,
    "unified",
    "none",
    "55:4067",
    "",
    [[
    mod.content.text:override("55:4067", "FIRST")
    mod.content.text:patch("TEXT_S55_4067", "SECOND")
    mod.exports.value = mod.content.text:get("55:4067")
    mod.exports.physical = mod.content.text:get("TEXT_S55_4067")
  ]]
  )
  T.eq(f.e.value, "SECOND", "canonical and native alias fold one ordered registry key")
  T.eq(f.e.physical, "SECOND", "native alias reads the same record")
  T.eq(f.data.text["55:4067"], nil, "no unused canonical shadow text is written")
  T.eq(f.data.text.TEXT_S55_4067, "SECOND", "native VM physical storage is authoritative")
  f.close()
  local conflict = F.new(
    ".",
    "gen2",
    "gold",
    api,
    "unified",
    "override",
    "55:4067",
    "unsafe",
    nil,
    function(data)
      data.text["55:4067"] = "AMBIGUOUS"
    end
  )
  T.check(#conflict.result.errors > 0, "ambiguous imported/custom aliases fail before entry writes")
  T.eq(conflict.data.text.TEXT_S55_4067, "SCRIPT BASE", "ambiguous alias does not pick a native record")
  T.eq(conflict.data.text["55:4067"], "AMBIGUOUS", "ambiguous alias does not mutate custom record")
  conflict.close()
end
-- Mixed native/unified owners share one physical record and the existing
-- dependency order. Failed unified owners must not acquire retirement of a
-- surviving native owner's value.
for _, order in ipairs({ "native-first", "unified-first", "failed-unified" }) do
  local f = F.new(
    ".",
    "gen2",
    "gold",
    3,
    "unified",
    order == "failed-unified" and "rollback" or "override",
    "55:4067",
    "UNIFIED",
    nil,
    nil,
    function(files, name, J)
      local path = "mods/native_text_overlay/"
      local m = {
        id = "native_text_overlay",
        name = "Native text overlay",
        version = "1.0.0",
        api = 2,
        games = { "gold" },
        gen2compat = true,
        entry = "main.lua",
      }
      if order == "unified-first" then
        m.dependencies = { name }
      else
        local current = J.decode(files["mods/" .. name .. "/manifest.json"])
        current.dependencies = { m.id }
        files["mods/" .. name .. "/manifest.json"] = J.encode(current)
      end
      files[path .. "manifest.json"] = J.encode(m)
      files[path .. "main.lua"] = 'local mod=...; mod.content.text:override("TEXT_S55_4067", "NATIVE")'
    end
  )
  T.eq(#f.result.errors > 0, order == "failed-unified", "mixed owner load outcome")
  T.eq(
    f.data.text.TEXT_S55_4067,
    order == "native-first" and "UNIFIED" or "NATIVE",
    "declared dependency order reaches physical VM key"
  )
  T.eq(f.data.text["55:4067"], nil, "mixed owners do not create shadow key")
  f.close()
  local r = reload(f.data)
  T.eq(
    f.data.text.TEXT_S55_4067,
    order == "failed-unified" and "NATIVE" or "SCRIPT BASE",
    "failed adapter cannot claim a surviving native owner's retirement"
  )
  r.release()
end
-- DS keeps its existing native text handles. This change does not invent a
-- common DS printer or claim GBA source controls work on those screens.
for _, version in ipairs({ "platinum", "black" }) do
  local f = F.new(".", "gen2", version, 3, "unified", "override", "PORTABLE_TEXT", "X\\nY")
  T.eq(f.data.text.PORTABLE_TEXT, "X\\nY", "DS native bytes remain unchanged")
  f.close()
end
V.set(old)
T.finish("source text ownership, legacy bytes, aliases and native token consumers")
