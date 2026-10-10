love=love or {filesystem={}}
local L=require("src.translation.Languages")
local P=require("src.translation.Plan")
local Serializer=require("src.core.SaveSerializer")
local options={translationLanguage="fr",translationSource="en",translationPerGame={emerald={target="ja"},crystal={target="original"}}}
assert(L.resolve(options,"red")=="fr")
assert(L.resolve(options,"emerald")=="ja")
assert(L.resolve(options,"crystal")=="original")
local restored=assert(Serializer.decode(Serializer.encode(options)))
assert(L.resolve(restored,"emerald")=="ja")
assert(L.resolve({translationLanguage="../../bad"},"red")=="original")
local source="Hello {RAM:wPlayerName}!\nPikachu learned %s.\fYou have %02d coins. %%"
local plan=P.build({source,"Pikachu"},{Pikachu="Pikachu-localized"})
for _,text in ipairs(plan.texts)do
 assert(not text:find("RAM",1,true) and not text:find("%%s",1,true))
end
local translations={}
for i,text in ipairs(plan.texts)do translations[i]="translated:"..text end
local catalog=P.finish(plan,translations)
assert(catalog[source]:find("{RAM:wPlayerName}",1,true))
assert(catalog[source]:find("%s",1,true) and catalog[source]:find("%02d",1,true))
assert(catalog[source]:find("%%",1,true) and catalog[source]:find("\f",1,true))
assert(catalog.Pikachu=="Pikachu-localized")
assert(not pcall(P.finish,plan,{}))
translations[1]="{RAM:corrupt}"
assert(not pcall(P.finish,plan,translations))
-- the official names are built on the device from PokeAPI's CSVs (none ship)
local G=require("src.translation.Glossary")
local species=[[pokemon_species_id,local_language_id,name,genus
25,9,Pikachu,Mouse Pokémon
25,5,Pikachu,Pokémon Souris
25,11,ピカチュウ,ねずみポケモン
25,12,皮卡丘,"鼠宝可梦, quoted"
6,9,Charizard,Flame Pokémon
6,6,Glurak,Flammen-Pokémon
]]
local csvs={["pokemon_species_names.csv"]=species}
assert(G.build(csvs,"fr").PIKACHU=="Pikachu" and G.build(csvs,"de").CHARIZARD=="Glurak")
assert(G.build(csvs,"ja").PIKACHU=="ピカチュウ" and G.build(csvs,"zh").PIKACHU=="皮卡丘")
assert(G.build(csvs,"pt").CHARIZARD=="Charizard","a language PokeAPI lacks keeps the English name")
assert(G.build(csvs,"de")["POKéMON CENTER"]=="Pokémon-Center")
assert(not io.open("data/localization/terms.lua","rb"),"the official names must not ship with the project")
local fs=love.filesystem
local originalRead,originalInfo=fs.read,fs.getInfo
fs.read=function(path)if path:find("translations/",1,true)then return require("src.link.Json").encode({catalog={Hello="Bonjour",PIKACHU="ピカチュウ"}})end end
fs.getInfo=function()return {type="file"}end
local Service=require("src.translation.Service")
local data={text={greeting="Hello",script="{RAM:player}"},pokemon={SPECIES_025={name="PIKACHU",index=25}},moves={},items={},trainers={}}
local originalText=data.text
Service.install(data,"emerald",options)
assert(data.text.greeting=="Bonjour" and originalText.greeting=="Hello")
assert(data.text.script=="{RAM:player}" and data.pokemon.SPECIES_025.index==25)
assert(data.pokemon.SPECIES_025.name=="ピカチュウ")
assert(data.pokemon.SPECIES_025.translationSourceName=="PIKACHU")
Service.install({text={}},"crystal",options)
assert(Service.lookup("Hello")=="Hello")
fs.read,fs.getInfo=originalRead,originalInfo
print("PASS global/per-game language precedence and option save roundtrip")
print("PASS localized names, placeholders, formatting and page controls")
print("PASS immutable source text, runtime overlays and original-language restore")

local Importer=require("src.import.RomImporter")
local fake=setmetatable({_settings=function()return options end},{__index=Importer})
local entry={scope="translation",version="emerald",row={id="target"}}
assert(fake:_settingValue(entry)=="ja")
fake:_setSettingValue(entry,"de")
assert(fake:_settingValue(entry)=="de" and L.resolve(options,"red")=="fr")
fake:_setSettingValue(entry,"inherit")
assert(L.resolve(options,"emerald")=="fr")
local global={scope="launcher",row={id="translationLanguage"}}
fake:_setSettingValue(global,"es")
assert(fake:_settingValue(global)=="es" and L.resolve(options,"emerald")=="es")
print("PASS actual launcher setting accessors and independent per-game overrides")
fake:_openTranslationSettings("emerald")
assert(fake.settingsOpen and fake.settingsPage=="translation" and fake._translationSettingsVersion=="emerald")
options.translationPerGame.emerald.target="original"
fake:_settingsAction({action="translateGame",version="emerald"})
assert(fake.settingsNotice:find("Choose a translation",1,true))
options.translationPerGame.emerald.target="es"
local oldEnqueue=Service.enqueue
local queued
Service.enqueue=function(version,opts)queued=version;assert(opts==options)end
fake:_settingsAction({action="translateGame",version="emerald"})
Service.enqueue=oldEnqueue
assert(queued=="emerald" and fake.settingsNotice:find("queued",1,true))
print("PASS game-page translation controls and visible original-language guidance")
local Progress=require("src.translation.Progress")
local fraction,detail=Progress.describe({progress={done=1048576,total=2097152,unit="bytes"}})
assert(fraction==0.5 and detail:find("50%%") and detail:find("1.0 MB / 2.0 MB",1,true))
assert(Progress.describe({progress={done=7,total=10,unit="segments"}})==0.7)
assert(Progress.describe({progress={done=123,total=0,unit="bytes"}})==nil)
assert(Progress.describe({progress={done=12,total=10}})==1)
print("PASS download bytes, translation counts and unknown-size progress")
assert(fake:_settingValue({scope="launcher",row={id="launcherLanguage"}})=="en")
local oldLauncher=Service.enqueueLauncher
local oldGameLanguage=options.translationLanguage
fs.read=function()return nil end;fs.getInfo=function()return nil end
local launcherQueued
Service.enqueueLauncher=function(opts)launcherQueued=opts.launcherLanguage end
fake:_setSettingValue({scope="launcher",row={id="launcherLanguage"}},"fr")
assert(launcherQueued=="fr" and options.translationLanguage==oldGameLanguage)
assert(options.launcherLanguage=="fr" and options.translationPerGame.emerald.target=="es")
Service.enqueueLauncher=oldLauncher
Service.setLauncher({launcherLanguage="en"})
assert(Service.launcherLookup("Hello")=="Hello")
assert(#require("data.localization.launcher_sources")>100)
fs.read,fs.getInfo=originalRead,originalInfo
print("PASS launcher defaults to English and remains independent of game language")
-- the ROM's language is not a setting: a saved French "source" no longer makes
-- a French -> French job that leaves the English text untouched
do
 local t,s=L.resolve({translationPerGame={crystal={source="fr",target="fr"}}},"crystal")
 assert(t=="fr" and s=="en","a saved source is ignored; the ROM's text is English")
 assert(L.resolve({translationLanguage="en"},"red")=="original","English onto an English ROM is nothing to translate")
 print("PASS source language comes from the ROM, not a setting")
end
