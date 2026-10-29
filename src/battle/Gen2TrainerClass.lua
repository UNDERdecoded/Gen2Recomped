-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Canonical vanilla GSC class identities in TrainerGroups order. Imported
-- records carry this numeric index; their translated/display name is not an
-- identity (all badge leaders can be named LEADER).
local Class = {}
local names = {
 'FALKNER','WHITNEY','BUGSY','MORTY','PRYCE','JASMINE','CHUCK','CLAIR',
 'RIVAL1','POKEMON_PROF','WILL','CAL','BRUNO','KAREN','KOGA','CHAMPION',
 'BROCK','MISTY','LT_SURGE','SCIENTIST','ERIKA','YOUNGSTER','SCHOOLBOY',
 'BIRD_KEEPER','LASS','JANINE','COOLTRAINERM','COOLTRAINERF','BEAUTY','POKEMANIAC',
 'GRUNTM','GENTLEMAN','SKIER','TEACHER','SABRINA','BUG_CATCHER','FISHER','SWIMMERM',
 'SWIMMERF','SAILOR','SUPER_NERD','RIVAL2','GUITARIST','HIKER','BIKER','BLAINE',
 'BURGLAR','FIREBREATHER','JUGGLER','BLACKBELT_T','EXECUTIVEM','PSYCHIC_T',
 'PICNICKER','CAMPER','EXECUTIVEF','SAGE','MEDIUM','BOARDER','POKEFANM',
 'KIMONO_GIRL','TWINS','POKEFANF','RED','BLUE','OFFICER','GRUNTF','MYSTICALMAN',
}
function Class.fromIndex(index)
 return names[tonumber(index)]
end
return Class
