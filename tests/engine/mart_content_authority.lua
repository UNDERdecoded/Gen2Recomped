package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local F = dofile("tests/mart_content/fixture.lua")
local Copy = require("src.mods.Merge").deepCopy
local old = V.get()
local function fresh(api, format, body)
  return F.new(".", "gen2", "gold", api, format, "none", body)
end
for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
  local api, format = unpack(mode)
  local f = F.new(".", "gen2", "gold", api, format, "replace")
  local m = f.e.api.content.marts
  T.eq(f.e.api:supports("content", "marts"), true, "public capability names the native registry")
  local pool = f.data.map_scripts.marts
  T.same(pool[0], { f.key("ULTRA_BALL") }, "public item ID reaches native pool key")
  T.eq(f.data.gen2Marts, nil, "virtual registry creates no foreign namespace")
  T.raises(function()
    m:patch("0", { "POTION" })
  end, "frozen", "late shelf writes are frozen")
  local stock = m:get("0")
  stock[1] = "CORRUPTED"
  for _, row in m:each() do
    row[1] = "CORRUPTED"
  end
  T.same(m:get("0"), { "ULTRA_BALL" }, "public reads cannot mutate the native pool")
  local before = pool[1]
  pool[1] = { "UNRELATED" }
  f.close()
  for root in pairs(require("src.mods.Builtins").namespaceRoots()) do
    if root ~= "items" and root ~= "map_scripts" then
      f.data[root] = nil
    end
  end
  local r = T.sdk.loadNone({ data = f.data })
  T.same(pool[0], { f.key("POTION"), f.key("ANTIDOTE") }, "reload retires previous shelf writes")
  T.eq(f.data.map_scripts.marts, pool, "reload preserves mounted pool identity")
  T.same(pool[1], { "UNRELATED" }, "reload preserves unrelated native shelves")
  T.eq(before, nil, "fixture side shelf was originally absent")
  r.release()
  local no = F.new(".", "gen2", "gold", api, format, "no-mod")
  T.same(no.shelf("0"), { no.key("POTION"), no.key("ANTIDOTE") }, "no-mod native stock unchanged")
  T.same(
    no.shelf("bargain"),
    { { item = no.key("NUGGET"), price = 4500 } },
    "no-mod native bargain price unchanged"
  )
  no.close()
  for _, id in ipairs({ '"00"', '"-1"', '"34"', '"MART_CHERRYGROVE"', '"generation"', '""', "0", "nil" }) do
    local bad = fresh(
      api,
      format,
      'mod.content.marts:patch("0", {"ULTRA_BALL"}); mod.content.marts:patch(' .. id .. ", {})"
    )
    T.check(#bad.result.errors > 0, "invalid mart ID rejects entry " .. id)
    T.same(bad.shelf("0"), { bad.key("POTION"), bad.key("ANTIDOTE") }, "ID failure rolls earlier write back")
    bad.close()
  end
  for _, value in ipairs({ '{[2]="POTION"}', '{__append={"POTION"}}', '{[0]="POTION"}', '{other="POTION"}' }) do
    local bad = fresh(api, format, 'mod.content.marts:patch("0", ' .. value .. ")")
    T.check(#bad.result.errors > 0, "non-contiguous and wrapper stock rejected")
    T.eq(next(bad.result.loader.content.marts.ops), nil, "invalid stock leaves no registry operations")
    bad.close()
  end
  if api >= 2 then
    for _, value in ipairs({
      '{{item="NUGGET",price=-1}}',
      '{{item="NUGGET",price=65536}}',
      '{{item="NUGGET",price=0/0}}',
      '{{item="NUGGET",price=math.huge}}',
      '{{item="NUGGET"}}',
      "{{price=1}}",
      '{{item="NUGGET",price=1,typo=true}}',
    }) do
      local bad = fresh(
        api,
        format,
        'mod.content.marts:patch("0", {"ULTRA_BALL"}); mod.content.marts:patch("bargain", ' .. value .. ")"
      )
      T.check(#bad.result.errors > 0, "invalid bargain row rejects entire entry")
      T.same(
        bad.shelf("bargain"),
        { { item = bad.key("NUGGET"), price = 4500 } },
        "invalid bargain row cannot alter native prices"
      )
      T.same(
        bad.shelf("0"),
        { bad.key("POTION"), bad.key("ANTIDOTE") },
        "bargain failure rolls ordinary shelf back"
      )
      bad.close()
    end
  end
  local forward = fresh(
    api,
    format,
    [[mod.content.marts:patch("0",{"CUSTOM_MART"});
    mod.content.items:register("ITEM_240",{id="ITEM_240",index=240,name="CUSTOM MART",price=300})]]
  )
  T.eq(#forward.result.errors, 0, "forward common item reference resolves after ordinary item merge")
  T.same(forward.shelf("0"), { "ITEM_240" }, "forward reference reaches actual imported key")
  T.same(forward.e.api.content.marts:get("0"), { "CUSTOM_MART" }, "forward public read uses common name")
  forward.close()
end
-- An unrelated in-place edit after the merge is not owned by retirement.
do
  local f = F.new(".", "gen2", "gold", 3, "unified", "replace")
  local pool = f.data.map_scripts.marts
  pool[0][1] = f.key("ANTIDOTE")
  f.close()
  for root in pairs(require("src.mods.Builtins").namespaceRoots()) do
    if root ~= "items" and root ~= "map_scripts" then
      f.data[root] = nil
    end
  end
  local r = T.sdk.loadNone({ data = f.data })
  T.same(pool[0], { f.key("ANTIDOTE") }, "reload preserves unrelated in-place shelf edit")
  r.release()
end
-- Native script dispatch and ordinary UI input, including close/resume.
do
  local f = F.new(".", "gen2", "gold", 3, "unified", "replace")
  local Stack = require("src.core.StateStack")
  local game = { data = f.data, save = { money = 10000, inventory = {}, bagOrder = {} } }
  game.stack = setmetatable({}, { __index = Stack })
  game.stack:init()
  local button
  game.input = {
    wasPressed = function(_, key)
      return button == key
    end,
  }
  local yielded, resumed = 0, 0
  local runner = {
    yield = function()
      yielded = yielded + 1
    end,
    resume = function()
      resumed = resumed + 1
    end,
  }
  local function press(key)
    button = key
    game.stack:top():update(1 / 60)
    button = nil
    for _ = 1, 20 do
      local top = game.stack:top()
      if top and top.update then
        top:update(1 / 60)
      end
    end
  end
  require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  Commands.g2_mart({ game = game, runner = runner }, 0, 0)
  T.eq(yielded, 1, "ordinary native shop yields runner")
  press("a")
  press("a")
  press("a")
  press("a")
  T.eq(game.save.inventory[f.key("ULTRA_BALL")], 1, "native shop input grants item")
  T.eq(game.save.money, 8800, "native shop input charges ordinary item price")
  press("b")
  press("b")
  T.eq(resumed, 1, "ordinary shop close resumes runner exactly once")
  Commands.g2_mart({ game = game, runner = runner }, 33, 2)
  T.eq(yielded, 2, "bargain native command selects independent stock")
  press("a")
  press("a")
  press("a")
  T.eq(game.save.inventory[f.key("NUGGET")], 1, "bargain input grants one item")
  T.eq(game.save.money, 8300, "bargain input charges its own price")
  press("a")
  T.eq(game.save.money, 8300, "sold-out input charges nothing")
  T.eq(game.save.inventory[f.key("NUGGET")], 1, "sold-out input grants nothing")
  press("b")
  T.eq(resumed, 2, "bargain close resumes runner exactly once")
  T.eq(game.stack:top(), nil, "native shop closes all its owned screens")
  f.close()
end
-- Real ROM IR lowering must retain the type that chooses the separate prices.
V.set("gold")
local data = { map_scripts = { scripts = { shop = { { "pokemart", 2, 33 }, { "end" } } } } }
local rows = require("src.script.Gen2ScriptVM").compile(data, "shop")
local seen = false
for _, row in ipairs(rows or {}) do
  if row[1] == "g2_mart" then
    T.same(row, { "g2_mart", 33, 2 }, "ROM type survives native script lowering")
    seen = true
  end
end
T.check(seen, "compiled native shop command exists")
local Extract = require("src.import.RomExtractorGen2")
local bytes = {
  [0x4000] = 0x02,
  [0x4001] = 0x40,
  [0x4002] = 2,
  [0x4003] = 18,
  [0x4004] = 9,
  [0x4100] = 2,
  [0x4101] = 36,
  [0x4102] = 0xf4,
  [0x4103] = 1,
  [0x4104] = 2,
  [0x4105] = 0xff,
  [0x4106] = 0xff,
}
local rom = {
  byte = function(_, _, address)
    assert(bytes[address], "out of fixture ROM")
    return bytes[address]
  end,
}
rom.word = function(self, bank, address)
  return self:byte(bank, address) + 256 * self:byte(bank, address + 1)
end
local extract = setmetatable(
  { symbols = { Marts = { 1, 0x4000 }, BargainShopData = { 1, 0x4100 } }, rom = rom },
  { __index = Extract }
)
local marts = extract:gen2Marts()
T.same(marts[0], { "ITEM_018", "ITEM_009" }, "real ROM reader keeps ordinary zero-based rows")
T.same(
  marts.bargain,
  { { item = "ITEM_036", price = 500 }, { item = "ITEM_002", price = 65535 } },
  "real ROM reader retains independent 16-bit bargain prices"
)
local Stock = require("src.inventory.Gen2MartStock")
local native = { map_scripts = { marts = marts } }
local shelf, opts = Stock.get(native, 33, 2)
T.eq(shelf, marts.bargain, "bargain ignores ordinary script mart number")
T.eq(opts.bargain, true, "bargain carries native transaction policy")
T.eq(Stock.entry(native, { martId = 0, mart = { "STALE" } }), marts[0], "annotated fallback uses live shelf")
V.set(old)
T.finish("mart ownership, rollback, reload, validation and native import/VM")
