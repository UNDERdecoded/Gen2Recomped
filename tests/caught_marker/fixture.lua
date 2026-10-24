local M = {}
function M.new(root, backend, version, api, format, noMod, failing)
  local T = require("tests.modkit")
  local V, Json = require("src.core.GameVersion"), require("src.link.Json")
  assert(V.VERSIONS[version], "unregistered version")
  V.set(version)
  local gen = V.generation()
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local files = {}
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    local f = assert(io.open(root .. "/examples/portable_caught_marker/" .. name, "rb"))
    files["mods/portable_caught_marker/" .. name] = f:read("*a")
    f:close()
  end
  local mf = Json.decode(files["mods/portable_caught_marker/manifest.json"])
  mf.api, mf.callback_format, mf.gen2compat = api, format, api < 3 and true or nil
  files["mods/portable_caught_marker/manifest.json"] = Json.encode(mf)
  if failing then
    files["mods/portable_caught_marker/main.lua"] = files["mods/portable_caught_marker/main.lua"]
      .. '\nerror("intentional marker entry rollback")'
  end
  if noMod then
    files = {}
  end
  local result = T.sdk.loadMods(
    noMod and {} or { "mods/portable_caught_marker" },
    { data = data, fs = T.sdk.memfs(files), generation = gen, dev = false }
  )
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local game = { data = data, save = { options = {}, pokedex = { owned = {}, caught = {} }, party = {} } }
  result.loader.game = game
  local e, b, battler = result.loader.exports.portable_caught_marker
  local f = {
    T = T,
    game = game,
    data = data,
    gen = gen,
    backend = backend,
    api = api,
    format = format,
    e = e,
    result = result,
  }
  function f.reset(opts)
    opts = opts or {}
    local id = backend == "gen1" and gen == 3 and 16 or "FIXMON_A"
    local mon = {
      species = id,
      nickname = "FOE",
      name = "FOE",
      level = 20,
      hp = 60,
      maxHp = 60,
      stats = { hp = 60 },
      status = opts.status,
    }
    local dex = { owned = {}, caught = {} }
    if opts.caught ~= false then
      dex.owned[id], dex.caught[id] = true, true
    end
    if opts.noDex then
      dex = nil
    end
    game.save.pokedex = dex
    if backend == "gen1" and gen == 3 then
      require("src.import.gba.versions").select(version)
      b = {
        kind = opts.trainer and "trainer" or "wild",
        wild = not opts.trainer,
        trainer = opts.trainer,
        dex = dex,
        session = { game = game, dex = dex },
        firstBattle = opts.tutorial,
        ghostBattle = opts.ghost,
      }
      battler = {
        species = id,
        mon = mon,
        isPlayer = opts.player or false,
        side = opts.player and "player" or "enemy",
      }
    elseif backend == "gen1" and gen == 2 then
      b = setmetatable({
        game = game,
        data = data,
        save = game.save,
        caughtMark = opts.latched ~= false,
        battle = { wild = not opts.trainer, enemy = mon },
        activeMon = function()
          return mon
        end,
      }, { __index = require("src.ui.gen2.BattleState") })
      battler = mon
    else
      battler = { mon = mon, name = "FOE", isPlayer = opts.player or false, shownStatus = opts.status }
      b = setmetatable({
        game = game,
        data = data,
        kind = opts.trainer and "trainer" or "wild",
        enemy = battler,
        caughtMark = opts.latched ~= false,
        demo = opts.tutorial,
        firstBattle = opts.tutorial,
        ghost = opts.ghost,
      }, { __index = require("src.battle.BattleState") })
    end
    b.publicTag = "caught_context"
    f.battle, f.battler, f.mon = b, battler, mon
    return b
  end
  function f.visible()
    if backend == "gen1" and gen == 3 then
      return require("src.core.game3.battle.healthbox").shouldShowCaughtMarker(b, battler)
    end
    return b:caughtMarkerVisible()
  end
  f.reset()
  f.close = function()
    result.release()
  end
  return f
end
return M
