-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Bind existing address metadata to verified cartridge bytes. The cache owns
-- decoded text and layout operands; no private decoder or ROM is distributed.
local M={SCHEMA=1,REVISION=5}
function M.bind(extractor,text,addresses)
 local rows={schema=M.SCHEMA,named={},records={}}
 local count=0
 for label,off in pairs(addresses)do
  local isText=type(label)=='string'and(label:match('^[gs]Text_')or label:match('^gOtherText_')
   or label:match('^BattleText_')or label:match('^BattleStatText_')
   or label:match('_Text_')or label:match('^Text_')or label:match('Names%[')or label=='gString_Help')
  if isText and type(off)=='number'and off>=0 and off%1==0 and off<extractor.rom.size then
   local id=('TEXT_%06X'):format(off)
   local row=rows.records[id]
   if not row then
    local ok,plain,used,ir=pcall(extractor.readText,extractor,off,4096,nil,true)
    if ok and plain and ir then
     -- Keep the native script decoder's existing value authoritative. The
     -- snapshot lets readers distinguish later registry edits from that value.
     row={plain=plain,ir=ir,nativePlain=text[id],address=off,bytes=used}
     rows.records[id]=row
    end
   end
   if row then rows.named[label]=id;count=count+1 end
  end
 end
 return rows,count
end
function M.extract(extractor,text)
 local Version=require('src.core.GameVersion')
 local edition=type(extractor.version)=='table'and extractor.version.id or extractor.version
 local info=Version.info(edition)
 if not(info and info.generation==3 and extractor.manifest.romSha1==info.sha1)then
  return nil,'named text requires a verified native GBA source'
 end
 local ok,digest=pcall(require('src.import.RomVerification').sha1,extractor.rom.data)
 if not ok or digest~=info.sha1 then return nil,'named text cartridge fingerprint mismatch'end
 -- Reduced GPL address facts are native import inputs. They do not require
 -- a language pack; their existing provenance stays with each profile.
 local addresses=require('src.import.gba.text_labels.'..edition)
 local rows,count=M.bind(extractor,text,addresses)
 rows.edition=edition;rows.romSha1=digest
 local ok,battleCount=require('src.import.Gen3BattleTextCatalog').append(extractor,text,rows)
 if not ok then return nil,battleCount end
 return rows,count+battleCount
end
return M
