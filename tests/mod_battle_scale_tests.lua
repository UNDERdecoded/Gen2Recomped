-- The battle-sprite-scale seam, exercised through the public mod API.
--
-- Modders scale battle pics per species (pokemon.battleScaleFront /
-- battleScaleBack) or per image path (the battle_sprite_scales registry,
-- the only handle on non-species pics like the trainer back).  The
-- properties worth pinning: the schema rejects out-of-range scales and a
-- pathless record, image-level beats species-level beats the vanilla
-- default, and above all the pic stays GROUNDED -- feet on the text-box
-- top, bottom edge in its slot -- at every scale and through the send-out
-- grow.  The placement math and the scale resolver are pure (no love.*),
-- so the grounding contract is asserted directly.
package.path = "./?.lua;./?/init.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local Loader = require("src.mods.Loader")
local Schemas = require("src.mods.Schemas")
local BattleState = require("src.battle.BattleState")

local S = require("tests.harness").suite("mod battle scale")
local check, eq = S.check, S.eq

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

local function manifest(id, extra)
  return ('{"id":"%s","name":"%s","version":"1.0.0","api":2,' ..
          '"entry":"main.lua"%s}'):format(id, id, extra or "")
end

-- a minimal, internally consistent base so a pokemon patch has something
-- to fold onto; the cross-reference pass skips registries no mod touched,
-- so the untouched type/move refs on these records never surface
local function baseData()
  return {
    pokemon = {
      PIKACHU = { id = "PIKACHU", name = "PIKACHU", dex = 25,
        types = { "ELECTRIC" },
        baseStats = { hp = 35, attack = 55, defense = 30, speed = 90, special = 50 },
        catchRate = 190, baseExp = 82, level1Moves = { "THUNDERSHOCK" },
        growthRate = "MEDIUM_FAST", learnset = {}, evolutions = {},
        spriteFront = "pikachu_front.png", spriteBack = "pikachu_back.png",
        frontSize = 5 },
      RAICHU = { id = "RAICHU", name = "RAICHU", dex = 26,
        types = { "ELECTRIC" },
        baseStats = { hp = 60, attack = 90, defense = 55, speed = 110, special = 90 },
        catchRate = 75, baseExp = 122, level1Moves = { "THUNDERSHOCK" },
        growthRate = "MEDIUM_FAST", learnset = {}, evolutions = {},
        spriteFront = "raichu_front.png", spriteBack = "raichu_back.png",
        frontSize = 6 },
    },
    moves = {
      THUNDERSHOCK = { id = "THUNDERSHOCK", name = "THUNDERSHOCK",
        type = "ELECTRIC", power = 40, accuracy = 100, pp = 30,
        effect = "PARALYZE_SIDE_EFFECT1" },
    },
  }
end

-- ------- schema: the battle_sprite_scales registry

do
  local spec = Schemas.REGISTRIES.battle_sprite_scales
  check(spec ~= nil, "the battle_sprite_scales registry is in the catalog")
  eq(spec.semantics, "record", "battle_sprite_scales merges as records")
  eq(spec.target, "battle_sprite_scales",
    "battle_sprite_scales writes to its own namespace")

  local ok = Schemas.check(spec, "battle_sprite_scales", "abra_back",
    { path = "assets/generated/battle/back/abrab.png", scale = 1.5 }, "register")
  check(ok, "a path + in-range scale validates")

  -- the boundaries are inclusive
  check(Schemas.check(spec, "battle_sprite_scales", "lo",
    { path = "x.png", scale = 0.25 }, "register"), "scale 0.25 is accepted")
  check(Schemas.check(spec, "battle_sprite_scales", "hi",
    { path = "x.png", scale = 4.0 }, "register"), "scale 4.0 is accepted")

  local tooBig, bigErr = Schemas.check(spec, "battle_sprite_scales", "big",
    { path = "x.png", scale = 5 }, "register")
  check(not tooBig, "a scale above 4.0 is rejected")
  check(tostring(bigErr):find("0.25", 1, true) ~= nil,
    "the rejection names the range it wanted: " .. tostring(bigErr))

  check(not Schemas.check(spec, "battle_sprite_scales", "small",
    { path = "x.png", scale = 0.1 }, "register"),
    "a scale below 0.25 is rejected")

  local noPath, pathErr = Schemas.check(spec, "battle_sprite_scales", "nopath",
    { scale = 1 }, "register")
  check(not noPath, "a record with no path is rejected")
  check(tostring(pathErr):find("path", 1, true) ~= nil,
    "the rejection names the missing path: " .. tostring(pathErr))

  check(not Schemas.check(spec, "battle_sprite_scales", "emptypath",
    { path = "", scale = 1 }, "register"), "an empty path is rejected")
end

-- ------- schema: the per-species scale fields

do
  local spec = Schemas.REGISTRIES.pokemon
  check(Schemas.check(spec, "pokemon", "PIKACHU",
    { battleScaleBack = 3, battleScaleFront = 0.5 }, "patch"),
    "in-range species scale overrides validate as a patch")
  local bad, err = Schemas.check(spec, "pokemon", "PIKACHU",
    { battleScaleBack = 5 }, "patch")
  check(not bad, "an out-of-range species scale is rejected")
  check(tostring(err):find("battleScaleBack", 1, true) ~= nil,
    "the rejection names the field: " .. tostring(err))
end

-- ------- the full merge: a mod patches a species and registers an image

local FILES = {
  ["mods/biggun/manifest.json"] = manifest("biggun"),
  ["mods/biggun/main.lua"] = [[
    local mod = ...
    -- species-level: PIKACHU's back pic at 3x
    mod.content.pokemon:patch("PIKACHU", { battleScaleBack = 3 })
    -- image-level, keyed by path: overrides the species scale for this pic
    mod.content.battle_sprite_scales:register("pika_back", {
      path = "pikachu_back.png", scale = 1.25,
    })
    -- and a bare, non-species pic (a trainer back) reachable only here
    mod.content.battle_sprite_scales:register("hero_back", {
      path = "assets/generated/battle/back/redb.png", scale = 1.5,
    })
  ]],
}

local data = baseData()
local loader = Loader.new({ fs = memfs(FILES) })
local okLoad = loader:load(data)
check(okLoad, "the scale mod loads clean: " .. table.concat(loader.errors, "; "))

eq(data.pokemon.PIKACHU.battleScaleBack, 3,
  "the species patch reached the merged data")
check(type(data.battle_sprite_scales) == "table",
  "the merge created the battle_sprite_scales namespace")

-- image-level beats species-level for the same pic
eq(BattleState.resolveBattleScale(data, "back", "pikachu_back.png", "PIKACHU"),
  1.25, "an image-level entry overrides the species scale for its path")
-- a different pic of the same species falls through to the species scale
eq(BattleState.resolveBattleScale(data, "back", "raichu_back.png", "PIKACHU"),
  3, "a species with an override but no image entry uses the species scale")
-- the non-species trainer back is reachable only by path
eq(BattleState.resolveBattleScale(data, "back",
  "assets/generated/battle/back/redb.png", nil),
  1.5, "a bare pic is scaled by its image-level entry with no species")
-- an unregistered species, unregistered path: the vanilla side defaults
eq(BattleState.resolveBattleScale(data, "front", "raichu_front.png", "RAICHU"),
  1, "enemy front defaults to 1x when nothing is registered")
eq(BattleState.resolveBattleScale(data, "back", "raichu_back.png", "RAICHU"),
  2, "player back defaults to 2x when nothing is registered")

-- ------- default unchanged with no registry at all

do
  local bare = { pokemon = { PIKACHU = {} } }
  eq(BattleState.resolveBattleScale(bare, "front", "any.png", "PIKACHU"), 1,
    "front default holds with no battle_sprite_scales table")
  eq(BattleState.resolveBattleScale(bare, "back", "any.png", "PIKACHU"), 2,
    "back default holds with no battle_sprite_scales table")
  eq(BattleState.resolveBattleScale({}, "back", nil, nil), 2,
    "back default holds with empty data and no path or species")
end

-- ------- placement math: feet stay pinned at every scale

local W, H, PAD, PADL = 56, 40, 3, 2

do
  for _, s in ipairs({ 0.5, 1, 2, 3 }) do
    local x, y, sc = BattleState.backPlacement(W, H, PAD, PADL, s)
    eq(sc, s, "back placement returns the scale (scale " .. s .. ")")
    eq(y + (H - PAD) * s, 96,
      "player feet stay on the text-box top at scale " .. s)
    eq(x, 8 - PADL * s,
      "player left pad is pulled back proportionally at scale " .. s)
  end

  local ex, ey = 100, 20
  for _, s in ipairs({ 0.5, 1, 2, 3 }) do
    local x, y = BattleState.frontPlacement(ex, ey, W, H, s)
    eq(y + H * s, ey + H,
      "enemy bottom edge stays pinned to its slot at scale " .. s)
    eq(x + W * s / 2, ex + W / 2,
      "enemy horizontal centre stays pinned at scale " .. s)
  end

  -- the s=1 case is the vanilla draw exactly: no shift
  local x1, y1 = BattleState.frontPlacement(ex, ey, W, H, 1)
  check(x1 == ex and y1 == ey, "scale 1 front placement is the untouched slot")
end

-- ------- composition with the send-out grow

do
  -- growInScale returns the AnimateSendingOutMon stages; a mod scale
  -- composes multiplicatively, and the composed pic is still grounded
  local moddedBack = BattleState.resolveBattleScale(
    { pokemon = { GROWMON = { battleScaleBack = 1.5 } } }, "back", nil, "GROWMON")
  eq(moddedBack, 1.5, "species back override resolved for the grow test")

  for _, gs in ipairs({ 3 / 7, 5 / 7, 1 }) do
    local eff = moddedBack * gs
    local _, y = BattleState.backPlacement(W, H, PAD, PADL, eff)
    eq(y + (H - PAD) * eff, 96,
      "player feet stay pinned through grow stage " .. gs)

    local ex, ey = 100, 20
    local _, ey2 = BattleState.frontPlacement(ex, ey, W, H, eff)
    eq(ey2 + H * eff, ey + H,
      "enemy bottom stays pinned through grow stage " .. gs)
  end
end

S.finish()
