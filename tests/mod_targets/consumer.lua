-- Identical edition-claim consumer for two independent native hosts.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Manifest = require("src.mods.Manifest")
local Targets = require("src.mods.ModTargets")
local Versions = require("src.core.GameVersion")
local Json = require("src.link.Json")
if arg[1] == "--catalog" then print("TARGET_CATALOG "..Json.encode(Versions.ORDER)); return end
local cases = {
  {games={"blue"}}, {games={"red","blue","blue"}},
  {games={"gen1"}}, {games={"Gen 2"}}, {games={"gen3"}},
  {games={"frlg"}}, {games={"rse"}}, {games={"all"}},
  {games={"blue"},gen2compat=true}, {gen2compat=true}, {gen2compat=false},
}
local out = {}
for n,extra in ipairs(cases) do
  local raw={id="consumer",name="Consumer",version="1.0.0",entry="main.lua",api=2}
  for key,value in pairs(extra) do raw[key]=value end
  local manifest=Manifest.validate(raw)
  for _,version in ipairs(arg) do
    assert(Versions.VERSIONS[version], "unknown requested edition")
    out[#out+1]={case=n,version=version,allowed=Targets.supports(manifest,version,Versions.generation(version))}
  end
end
print("TARGET_CONTRACT "..Json.encode(out))
