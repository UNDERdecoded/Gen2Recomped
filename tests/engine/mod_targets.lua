package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Manifest = require("src.mods.Manifest")
local Targets = require("src.mods.ModTargets")
local Gens = require("src.mods.ModGens")
local Versions = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local Json = require("src.link.Json")
local Launcher = require("src.mods.LauncherMods")
local Manager = require("src.mods.ManagerState")
local savedVersion = Versions.get()
local function manifest(extra, id)
  local raw = {id=id or "edition_mod", name=id or "Edition Mod", version="1.0.0", api=2, entry="main.lua"}
  for k,v in pairs(extra or {}) do raw[k]=v end
  return raw
end
local function boot(version, extra, options)
  Versions.set(version)
  local raw = manifest(extra)
  local files = {
    ["mods/edition_mod/manifest.json"] = Json.encode(raw),
    ["mods/edition_mod/main.lua"] = "local mod=...;mod.exports.executed=true;mod.events:on('mod.edition_mod.probe',function()end)",
    ["mods/consumer/manifest.json"] = Json.encode(manifest({games={"all"}, dependencies={"edition_mod"}}, "consumer")),
    ["mods/consumer/main.lua"] = "local mod=...;mod.exports.executed=true",
    ["mods/independent/manifest.json"] = Json.encode(manifest({games={"all"}}, "independent")),
    ["mods/independent/main.lua"] = "local mod=...;mod.exports.executed=true",
  }
  local fs = T.sdk.memfs(files)
  if options then SaveData.saveOptions(options, fs) end
  local run = T.sdk.loadMods({"mods/edition_mod","mods/consumer","mods/independent"}, {fs=fs,dev=false})
  return run
end

local scoped = Manifest.validate(manifest({games={" BLUE ","blue"}}))
T.same(scoped.games,{"blue"},"edition tokens normalize and deduplicate")
T.eq(scoped.gen2compat,false,"edition claim derives legacy compatibility metadata")
T.eq(Manifest.validate(manifest({games={"gold"}})).gen2compat,true,"second-generation claim derives compatibility metadata")
local function available(ids)
  local out={};for _,id in ipairs(ids) do if Versions.VERSIONS[id] then out[#out+1]=id end end;return out
end
T.same(Targets.normalize({"frlg"}), available({"firered","leafgreen"}), "FRLG family expands to native editions")
T.same(Targets.normalize({"rse"}), available({"ruby","sapphire","emerald"}), "RSE family follows launcher order")
T.same(Targets.normalize({"GEN 2"}), Targets.expand("gen2"), "generation token is case/space insensitive")
T.eq(Manifest.validate(manifest()).games,nil,"undeclared host mods retain their generation policy")
T.check(Targets.supports(Manifest.validate(manifest()),"emerald"),"legacy host manifest remains allowed")
local additive = Manifest.validate(manifest({games={"blue"}, gen2compat=true}))
T.check(Targets.supports(additive,"blue"),"legacy flag keeps explicit edition")
T.check(Targets.supports(additive,"gold"),"legacy flag adds second-generation games")
T.eq(Targets.supports(additive,"red"),false,"additive flag does not widen first-generation claim")
local legacy = Manifest.validate(manifest({gen2compat=true}))
T.check(Targets.supports(legacy,"red"),"legacy compatibility flag includes first generation")
T.check(Targets.supports(legacy,"crystal"),"legacy compatibility flag includes second generation")
T.eq(Targets.supports(legacy,"emerald"),false,"legacy flag excludes unrelated generations")
for _,bad in ipairs({"blue", {"unknown_game"}, {[2]="blue"}, {[1]="blue",[3]="red"}, {blue=true}, {}}) do
  T.raises(function() Manifest.validate(manifest({games=bad})) end,nil,"invalid edition declaration rejected")
end
local relaxed=Manifest.validate(manifest({api=1,games={"blue","unknown_game"}}))
T.same(relaxed.games,{"blue"},"API 1 retains recognized editions with unknown tokens")
T.eq(Gens.allows(scoped,1),true,"generation chips include an explicit edition")
T.eq(Gens.allows(scoped,2),false,"generation chips exclude undeclared editions")
local intersection=Manifest.validate(manifest({games={"all"},generations={3}}))
T.eq(Gens.allows(intersection,1),false,"existing generation restriction still applies")
T.eq(Gens.allows(intersection,3),true,"intersection retains supported generation")

for _,version in ipairs(Versions.ORDER) do
  local run=boot(version,{games={"blue"}})
  local wanted=version=="blue"
  T.eq(run.loader.exports.edition_mod~=nil,wanted,version..": original entry obeys edition claim")
  T.eq(run.loader.exports.consumer~=nil,wanted,version..": hard dependent follows the target skip")
  T.check(run.loader.exports.independent.executed,version..": unrelated mod still runs")
  T.eq(#run.errors,0,version..": target skips are not failures")
  if not wanted then
    T.eq(run.mods.edition_mod.state,"wrong_game",version..": distinct skipped state")
    T.check(run.mods.consumer.skipReason:find("does not run here",1,true),version..": dependency skip explains its source")
    T.eq((run.loader.apis or {}).edition_mod,nil,version..": skipped entry receives no API or subscriptions")
  end
  run.release()
end

local options={modsGames={edition_mod={red=true}}}
local run=boot("red",{games={"blue"}},options)
T.check(run.loader.exports.edition_mod.executed,"per-edition override loads the original entry")
T.eq(run.mods.edition_mod.forcedGame,"red","forced edition is attributed in runtime status")
run.release()
run=boot("emerald",{games={"blue"}},options)
T.eq(run.loader.exports.edition_mod,nil,"override does not spread to another edition")
run.release()
run=boot("red",{games={"blue"}},{mods={edition_mod=false},modsGames={edition_mod={red=true}}})
T.eq(run.loader.exports.edition_mod,nil,"override does not bypass player's off switch")
run.release()
run=boot("red",{games={"blue"}},{mods={edition_mod={on=true,force={true},gens={true}}}})
T.eq(run.loader.exports.edition_mod,nil,"generation override does not widen an edition claim")
run.release()
T.eq(Targets.forced({modsGen2={edition_mod=true}},"edition_mod","red"),false,"old boolean override excludes first generation")
T.eq(Targets.forced({modsGen2={edition_mod=true}},"edition_mod","crystal"),true,"old boolean override retains its generation")
T.eq(Targets.forced({modsGen2={edition_mod={red=true}}},"edition_mod","gold"),false,"old table override remains edition-specific")

Versions.set("red")
local rows=Launcher.deriveList({scoped},{mods={}},"red")
T.eq(rows[1].status,"other_game","launcher reports the runtime's edition exclusion")
T.eq(rows[1].targets,"Blue","launcher names supported editions")
T.same(rows[1].supportedGens,{1},"launcher chips reflect edition claims")
local m=scoped
m.enabled,m.state,m.skipReason=true,"wrong_game","For Blue, not Red"
local writes=0
local game={save={options={mods={}}},modStatus={available={m},errors={}},writeOptions=function() writes=writes+1 end}
local manager=Manager.new(game)
manager:refresh()
local action
for _,row in ipairs(manager:detailRows(m)) do if row.label=="TRY HERE ANYWAY" then action=row.action end end
T.check(action~=nil,"manager offers an explicit per-game override")
action()
T.check(Targets.forced(game.save.options,m.id,"red"),"manager stores the selected edition only")
T.check(manager.restartPending,"target change requires restart")
T.eq(Targets.forced(game.save.options,m.id,"gold"),false,"manager does not force other games")
for _,row in ipairs(manager:detailRows(m)) do if row.label=="STOP FORCING HERE" then row.action() end end
T.eq(manager.restartPending,false,"returning to the boot target is a no-op")
for _,row in ipairs(manager:detailRows(m)) do if row.label=="TRY HERE ANYWAY" then row.action() end end
manager:discardChanges()
T.eq(Targets.forced(game.save.options,m.id,"red"),false,"discard restores boot override state")
T.eq(manager.restartPending,false,"discard clears target-only pending change")
T.check(writes>0,"override uses the normal options writer")
Versions.set(savedVersion)
T.finish()
