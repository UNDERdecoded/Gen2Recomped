"""RS ball art and send-out sites from a cartridge-verified matching ELF."""
import hashlib,re,struct
from gen3_discover import Rom,lz77_at


def rs_ball_animation(pret,target,at):
    rom=target.rom;reader=Rom(rom)
    source=(pret/'src/pokeball.c').read_text();particles=(pret/'src/battle_anim_special.c').read_text()
    songs=(pret/'include/constants/songs.h').read_text()
    required=['gSprites[spriteId].x = 24;','gSprites[spriteId].y = 68;',
      'sprite->data[0] = 25;','sprite->data[4] = GetBattlerSpriteCoord(sprite->data[6], 3) + 24;',
      'sprite->data[5] = -30;','sprite->data[0] > 15','gSprites[gBattlerSpriteIds[r4]].data[1] -= 288;',
      'sub_8141314(1, sprite->data[6], 14, ballIndex)','LZDecompressVram(gUnknown_08D030D0,']
    assert all(token in source for token in required),'RS send-out source contract changed'
    assert 'case 6:\n    case 10:\n    case 11:'in source
    fields={key:at(name)for key,name in dict(SHEETS='sBallSpriteSheets',PALETTES='sBallSpritePalettes',
      OPEN_FRAME='gUnknown_08D030D0',COLOURS='gUnknown_0840B4D4',PARTICLES='gBattleAnimSpriteSheet_Particles',
      PARTICLE_PALETTE='gBattleAnimSpritePalette_136',PARTICLE_ANIM='gBallOpenParticleAnimNums').items()}
    assert target.by_name['sBallSpriteSheets'][0]['size']==96 and target.by_name['sBallSpritePalettes'][0]['size']==96
    for i in range(12):
        gfx,size,tag=struct.unpack_from('<IHH',rom,fields['SHEETS']+i*8)
        pal,ptag=struct.unpack_from('<IH',rom,fields['PALETTES']+i*8)
        assert size==384 and tag==ptag==55000+i
        assert len(lz77_at(reader,gfx-0x08000000))==384 and len(lz77_at(reader,pal-0x08000000))==32
    assert len(lz77_at(reader,fields['OPEN_FRAME']))==128
    assert len(lz77_at(reader,fields['PARTICLES']))==256
    assert len(lz77_at(reader,fields['PARTICLE_PALETTE']))==32
    assert list(rom[fields['PARTICLE_ANIM']:fields['PARTICLE_ANIM']+12])==[0,0,0,5,1,2,2,3,5,5,4,4]
    sites={};proof={}
    def find(name,predicate):
        rows=target.by_name[name];assert len(rows)==1 and rows[0]['type']==2
        row=rows[0];start=at(name);end=start+row['size'];found=[]
        proof[name]=dict(address=start,size=row['size'],sha256=hashlib.sha256(rom[start:end]).hexdigest())
        for pos in range(start,end,2):
            hw=struct.unpack_from('<H',rom,pos)[0]
            if predicate(pos,hw):found.append(pos)
        assert len(found)==1,(name,found)
        return found[0]
    def immediate(name,value):return find(name,lambda p,h:h==value)
    def literal(name,value):
        def matches(pos,hw):
            if not 0x4800<=hw<=0x4fff:return False
            pool=((pos+4)&~3)+(hw&255)*4
            return struct.unpack_from('<I',rom,pool)[0]==value
        return find(name,matches)
    sites.update(AT_HAND_X=immediate('SendOutMonAnimation',0x2018),AT_HAND_Y=immediate('SendOutMonAnimation',0x2044),
      AT_FRAMES=immediate('SendOutPlayerMonAnimation_Step0',0x2019),AT_TARGET_DY=immediate('SendOutPlayerMonAnimation_Step0',0x3018),
      AT_ARC=literal('SendOutPlayerMonAnimation_Step0',0xffe2),AT_FOE_DY=immediate('SendOutMonAnimation',0x3018),
      AT_FOE_WAIT=immediate('SendOutOpponentMonAnimation_Step0',0x280f),AT_FADE=immediate('sub_8046C78',0x220e),
      AT_RISE=literal('sub_8046E9C',0xfffffee0),MOV_R0=0x2000,MOV_R2=0x2200,ADD_R0=0x3000,CMP_R0=0x2800)
    fields['SEND']=sites
    def song(name):
        values=re.findall(r'^#define\s+'+name+r'\s+(\d+)\b',songs,re.M);assert len(values)==1;return int(values[0])
    # RS's caught callback has no sound at tick40 and uses MUS_EVOLVED at95.
    assert 'sprite->data[4] == 40' in source and 'PlaySE(MUS_EVOLVED);'in source
    fields['SOUNDS']=dict(throw=song('SE_BALL_THROW'),open=song('SE_BALL_OPEN'),absorb=song('SE_BALL_TRADE'),shake=song('SE_BALL'),caught=song('MUS_EVOLVED'))
    fields['SOURCE']='ROM:matching RS sBallSpriteSheets %07X, palettes %07X, shared open %07X, colors %07X, particles %07X; verified RS Thumb send-out and release sites'%(fields['SHEETS'],fields['PALETTES'],fields['OPEN_FRAME'],fields['COLOURS'],fields['PARTICLES'])
    evidence=dict(functions=proof,sources={n:hashlib.sha256((pret/n).read_bytes()).hexdigest()for n in ['src/pokeball.c','src/battle_anim_special.c','include/constants/songs.h']},sheetsVerified=12,particleFrames=8,sharedOpenBytes=128,sendOutSitesVerified=9)
    return fields,evidence
