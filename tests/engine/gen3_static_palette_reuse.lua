package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local F = require("tools.native-palettes.fixture")
local Tiles = require("src.render.Gen3Tiles")
local Copy = require("src.mods.Merge").deepCopy
for _, version in ipairs({"emerald", "firered"}) do
  local f = F.new(version, 2, true)
  local layout = f.state.game.data.constants.gen3Layout
  local pair = {primary=f.records.P, secondary=f.records.S}
  pair.primary.paletteCycles={};pair.secondary.paletteCycles={}
  local decoder = Tiles.new(pair, layout)
  T.eq(decoder:setPaletteTicks(0), true, "first static picture installed")
  local first, original = decoder.paletteState, Copy(pair)
  for tick=1,600 do
    T.eq(decoder:setPaletteTicks(tick), false, "static terrain never recolours")
    T.eq(decoder.paletteState, first, "static picture retains its owned colour tables")
  end
  T.eq(first.ticks,600,"static clock still advances")
  T.same(pair,original,"sampling does not mutate shared cartridge data")
  -- In-place edits, including entries outside the active bank split, must
  -- invalidate a picture; identity-only source caching would miss these.
  pair.secondary.palettes[1][1][2]=(pair.secondary.palettes[1][1][2]+1)%256
  T.eq(decoder:setPaletteTicks(601),true,"same-table source edit is observed")
  T.check(decoder.paletteState~=first,"changed source receives fresh owned picture")
  local changed=decoder.paletteState
  T.eq(first.secondary[1][1][2],original.secondary.palettes[1][1][2],"old picture remains detached")
  pair.primary.paletteCycles={{kind="rotate",first=17,count=4,step=1,direction=1}}
  T.eq(decoder:setPaletteTicks(602),true,"static-to-animated transition is sampled")
  T.check(#decoder.paletteState.primaryFrames==1,"animation resumes")
  pair.primary.paletteCycles={}
  T.eq(decoder:setPaletteTicks(603),true,"animated-to-static transition restores base")
  local function reject(edit)
    pair.primary=Copy(original.primary);pair.secondary=Copy(original.secondary)
    decoder.primary,decoder.secondary=pair.primary,pair.secondary
    assert(decoder:setPaletteTicks(0)~=nil)
    edit(pair)
    local _,reason=decoder:setPaletteTicks(1)
    T.eq(decoder.paletteState,nil,"invalid source cannot reuse stale colours")
    T.eq(reason,"palette animation data unavailable","invalid static source declines")
  end
  reject(function(p)p.primary.paletteCycles=nil end)
  reject(function(p)p.secondary.paletteCycles.extra=true end)
  reject(function(p)p.primary.palettes[2].extra=true end)
  reject(function(p)p.secondary.palettes[16][16][3]=256 end)
  reject(function(p)p.primary.palettes[1][1][1]=0/0 end)
  reject(function(p)p.primary.palettes[1][1]=setmetatable({1,2,3},{}) end)
  decoder.primary,decoder.secondary=original.primary,original.secondary
  decoder:setPaletteTicks(0)
  local _,reason=decoder:setPaletteTicks(-1)
  T.eq(decoder.paletteState,nil,"invalid clock cannot retain static picture")
  T.eq(reason,"terrain clock unavailable","clock rejection preserved")
  decoder:setPaletteTicks(0);decoder.palettesInPrimary=0
  decoder:setPaletteTicks(1)
  T.eq(decoder.paletteState,nil,"invalid split cannot reuse static picture")
  f.run.release()
end
T.finish("Native static palette reuse and mutable-source invalidation")
