package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local F = dofile("tests/rom_text/fixture.lua")
local original = V.get()
local function reload(data)
  -- Keep the registry under test, excluding the known duplicate builtin
  -- fixture registration issue from the unrelated existing baseline suites.
  for root in pairs(require("src.mods.Builtins").namespaceRoots()) do
    if root ~= "text" and root ~= "constants" then
      data[root] = nil
    end
  end
  return T.sdk.loadNone({ data = data })
end
for _, version in ipairs({ "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, config in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local api, format = unpack(config)
    local f = F.new(".", "gen2", version, "replace", api, format)
    T.eq(#f.result.errors, 0, "prose entry loads in each host mode")
    T.eq(f.e.api:supports("content", "rom_text"), true, "public capability has a native prose target")
    T.eq(f.e.api.content.rom_text.available, true, "prose facade advertises availability")
    T.eq(f.e.api.content.rom_text:has(f.label), true, "effective prose is queryable")
    T.eq(f.e.api.content.rom_text:get("MISSING"), nil, "missing prose remains absent")
    for id, value in f.e.api.content.rom_text:each() do
      T.eq(type(id), "string", "prose enumeration uses labels")
      T.eq(type(value), "string", "prose enumeration returns source/native strings")
      T.check(not id:match("^TEXT_S") and id ~= "55:4067", "VM addresses never appear as prose")
    end
    T.eq(
      f.data.text._WokeUpText,
      f.gen == 2 and "{USER} is awake!" or "{USER} woke up!",
      "native Gen-2 label readers consume prose while GBA script storage stays intact"
    )
    if f.gen == 2 then
      f.data.text.UNLISTED_LEGACY = "UNCHANGED"
      local b = setmetatable({ data = f.data }, { __index = require("src.battle.BattleState") })
      T.eq(
        b:romText("UNLISTED_LEGACY", "fallback"),
        "UNCHANGED",
        "untouched legacy prose keeps native fallback"
      )
    else
      local native = f.data.constants.gen3PCMenu.storage
      T.eq(native.rows[1], "BASE1", "prose view does not edit imported constants")
      local game = { data = f.data, save = { player = { name = "PROBE" }, options = {} } }
      local view = require("src.ui.Gen3StorageMenu").record(game)
      T.eq(view.rows[1], "TAKE FRIEND", "native record view reads prose override")
      view.rows[1] = "EXTERNAL VIEW"
      T.eq(
        require("src.ui.Gen3StorageMenu").record(game).rows[1],
        "TAKE FRIEND",
        "overridden view is detached"
      )
      T.eq(native.rows[1], "BASE1", "view mutation cannot edit the imported cartridge record")
      f.data.constants.gen3PCMenu.storage = nil
      T.eq(
        require("src.ui.Gen3StorageMenu").record(game).rows[1],
        "TAKE FRIEND",
        "legacy fallback screen consumes label override"
      )
    end
    f.close()
    local r = reload(f.data)
    T.eq(f.data.romText, nil, "reload retires untouched installed prose map")
    T.eq(f.data._romTextGeneration, nil, "reload retires generation routing")
    T.eq(f.data._romTextTouched, nil, "reload retires tombstone routing")
    r.release()
    local edited = F.new(".", "gen2", version, "replace", api, format)
    edited.data.romText[edited.label] = "EXTERNAL"
    edited.close()
    local keep = reload(edited.data)
    T.eq(edited.data.romText[edited.label], "EXTERNAL", "reload preserves intervening native prose edit")
    keep.release()
    local unrelated = F.new(".", "gen2", version, "replace", api, format)
    unrelated.data.romText.UNRELATED = "EXTERNAL"
    unrelated.close()
    local keepOther = reload(unrelated.data)
    T.eq(unrelated.data.romText.UNRELATED, "EXTERNAL", "retirement preserves unrelated native prose")
    T.eq(unrelated.data.romText[unrelated.label], nil, "retirement removes owned value beside external edit")
    if unrelated.gen == 2 then
      local b = setmetatable({ data = unrelated.data }, { __index = require("src.battle.BattleState") })
      T.eq(
        b:romText(unrelated.label, "%s fallback", "GOLD"),
        "GOLD woke up!",
        "retirement also removes owned fallback mask"
      )
    end
    keepOther.release()
  end
end
for _, api in ipairs({ 2, 3 }) do
  for _, mode in ipairs({ "same-label", "namespace-prefix", "empty-script" }) do
    local f = F.new(".", "gen2", "gold", mode, api, "unified")
    T.eq(#f.result.errors, 0, "isolated script namespace loads")
    T.eq(f.prose(), "GOLD is awake!", "private script source does not replace engine prose")
    for id in pairs(f.data.text) do
      T.check(
        not id:match("^__portable_script_text__:"),
        "synthetic script keys do not leak into legacy storage"
      )
    end
    T.eq(
      f.data.text._WokeUpText,
      "{USER} is awake!",
      "raw Gen-2 engine label reads prose, not private script source"
    )
    T.eq(
      f.e.api.content.text:get(f.label),
      mode == "empty-script" and "" or "SCRIPT ONLY",
      "public script view retains its value"
    )
    local proseSeen, scriptSeen = 0, 0
    for id in f.e.api.content.rom_text:each() do
      if id == f.label then
        proseSeen = proseSeen + 1
      end
    end
    for id in f.e.api.content.text:each() do
      if id == f.label then
        scriptSeen = scriptSeen + 1
      end
    end
    T.eq(proseSeen, 1, "prose enumerates its label once")
    T.eq(scriptSeen, 1, "script enumerates separate same-spelling label once")
    f.close()
    local r = reload(f.data)
    T.eq(f.data._portableScriptText[f.label], nil, "reload retires private script record")
    T.eq(f.data.romText, nil, "reload retires corresponding prose independently")
    r.release()
  end
  local masked = F.new(
    ".",
    "gen2",
    "gold",
    "none",
    api,
    "unified",
    [[
    mod.content.rom_text:override("_WokeUpText", "{USER} ENGINE")
    mod.content.text:override("_WokeUpText", "SCRIPT")
    mod.content.text:remove("_WokeUpText")
  ]]
  )
  T.eq(masked.e.api.content.text:get("_WokeUpText"), nil, "private tombstone remains absent to public reader")
  T.eq(masked.script(), "...", "private tombstone cannot reveal engine text through native VM")
  T.eq(masked.prose(), "GOLD ENGINE", "private tombstone does not remove engine prose")
  masked.close()
  local collision = F.new(".", "gen2", "gold", "same-label", api, "unified", nil, function(data)
    data.text["__portable_script_text__:_WokeUpText"] = "PREEXISTING"
  end)
  T.eq(collision.e.scriptAfter, "SCRIPT ONLY", "namespace reservation avoids preexisting native record")
  T.eq(
    collision.data.text["__portable_script_text__:_WokeUpText"],
    "PREEXISTING",
    "existing authored prefix bytes survive"
  )
  T.eq(collision.script(), "SCRIPT ONLY", "reserved private record reaches actual VM")
  collision.close()
  for _, body in ipairs({
    'mod.content.rom_text:override("_WokeUpText","EARLY"); mod.content.rom_text:override("BAD",{})',
    'mod.content.rom_text:override("_WokeUpText","EARLY"); error("ROLL BACK")',
    'mod.content.text:register("_WokeUpText","EARLY SCRIPT"); error("ROLL BACK")',
  }) do
    local failed = F.new(".", "gen2", "gold", "none", api, "unified", body)
    T.check(#failed.result.errors > 0, "invalid/failed prose or script entry is rejected")
    T.eq(failed.data.romText, nil, "failed prose entry adds no native map")
    T.eq(failed.data._portableScriptText, nil, "failed entry adds no private native script records")
    T.eq(next(failed.result.loader.content.rom_text.ops), nil, "failed owner leaves no prose operations")
    T.eq(failed.prose(), "GOLD woke up!", "failed entry leaves native prose intact")
    failed.close()
  end
end
for _, version in ipairs({ "red", "blue", "yellow", "platinum", "heartgold", "black", "white" }) do
  local f = F.new(".", "gen2", version, "replace", 3, "unified")
  local handle = f.e.api.content.rom_text
  T.eq(handle.available, false, "unavailable generation has honest metadata")
  local value, reason = handle:override("UNUSED", "unused")
  T.eq(value, nil, "unavailable write is inert")
  T.check(type(reason) == "string", "unavailable write explains missing native target")
  T.eq(handle:each()(), nil, "unavailable prose iterator is empty")
  T.eq(next(f.result.loader.content.rom_text.ops), nil, "unavailable target receives no operations")
  T.eq(f.data.romText, nil, "unavailable target receives no prose map")
  f.close()
end
local endMarker = F.new(
  ".",
  "gen2",
  "gold",
  "none",
  3,
  "unified",
  [[
  mod.content.rom_text:override("_WokeUpText", "{USER} awake{DONE}{PROMPT}")
]]
)
T.eq(endMarker.prose(), "GOLD awake{DONE}{PROMPT}", "native formatter retains ending metadata")
T.eq(
  require("src.render.TextBox").substitute({ data = endMarker.data }, endMarker.prose()),
  "GOLD awake",
  "native prose textbox does not print ending metadata"
)
endMarker.close()
V.set(original)
T.finish("ROM prose ownership, namespace isolation and native storage views")
