-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Audited strip locations for exact cartridge digests, also used when an
-- older manifest predates optional fieldMoveStreaks metadata.
local profiles={
 ['41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc']={edition='firered',schema=1,romSha1='41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc',strips={
  indoors={tiles=0x3CBA90,palette=0x3CBB10,tilemap=0x3CBB30,tileCount=4},
  outdoors={tiles=0x3CB5F0,palette=0x3CB7F0,tilemap=0x3CB810,tileCount=16},
 }},
 ['574fa542ffebb14be69902d1d36f1ec0a4afd71e']={edition='leafgreen',schema=1,romSha1='574fa542ffebb14be69902d1d36f1ec0a4afd71e',strips={
  indoors={tiles=0x3CB8CC,palette=0x3CB94C,tilemap=0x3CB96C,tileCount=4},
  outdoors={tiles=0x3CB42C,palette=0x3CB62C,tilemap=0x3CB64C,tileCount=16},
 }},
 ['f3ae088181bf583e55daf962a92bb46f4f1d07b7']={edition='emerald',schema=1,romSha1='f3ae088181bf583e55daf962a92bb46f4f1d07b7',strips={
  indoors={tiles=0x55B2F0,palette=0x55B370,tilemap=0x55B390,tileCount=4},
  outdoors={tiles=0x55AE50,palette=0x55B050,tilemap=0x55B070,tileCount=16},
 }},
 ['f28b6ffc97847e94a6c21a63cacf633ee5c8df1e']={edition='ruby',schema=1,romSha1='f28b6ffc97847e94a6c21a63cacf633ee5c8df1e',strips={
  indoors={tiles=0x39EDB4,palette=0x39EE34,tilemap=0x39EE54,tileCount=4},
  outdoors={tiles=0x39E914,palette=0x39EB14,tilemap=0x39EB34,tileCount=16},
 }},
 ['3ccbbd45f8553c36463f13b938e833f652b793e4']={edition='sapphire',schema=1,romSha1='3ccbbd45f8553c36463f13b938e833f652b793e4',strips={
  indoors={tiles=0x39EBFC,palette=0x39EC7C,tilemap=0x39EC9C,tileCount=4},
  outdoors={tiles=0x39E75C,palette=0x39E95C,tilemap=0x39E97C,tileCount=16},
 }},
}
return{forSha1=function(sha1,edition)
 local p=profiles[sha1];if p and p.edition==edition then return p end
end}
