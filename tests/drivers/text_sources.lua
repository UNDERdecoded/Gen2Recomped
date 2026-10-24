-- Imported-data native text smoke. Use the isolated combined-fork wrapper.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION"), "wrong imported version")
  local gen = V.generation()
  assert(gen == 2 or gen == 3, "smoke requires imported Gen 2/GBA")
  local e = assert(game.mods.exports.portable_text_sources, "install public text example")
  assert(e.after and not e.reason, "public text source was refused")
  local title
  for _ = 1, 120 do
    local top = game.stack:top()
    if top and type(top.onNewGame) == "function" then
      title = top
      break
    end
    U.tap(game, "start")
    U.wait(4)
  end
  assert(title, "native title missing")
  title:onNewGame()
  local world = assert(game.overworld, "native New Game missing")
  game.save.player.name, game.save.player.rival = "PROBE", "RIVAL"
  game.stringBuffers = { "ONE", "TWO", "THREE" }
  game.stack.states = { world }
  local key = gen == 2 and "TEXT_S55_4067" or "PORTABLE_TEXT"
  assert(game.data.text[key], "native storage key missing")
  if gen == 2 then
    assert(e.before and e.before ~= "SCRIPT BASE", "Gold must use actual imported cartridge text")
    assert(not game.data.text["55:4067"], "unused canonical shadow text created")
    assert(e.api.content.text:get("55:4067") == e.after, "canonical read mismatch")
  end
  local script
  if gen == 2 then
    local pool = assert(game.data.map_scripts.scripts)
    assert(pool.portable_text_source_probe == nil, "driver key already occupied")
    pool.portable_text_source_probe = { { "writetext", key }, { "end" } }
    script = assert(require("src.script.Gen2ScriptVM").compile(game.data, "portable_text_source_probe"))
  else
    script = { { "g3_show_text", key } }
  end
  local runner = require("src.script.ScriptRunner").new(game, world)
  runner:run(script)
  local box = assert(game.stack:top(), "native text did not open")
  assert(box ~= world and type(box.pages) == "table", "native textbox missing")
  local all = {}
  for _, page in ipairs(box.pages) do
    for _, line in ipairs(page) do
      all[#all + 1] = line
    end
  end
  local shown = table.concat(all, "|")
  assert(shown:find("PROBE", 1, true), "player placeholder did not reach native printer")
  assert(not shown:find("{PLAYER}", 1, true), "player token remained literal")
  if gen == 3 then
    assert(shown:find("ONE", 1, true) and shown:find("TWO", 1, true), "common string vars did not expand")
    assert(
      not shown:find("{STR_VAR", 1, true) and not shown:find("{VAR", 1, true),
      "string vars remained literal"
    )
  end
  assert(#box.pages >= 2, "paragraph source control did not reach native pages")
  U.wait(10) -- the ordinary renderer draws the actual box
  for _ = 1, 100 do
    if game.stack:top() == world then
      break
    end
    U.tap(game, "a")
    U.wait(3)
  end
  assert(game.stack:top() == world, "native A input did not close dialogue")
  assert(not runner:isRunning(), "native dialogue did not resume script")
  local ok, err = pcall(function()
    e.api.content.text:override("PORTABLE_TEXT", "LATE")
  end)
  assert(not ok and tostring(err):find("frozen", 1, true), "late public write was not frozen")
  print("PORTABILITY_TEXT_SOURCE_PASS " .. V.get())
  love.event.quit(0)
end
