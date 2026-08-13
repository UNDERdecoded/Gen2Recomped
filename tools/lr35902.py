"""Minimal LR35902 disassembler - enough to read data-loading routines."""
R  = ["b","c","d","e","h","l","[hl]","a"]
RP = ["bc","de","hl","sp"]
RP2= ["bc","de","hl","af"]
CC = ["nz","z","nc","c"]
ALU= ["add a,","adc a,","sub ","sbc a,","and ","xor ","or ","cp "]
ROT= ["rlc","rrc","rl","rr","sla","sra","swap","srl"]

def _u8(d,i): return d[i]
def _u16(d,i): return d[i] | (d[i+1]<<8)

def decode(data, pc, base):
    """Returns (text, length, operand_word_or_None)."""
    op = data[pc]
    def w(): return _u16(data, pc+1)
    def b(): return data[pc+1]
    if op == 0x00: return "nop",1,None
    if op == 0x76: return "halt",1,None
    if op == 0xCB:
        cb = data[pc+1]; r = R[cb&7]; y=(cb>>3)&7
        if cb < 0x40: return f"{ROT[y]} {r}",2,None
        if cb < 0x80: return f"bit {y},{r}",2,None
        if cb < 0xC0: return f"res {y},{r}",2,None
        return f"set {y},{r}",2,None
    if op & 0xCF == 0x01: return f"ld {RP[op>>4]},${w():04x}",3,w()
    if op & 0xCF == 0x09: return f"add hl,{RP[op>>4]}",1,None
    if op in (0x02,0x12): return f"ld [{RP[op>>4]}],a",1,None
    if op in (0x0A,0x1A): return f"ld a,[{RP[op>>4]}]",1,None
    if op == 0x22: return "ld [hl+],a",1,None
    if op == 0x32: return "ld [hl-],a",1,None
    if op == 0x2A: return "ld a,[hl+]",1,None
    if op == 0x3A: return "ld a,[hl-]",1,None
    if op & 0xCF == 0x03: return f"inc {RP[op>>4]}",1,None
    if op & 0xCF == 0x0B: return f"dec {RP[op>>4]}",1,None
    if op & 0xC7 == 0x04: return f"inc {R[op>>3]}",1,None
    if op & 0xC7 == 0x05: return f"dec {R[op>>3]}",1,None
    if op & 0xC7 == 0x06: return f"ld {R[op>>3]},${b():02x}",2,b()
    if op == 0x07: return "rlca",1,None
    if op == 0x0F: return "rrca",1,None
    if op == 0x17: return "rla",1,None
    if op == 0x1F: return "rra",1,None
    if op == 0x27: return "daa",1,None
    if op == 0x2F: return "cpl",1,None
    if op == 0x37: return "scf",1,None
    if op == 0x3F: return "ccf",1,None
    if op == 0x08: return f"ld [${w():04x}],sp",3,w()
    if op == 0x10: return "stop",2,None
    if op == 0x18:
        off = data[pc+1]; off = off-256 if off>127 else off
        return f"jr ${base+pc+2+off:04x}",2,base+pc+2+off
    if op & 0xE7 == 0x20:
        off = data[pc+1]; off = off-256 if off>127 else off
        return f"jr {CC[(op>>3)&3]},${base+pc+2+off:04x}",2,base+pc+2+off
    if 0x40 <= op < 0x80: return f"ld {R[(op>>3)&7]},{R[op&7]}",1,None
    if 0x80 <= op < 0xC0: return f"{ALU[(op>>3)&7]}{R[op&7]}",1,None
    if op & 0xCF == 0xC1: return f"pop {RP2[(op>>4)&3]}",1,None
    if op & 0xCF == 0xC5: return f"push {RP2[(op>>4)&3]}",1,None
    if op & 0xC7 == 0xC7: return f"rst ${op&0x38:02x}",1,None
    if op & 0xE7 == 0xC0: return f"ret {CC[(op>>3)&3]}",1,None
    if op == 0xC9: return "ret",1,None
    if op == 0xD9: return "reti",1,None
    if op & 0xE7 == 0xC2: return f"jp {CC[(op>>3)&3]},${w():04x}",3,w()
    if op == 0xC3: return f"jp ${w():04x}",3,w()
    if op & 0xE7 == 0xC4: return f"call {CC[(op>>3)&3]},${w():04x}",3,w()
    if op == 0xCD: return f"call ${w():04x}",3,w()
    if op & 0xC7 == 0xC6: return f"{ALU[(op>>3)&7]}${b():02x}",2,b()
    if op == 0xE0: return f"ldh [$ff{b():02x}],a",2,0xFF00|b()
    if op == 0xF0: return f"ldh a,[$ff{b():02x}]",2,0xFF00|b()
    if op == 0xE2: return "ldh [c],a",1,None
    if op == 0xF2: return "ldh a,[c]",1,None
    if op == 0xEA: return f"ld [${w():04x}],a",3,w()
    if op == 0xFA: return f"ld a,[${w():04x}]",3,w()
    if op == 0xE8: 
        o=data[pc+1]; o=o-256 if o>127 else o
        return f"add sp,{o}",2,None
    if op == 0xF8:
        o=data[pc+1]; o=o-256 if o>127 else o
        return f"ld hl,sp{o:+d}",2,None
    if op == 0xE9: return "jp hl",1,None
    if op == 0xF9: return "ld sp,hl",1,None
    if op == 0xF3: return "di",1,None
    if op == 0xFB: return "ei",1,None
    return f"db ${op:02x}",1,None

def disasm(rom, sym, bank, start, end, label=""):
    data = rom.bytes(bank, start, end-start)
    out=[]; pc=0
    while pc < len(data):
        addr = start+pc
        names = sym.names_at(bank, addr)
        if names and pc: out.append(f"{names[0]}:")
        try: text,ln,operand = decode(data, pc, start)
        except IndexError: break
        ann=""
        if operand is not None and 0x4000 <= operand < 0x8000:
            for b2 in (bank,):
                n = sym.names_at(b2, operand)
                if n: ann = "   ; " + n[0]; break
        raw=" ".join(f"{x:02x}" for x in data[pc:pc+ln])
        out.append(f"  {bank:02x}:{addr:04x}  {raw:<9} {text}{ann}")
        pc += ln
    return "\n".join(out)
