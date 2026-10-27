#!/usr/bin/env python3
"""Build native Ruby/Sapphire metadata from a verified matching pret build.

Only addresses, layouts and hashes are emitted; supply your own cartridge.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
from gen3_sibling_manifest import Symbols
import gen3_discover as discover
from gen3_source_flags import source_metadata
from gen3_rs_ball_metadata import rs_ball_animation


def rs_field_window(pret, at):
    """RS uses code coordinates, not Emerald's eight-byte BG windows."""
    message_source=(pret/'src/field_message_box.c').read_text()
    frame_source=(pret/'src/text_window.c').read_text()
    printers=re.findall(r'Contest_StartTextPrinter\s*\(\s*&gFieldMessageBoxWindow\s*,\s*gStringVar4\s*,\s*gMenuTextTileOffset\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',message_source)
    assert len(printers)==2 and len(set(printers))==1,'Field printer coordinates changed'
    left,top=map(int,printers[0])
    dimensions={}
    for key in ('LEFT','TOP','WIDTH','HEIGHT'):
        found=re.findall(r'^#define\s+STD_DLG_FRAME_'+key+r'\s+(\d+)\s*$',frame_source,re.M)
        assert len(found)==1,(key,found)
        dimensions[key.lower()]=int(found[0])
    assert (left,top)==(2,15) and dimensions==dict(left=0,top=14,width=26,height=4)
    assert 'DrawDialogueFrame(win, STD_DLG_FRAME_LEFT, STD_DLG_FRAME_TOP, STD_DLG_FRAME_WIDTH, STD_DLG_FRAME_HEIGHT);'in frame_source
    sites={name:at(name)for name in ('PrintFieldMessage','PrintFieldMessageFromStringVar4','TextWindow_DrawDialogueFrame','gMenuTextWindowTemplate')}
    return dict(kind='rs-field-code',left=left,top=top,width=dimensions['width'],height=dimensions['height'],
        source='ROM:PrintFieldMessage %07X / PrintFieldMessageFromStringVar4 %07X; matching RS field printer and dialogue-frame code'%
               (sites['PrintFieldMessage'],sites['PrintFieldMessageFromStringVar4']),
        evidence=dict(symbols=sites,sourceSHA256={
            'src/field_message_box.c':hashlib.sha256(message_source.encode()).hexdigest(),
            'src/text_window.c':hashlib.sha256(frame_source.encode()).hexdigest()},
            frame=dimensions,printerCallCount=len(printers)))


def rs_item_menu(pret, target, at):
    """Verified RS action records and fixed-stride column-major pocket lists."""
    source=(pret/'src/item_menu.c').read_text()
    clean=re.sub(r'//[^\n]*|/\*.*?\*/','',source,flags=re.S)
    enums=re.findall(r'enum\s*\{(.*?)\};',clean,re.S)
    enum=next(e for e in enums if 'ITEM_ACTION_USE_0' in e)
    names=[n.strip() for n in enum.split(',') if n.strip()]
    assert names==['ITEM_ACTION_USE_0','ITEM_ACTION_TOSS','ITEM_ACTION_CANCEL_2','ITEM_ACTION_REGISTER','ITEM_ACTION_USE_4','ITEM_ACTION_CANCEL_5','ITEM_ACTION_GIVE','ITEM_ACTION_CHECK_TAG','ITEM_ACTION_NONE','ITEM_ACTION_CONFIRM']
    ids={n:i for i,n in enumerate(names)}
    pocket_names=['BAG_POCKET_ITEMS','BAG_POCKET_POKE_BALLS','BAG_POCKET_TMs_HMs','BAG_POCKET_BERRIES','BAG_POCKET_KEY_ITEMS']
    enum=next(e for e in enums if 'BAG_POCKET_ITEMS' in e)
    assert [n.strip() for n in enum.split(',') if n.strip()]==pocket_names
    actions=at('sItemPopupMenuActions');choices=at('sItemPopupMenuChoicesTable')
    assert target.by_name['sItemPopupMenuActions'][0]['size']==10*8
    assert target.by_name['sItemPopupMenuChoicesTable'][0]['size']==5*6
    table=re.search(r'sItemPopupMenuActions\[\]\s*=\s*\{(.*?)\};',clean,re.S)
    pairs=re.findall(r'\{\s*(\w+)\s*,\s*(\w+)\s*\}',table[1])
    assert len(pairs)==10
    functions=['HandlePopupMenuAction_UseOnField','HandlePopupMenuAction_Toss','sub_80A5F80','HandlePopupMenuAction_Register','HandlePopupMenuAction_UseInBattle','sub_80A7124','HandlePopupMenuAction_Give','HandlePopupMenuAction_CheckTag','NULL','HandlePopupMenuAction_Confirm']
    assert [fn for _,fn in pairs]==functions
    for i,(text,fn) in enumerate(pairs):
        tp,fp=struct.unpack_from('<II',target.rom,actions+i*8)
        assert tp==0x08000000+at(text),(i,text)
        assert fp==(0 if fn=='NULL' else 0x08000001+at(fn)),(i,fn)
    table=re.search(r'sItemPopupMenuChoicesTable\[\]\[6\]\s*=\s*\{(.*?)\n\};',clean,re.S)
    rows=re.findall(r'\[(\w+)\]\s*=\s*\{(.*?)\}',table[1],re.S)
    assert [name for name,_ in rows]==pocket_names
    pockets={}
    for i,(name,values) in enumerate(rows):
        values=[ids[v.strip()] for v in values.split(',') if v.strip()]
        count=6 if i==3 else 4
        assert len(values)==count and values[-1]==ids['ITEM_ACTION_CANCEL_2']
        raw=target.rom[choices+i*6:choices+(i+1)*6]
        assert raw==bytes(values+[0]*(6-count)),(name,raw)
        pockets[['ITEM','BALL','TM_HM','BERRY','KEY_ITEM'][i]]=dict(row=i,count=count)
    # The actual printers are column-major, with two or three rows per
    # column. The native generic action menu consumes row-major entries.
    assert '1 + (i / 2) * 6, 8 + (i % 2) * 2' in source
    assert '1 + (i / 3) * 6, 6 + (i % 3) * 2' in source
    return dict(actions=actions,actionCount=10,choices=choices,choiceStride=6,pockets=pockets,
        kinds=['use','toss','cancel','register','use','cancel','give','checkTag','blank','other'],
        columns=2,cancel=3,blank=9,register=4,sourceOrder='column-major',
        evidence=dict(sourceSHA256=hashlib.sha256(source.encode()).hexdigest(),recordCount=10,
            actionEnum=names,printerRows=[2,3],pointerPairsVerified=True))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rom',type=Path,required=True)
    p.add_argument('--elf',type=Path,required=True)
    p.add_argument('--pret',type=Path,required=True)
    p.add_argument('--emerald-elf',type=Path,required=True)
    p.add_argument('--emerald-rom',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    pret_commit=subprocess.check_output(['git','-C',str(args.pret),'rev-parse','HEAD'],text=True).strip()
    assert pret_commit=='5784633ce4ef7ade1a7f2d2d0c288e3d5e6cdd7f', 'Use the pinned matching RS source'
    assert not subprocess.check_output(['git','-C',str(args.pret),'status','--porcelain','--untracked-files=no']).strip(), 'Matching source has tracked changes'
    rom=args.rom.read_bytes()
    code=rom[0xac:0xb0].decode()
    edition={'AXVE':'ruby','AXPE':'sapphire'}[code]
    expected={'ruby':'f28b6ffc97847e94a6c21a63cacf633ee5c8df1e','sapphire':'3ccbbd45f8553c36463f13b938e833f652b793e4'}
    assert hashlib.sha1(rom).hexdigest()==expected[edition]
    target=Symbols(args.elf,rom)
    emrom=args.emerald_rom.read_bytes()
    emerald=Symbols(args.emerald_elf,emrom)
    records={}
    def symbol_offset(name):
        rows=target.by_name.get(name,[])
        offsets={r['at'] for r in rows}
        assert len(offsets)==1,(name,rows)
        return offsets.pop()
    def at(name):
        value=symbol_offset(name);records[name]=value;return value
    f=discover.discover(discover.Rom(rom))
    base=json.loads((Path(__file__).parent/'rom_manifest_emerald.json').read_text())
    result={k:copy.deepcopy(base[k]) for k in ('format','generation','romBase','charmap','layout')}
    result.update(version=edition,romSha1=expected[edition],romHeader=dict(title=rom[0xa0:0xac].decode(),gameCode=code,makerCode=rom[0xb0:0xb2].decode(),revision=rom[0xbc]))
    result['symbols']=dict(f.found)
    aliases={'gNatureNamePointers':'gNatureNames','gFontNormalLatinGlyphs':'gFont3LatinGlyphs',
             'gFontNormalLatinGlyphWidths':'sFont3Widths','gFontBrailleLatinGlyphs':'sBrailleGlyphs',
             'sElevationToSubspriteTable':'sElevationToSubspriteTableNum','sStarterMon':'sStarterMons',
             'sWindowFrames':'sTextWindowFrameGraphics'}
    for name in base['symbols']:
        target_name=aliases.get(name,name)
        if name not in result['symbols'] and target_name in target.by_name:
            result['symbols'][name]=at(target_name)
    result['symbols']['gScriptCmdTable']=at('gScriptCmdTable')
    result['symbols']['gStdScripts']=at('gStdScripts')
    # RS retains two description pointers: 387 entries, 36 bytes each.
    # The matching ELF and raw Bulbasaur dimensions independently check it.
    dex=at('gPokedexEntries')
    assert target.by_name['gPokedexEntries'][0]['size']==387*36
    assert struct.unpack_from('<HH',rom,dex+36+12)==(7,69)
    result['pokedexEntrySize']=36
    # RS has 163 item-effect pointers, indexed from ITEM_POTION (13).
    # Emerald's table/address and its three extra berry rows are unrelated.
    effects=at('gItemEffectTable')
    effect_rows=target.by_name['gItemEffectTable']
    assert len(effect_rows)==1 and effect_rows[0]['size']==163*4
    effect_source=(args.pret/'src/data/pokemon/item_effects.h').read_text()
    effect_table=re.search(r'gItemEffectTable\[\]\s*=\s*\{(.*?)\};',effect_source,re.S)
    assert effect_table
    effect_names=[name.strip() for name in effect_table[1].split(',') if name.strip()]
    assert len(effect_names)==163
    for index,name in enumerate(effect_names):
        pointer=struct.unpack_from('<I',rom,effects+index*4)[0]
        assert pointer==(0 if name=='NULL' else 0x08000000+at(name)),(index,name)
    result['stageOverrides']={'ITEM_EFFECTS':dict(TABLE=effects,FIRST=13,COUNT=163)}
    result['stageOverrides']['BALL_ANIM'],result['rsBallAnimationEvidence']=rs_ball_animation(args.pret,target,at)
    for name in ('scenes','sceneRoles','sceneOverlays','screenText','bagSprite','wallClock','introCast','introShots','messageWindow','specials','starters','playerTitles','movementActions','playerSprites','m4aWidths','introSprites'):
        result[name]=copy.deepcopy(getattr(f,name,None))
    # Field text is printed at (2,15) in the matching RS code. Its older
    # WindowTemplate is not an Emerald/FRLG battle-window scan anchor.
    result['rsFieldMessageWindow']=rs_field_window(args.pret,at)
    result['rsItemMenu']=rs_item_menu(args.pret,target,at)
    result['metatileBehaviorFlags']=source_metadata(edition,rom,(args.pret/'src/metatile_behavior.c').read_bytes(),symbol_offset('sTileBitAttributes'))
    # Speech contents are recovered from the cartridge by the native importer.
    for row in ((result.get('introSprites') or {}).get('birch') or {}).get('speech',[]):
        row.pop('text',None)
    layout=result['layout']
    layout.update(f.counts)
    layout.update(numSongs=f.counts['songCount'],numItems=349,numTrainers=694,
                  flagBytes=288,windowFrameCount=20,numSpecialVars=20,scriptCmdCount=198)
    # Both retail RS builds use the same 4bpp shadowed font contract.
    glyphs,widths=at('gFont3LatinGlyphs'),at('sFont3Widths')
    count=target.by_name['sFont3Widths'][0]['size']
    assert count==254 and all(0<z<=8 for z in rom[widths:widths+count])
    result['font']=dict(bits=4,glyphBytes=64,cell=16,cellWidth=8,cellHeight=16,
                        count=count,inkTop=0,inkBottom=15,inkRight=7,
                        glyphs=glyphs,widths=widths,role='normal',fontId=3,
                        roles={'none':0,'text':15,'shadow':14})
    result['font']['faces']=[dict(role='small',fontId=4,bits=4,glyphBytes=32,
        cellWidth=8,cellHeight=8,glyphs=at('gFont4LatinGlyphs'),widths=at('sFont4Widths'),
        glyphMap=at('sFontType1Map'),glyphMapStride=2,glyphMapOffset=1)]
    result['trainerBack']=dict(table=at('gTrainerBackPicTable'),palettes=at('gTrainerBackPicPaletteTable'),count=3,compressed=True)
    # StringBraille emits c and c+0x40. Each half uses two tiles selected
    # by sFontType3Map; the field's proportional 1bpp blitter is MSB-first.
    # ScrCmd_braillemessage consumes all six format bytes in RS, unlike EM.
    assert target.by_name['sBrailleGlyphs'][0]['size']==1536
    assert target.by_name['sFontType3Map'][0]['size']==256
    result['braille']=dict(bits=1,glyphMap=at('sFontType3Map'),halfCodeOffset=64,
        frameFromHeader=True,lineHeight=32)
    coords=at('sMauvilleGymSwitchCoords')
    events=json.loads((args.pret/'data/maps/MauvilleCity_Gym/map.json').read_text())['coord_events']
    count=len(events)
    assert target.by_name['sMauvilleGymSwitchCoords'][0]['size']==count*4
    assert all(rom[coords+i*4+2:coords+i*4+4]==b'\0\0' for i in range(count))
    switches=[[rom[coords+i*4]-7,rom[coords+i*4+1]-7] for i in range(count)]
    assert count==3 and switches==[[e['x'],e['y']] for e in events]
    result['mauvilleGym']=dict(SWITCHES=switches,X0=0,X1=8,Y0=5,Y1=16,
        RAISED_SWITCH=0x205,PRESSED_SWITCH=0x206,FLOOR=0x21A,
        GREEN_V1=0x240,GREEN_V2=0x248,RED_V2=0x249)
    # The existing native beam recipes and Norman door frames are shared;
    # the switch positions are not. Check their actual metatile identities.
    labels=(args.pret/'include/constants/metatile_labels.h').read_text()
    for name,value in dict(RaisedSwitch=0x205,PressedSwitch=0x206,FloorTile=0x21A,
        GreenBeamV1_On=0x240,GreenBeamV2_On=0x248,RedBeamV2_On=0x249).items():
        match=re.search(r'#define METATILE_MauvilleGym_'+name+r'\s+(0x[0-9A-Fa-f]+)',labels)
        assert match and int(match[1],16)==value,name
    frames=at('gPetalburgGymSlidingDoorMetatiles')
    assert struct.unpack_from('<5H',rom,frames)==tuple(range(0x218,0x21D))
    delays=at('gUnknown_083F8370')
    assert rom[delays:delays+5]==bytes([0,1,1,1,1])
    result['pocketEnum']={'1':'ITEM','2':'BALL','3':'TM_HM','4':'BERRY','5':'KEY_ITEM'}
    result['typeIds']=['NORMAL','FIGHTING','FLYING','POISON','GROUND','ROCK','BUG','GHOST','STEEL','TYPE_09','FIRE','WATER','GRASS','ELECTRIC','PSYCHIC','ICE','DRAGON','DARK']
    # RS stores direct RAM save blocks and has no bag/money encryption key.
    # Its ROM table is {RAM pointer,u16 size,padding}, not Emerald's
    # {u16 block offset,u16 size}; decode the actual fourteen records.
    chunks=at('sSaveBlockChunks')
    sectors=[]
    bases={}
    for i in range(14):
        ptr,size,padding=struct.unpack_from('<IHH',rom,chunks+i*8)
        group=0 if i==0 else (1 if i<5 else 2)
        bases.setdefault(group,ptr)
        offset=ptr-bases[group]
        assert 0<size<=3968 and padding==0
        expected_offset=0 if group==0 else (i-(1 if group==1 else 5))*3968
        assert offset==expected_offset
        sectors.append(dict(offset=offset,size=size))
    sizes=[sum(r['size'] for r in sectors[a:b]) for a,b in ((0,1),(1,5),(5,14))]
    result['save']=dict(chunkStride=3968,sectorSize=4096,sectorsPerSlot=14,sectors=sectors,
                        saveBlock2Size=sizes[0],saveBlock1Size=sizes[1],pokemonStorageSize=sizes[2],security=0x08012025)
    source=(args.pret/'src/pokemon_2.c').read_text()
    cases=re.findall(r'SUBSTRUCT_CASE\(\s*(\d+)\s*,\s*(\d)\s*,\s*(\d)\s*,\s*(\d)\s*,\s*(\d)\s*\)',source)
    assert len(cases)==24 and [int(z[0]) for z in cases]==list(range(24))
    orders=[[int(z) for z in row[1:]] for row in cases]
    assert all(sorted(z)==[0,1,2,3] for z in orders)
    result['substructOrders']=orders
    header=(args.pret/'include/global.h').read_text()
    def offsets(block,names):
        text=header.split('struct '+block,1)[1].split('\n};',1)[0]
        out={}
        for name in names:
            match=re.search(r'/\*0x([0-9A-Fa-f]+)\*/[^\n]*\b'+name+r'\b',text)
            assert match,(block,name)
            out[name]=int(match[1],16)
        return out
    b1=offsets('SaveBlock1',['location','money','coins','registeredItem','flags','vars','gameStats','pcItems','playerParty','playerPartyCount','bagPocket_Items','bagPocket_KeyItems','bagPocket_PokeBalls','bagPocket_TMHM','bagPocket_Berries'])
    b2=offsets('SaveBlock2',['playerName','playerGender','playerTrainerId','playTimeHours','playTimeMinutes','playTimeSeconds','playTimeVBlanks'])
    b1.update(posX=0,posY=2);b2['encryptionKey']=False
    pockets=[b1.pop(n) for n in ('bagPocket_Items','bagPocket_KeyItems','bagPocket_PokeBalls','bagPocket_TMHM','bagPocket_Berries')]
    capacities=[(pockets[i+1]-pockets[i])//4 for i in range(4)]+[46]
    assert capacities==[20,20,16,64,46]
    result['saveFields']=dict(saveBlock1=b1,saveBlock2=b2,flagBytes=288,varCount=256,varsStartId=0x4000,
        party=dict(count=b1['playerPartyCount'],start=b1['playerParty'],size=6,monSize=100),
        bag=dict(capacities=capacities,pockets=pockets,itemSlotSize=4,pcItems=b1['pcItems'],pcItemCount=50),
        storage=dict(currentBox=0,boxes=4,boxCount=14,boxCapacity=30,boxMonSize=80,boxNames=33604,boxNameLength=9,boxWallpapers=33730))
    # Resolve specials by native function identity, never by sibling slot.
    # Read the assembler's actual conditional-build ids (the German-only
    # special at the end is absent from the English retail table).
    symbol_lines=subprocess.check_output(['arm-none-eabi-nm','-P','--defined-only',str(args.elf)],text=True)
    special_ids={}
    for line in symbol_lines.splitlines():
        fields=line.split()
        if len(fields)>=3 and fields[0].startswith('SPECIAL_') and fields[1].upper()=='A':
            special_ids[int(fields[2],16)]=fields[0][8:]
    assert set(special_ids)==set(range(len(special_ids)))
    specials=[special_ids[i] for i in range(len(special_ids))]
    special_at=at('gSpecials')
    result['specials']=dict(at=special_at,count=len(specials))
    layout['numSpecials']=len(specials)
    em_specials=base['specials']
    em_names={}
    for i in range(em_specials['count']):
        address=struct.unpack_from('<I',emrom,em_specials['at']+i*4)[0]-0x08000001
        for row in emerald.by_address.get(address,[]):em_names.setdefault(row['name'],i)
    names={'ScrSpecial_HealPlayerParty':'HealPlayerParty','Overworld_SetWarpDestination':'SetWarpDestination',
        'MauvilleGymSpecial1':'MauvilleGymPressSwitch',
        'MauvilleGymSpecial2':'MauvilleGymSetDefaultBarriers',
        'MauvilleGymSpecial3':'MauvilleGymDeactivatePuzzle',
        'PetalburgGymSlideOpenDoors':'PetalburgGymSlideOpenRoomDoors',
        'PetalburgGymOpenDoorsInstantly':'PetalburgGymUnlockRoomDoors'}
    def canonical_special(name):
        root=name.removeprefix('ScrSpecial_')
        candidates={em_names[n] for n in (names.get(name,name),root,'Special_'+root,'Script_'+root) if n in em_names}
        assert len(candidates)<=1,(name,candidates)
        return next(iter(candidates),-1)
    result['specialRemap']=[canonical_special(n) for n in specials]
    result['specialIndexMap']={}
    for native,canonical in enumerate(result['specialRemap']):
        if canonical<0:continue
        key=str(canonical)
        if key in result['specialIndexMap']:
            previous=result['specialIndexMap'][key]
            assert at(specials[native])==at(specials[previous]),(canonical,native,previous)
        else:result['specialIndexMap'][key]=native
    for i,n in enumerate(specials):
        assert (struct.unpack_from('<I',rom,special_at+i*4)[0]&~1)-0x08000000==at(n)
    # WarpToTruck's map is also declared in the source's canonical map group
    # list. Confirm the truck layout and dimensions from its actual ROM header.
    groups=json.loads((args.pret/'data/maps/map_groups.json').read_text())
    spawn=None
    for group,label in enumerate(groups['group_order']):
        for number,name in enumerate(groups[label]):
            if name=='InsideOfTruck':
                group_ptr=struct.unpack_from('<I',rom,at('gMapGroups')+group*4)[0]-0x08000000
                header=struct.unpack_from('<I',rom,group_ptr+number*4)[0]-0x08000000
                map_layout=struct.unpack_from('<I',rom,header)[0]-0x08000000
                w,h=struct.unpack_from('<II',rom,map_layout)
                spawn=dict(group=group,number=number,x=w//2,y=h//2,width=w,height=h)
    assert spawn and spawn['width']==5 and spawn['height']==5
    reset=at('EventScript_ResetAllMapFlags')
    hide=[]
    while rom[reset]==0x29:
        hide.append(struct.unpack_from('<H',rom,reset+1)[0]);reset+=3
    assert len(hide)>50 and rom[reset]==4
    assert struct.unpack_from('<I',rom,reset+1)[0]-0x08000000==at('EventScript_ResetAllBerryTrees')
    assert rom[reset+5]==2
    result['newGame']=dict(spawn=spawn,hideFlags=hide)
    result['symbolSource']='Structural discovery plus matching pret ELF symbols, allocated ROM sections byte-verified against supplied cartridge; tools/gen3_rs_manifest.py'
    result['provenance']=dict(pretCommit=pret_commit,elfSHA256=hashlib.sha256(args.elf.read_bytes()).hexdigest(),verifiedROMBytes=target.checked_bytes,
                              symbolIdentities=records,structuralWarnings=f.fail)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('VERIFIED_RS_MANIFEST',edition,len(result['symbols']),'symbols',len(specials),'specials')


if __name__=='__main__':main()
