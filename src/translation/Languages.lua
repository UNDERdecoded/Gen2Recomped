local L={
 {"original","Original ROM text"},{"en","English"},{"fr","French"},{"de","German"},
 -- two Portugueses, by Argos' own codes: "pt" is European, "pb" Brazilian
 {"es","Spanish"},{"it","Italian"},{"pt","Portuguese (Portugal)"},{"pb","Portuguese (Brazil)"},{"nl","Dutch"},
 {"pl","Polish"},{"cs","Czech"},{"da","Danish"},{"sv","Swedish"},
 {"fi","Finnish"},{"el","Greek"},{"ro","Romanian"},{"hu","Hungarian"},
 {"tr","Turkish"},{"nb","Norwegian"},{"bg","Bulgarian"},
 {"sk","Slovak"},{"sl","Slovenian"},{"ca","Catalan"},
 {"uk","Ukrainian"},{"ru","Russian"},{"ja","Japanese"},{"zh","Chinese (Simplified)"}}
function L.choices(inherit)
 local values,labels={},{}
 if inherit then values[1]="inherit";labels.inherit="Use launcher language" end
 for _,v in ipairs(L)do values[#values+1]=v[1];labels[v[1]]=v[2]end
 return values,labels
end
function L.resolve(options,version)
 options=type(options)=="table" and options or {}
 local per=type(options.translationPerGame)=="table" and options.translationPerGame[version] or {}
 per=type(per)=="table" and per or {}
 local target=per.target
 if not target or target=="inherit" then target=options.translationLanguage or "original" end
 local valid={original=true};for _,v in ipairs(L)do valid[v[1]]=true end
 if not valid[target] then target="original" end
 -- The source is what the ROM's text IS, not a choice: every ROM this port
 -- imports is identified as an English (USA) dump, so its text is English.
 -- A saved per-game or launcher "source" (an older settings row) is ignored --
 -- one set to the target language made French -> French jobs that returned
 -- the English text unchanged.
 local source=L.romLanguage(version)
 -- Nothing to translate when the target is the ROM's own language.
 if target==source then target="original" end
 return target,source
end
L._romLang={}
function L.romLanguage(version)
 local ok,GameVersion=pcall(require,"src.core.GameVersion")
 local info=ok and version and GameVersion.info and GameVersion.info(version)
 local lang=type(info)=="table" and info.textLanguage
 if type(lang)=="string" then return lang end
 -- a non-English Gen 4 cartridge (German Platinum) records its text language
 -- in its cache (gen4_language.lua); without it German ROM text would be
 -- sent for translation as if it were English
 if type(info)=="table" and info.cachePrefix then
  if L._romLang[version] then return L._romLang[version] end
  local okA,Art=pcall(require,"src.pokewalker.WalkerArt")
  local src=okA and Art._read and Art._read(info.cachePrefix,"data/generated/gen4_language.lua")
  local chunk=src and (loadstring or load)(src,"=gen4_language")
  local okC,rec=false,nil
  if chunk then okC,rec=pcall(chunk) end
  if okC and type(rec)=="table" and type(rec.language)=="string" then
   L._romLang[version]=rec.language
   return rec.language
  end
 end
 return "en"
end
function L.font(target)
 if target=="ja" or target=="zh" then
  return "NotoSansCJK-Regular.otf","https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
 end
 return "NotoSans-Regular.ttf","https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf"
end
return L
