import types

type Mapper4* = ref object of Mapper
  cartridge: Cartridge
  nes: NES
  register, prgMode, chrMode, reload, counter: uint8
  registers: array[0'u8..7'u8, uint8]
  prgOffsets: array[0'u8..3'u8, int]
  chrOffsets: array[0'u8..7'u8, int]
  irqEnable: bool

proc prgBankOffset(m: Mapper4, index: int): int =
  var index = if index >= 0x80: index - 0x100 else: index
  index = index mod (m.cartridge.prg.len div 0x2000)
  result = index * 0x2000
  if result < 0:
    result += m.cartridge.prg.len

proc chrBankOffset(m: Mapper4, index: int): int =
  var index = if index >= 0x80: index - 0x100 else: index
  index = index mod (m.cartridge.chr.len div 0x0400)
  result = index * 0x0400
  if result < 0:
    result += m.cartridge.chr.len

proc updateOffsets(m: Mapper4) =
  case m.prgMode
  of 0:
    m.prgOffsets[0] = m.prgBankOffset(m.registers[6].int)
    m.prgOffsets[1] = m.prgBankOffset(m.registers[7].int)
    m.prgOffsets[2] = m.prgBankOffset(-2)
    m.prgOffsets[3] = m.prgBankOffset(-1)
  of 1:
    m.prgOffsets[0] = m.prgBankOffset(-2)
    m.prgOffsets[1] = m.prgBankOffset(m.registers[7].int)
    m.prgOffsets[2] = m.prgBankOffset(m.registers[6].int)
    m.prgOffsets[3] = m.prgBankOffset(-1)
  else: discard

  case m.chrMode
  of 0:
    m.chrOffsets[0] = m.chrBankOffset(int(m.registers[0] and 0xFE))
    m.chrOffsets[1] = m.chrBankOffset(int(m.registers[0] or 0x01))
    m.chrOffsets[2] = m.chrBankOffset(int(m.registers[1] and 0xFE))
    m.chrOffsets[3] = m.chrBankOffset(int(m.registers[1] or 0x01))
    m.chrOffsets[4] = m.chrBankOffset(m.registers[2].int)
    m.chrOffsets[5] = m.chrBankOffset(m.registers[3].int)
    m.chrOffsets[6] = m.chrBankOffset(m.registers[4].int)
    m.chrOffsets[7] = m.chrBankOffset(m.registers[5].int)
  of 1:
    m.chrOffsets[0] = m.chrBankOffset(m.registers[2].int)
    m.chrOffsets[1] = m.chrBankOffset(m.registers[3].int)
    m.chrOffsets[2] = m.chrBankOffset(m.registers[4].int)
    m.chrOffsets[3] = m.chrBankOffset(m.registers[5].int)
    m.chrOffsets[4] = m.chrBankOffset(int(m.registers[0] and 0xFE))
    m.chrOffsets[5] = m.chrBankOffset(int(m.registers[0] or 0x01))
    m.chrOffsets[6] = m.chrBankOffset(int(m.registers[1] and 0xFE))
    m.chrOffsets[7] = m.chrBankOffset(int(m.registers[1] or 0x01))
  else: discard

proc writeBankSelect(m: Mapper4, val: uint8) =
  m.prgMode = (val shr 6) and 1
  m.chrMode = (val shr 7) and 1
  m.register = val and 7

proc writeMirror(m: Mapper4, val: uint8) =
  m.cartridge.mirror = uint8(case val and 1
  of 0: mirrorVertical
  of 1: mirrorHorizontal)

proc writeRegister(m: Mapper4, adr: uint16, val: uint8) =
  case adr
  of 0x0000..0x9FFF:
    if adr mod 2 == 0: m.writeBankSelect(val)
    else:              m.registers[m.register] = val
    m.updateOffsets()
  of 0xA000..0xBFFF:
    if adr mod 2 == 0: m.writeMirror(val)
    else:              discard # write protect
  of 0xC000..0xDFFF:
    if adr mod 2 == 0: m.reload = val
    else:              m.counter = 0
  of 0xE000..0xFFFF:
    if adr mod 2 == 0: m.irqEnable = false
    else:              m.irqEnable = true

proc newMapper4*(cartridge: Cartridge, nes: NES): Mapper4 =
  new result
  result.cartridge = cartridge
  result.nes = nes
  result.prgOffsets[0] = result.prgBankOffset(0)
  result.prgOffsets[1] = result.prgBankOffset(1)
  result.prgOffsets[2] = result.prgBankOffset(-2)
  result.prgOffsets[3] = result.prgBankOffset(-1)

method step*(m: Mapper4) =
  let ppu = m.nes.ppu

  if ppu.cycle != 300:
    return
  if ppu.scanLine in 240..260:
    return
  if not ppu.flagShowBackground and not ppu.flagShowSprites:
    return

  if m.counter == 0:
    m.counter = m.reload
  else:
    dec m.counter
    if m.counter == 0 and m.irqEnable:
      m.nes.cpu.triggerIRQ()

method `[]`*(m: Mapper4, adr: uint16): uint8 =
  case adr
  of 0x0000..0x1FFF:
    let bank = adr div 0x0400
    let offset = adr mod 0x0400
    result = m.cartridge.chr[m.chrOffsets[bank]+offset.int]
  of 0x6000..0x7FFF: result = m.cartridge.sram[adr.int - 0x6000]
  of 0x8000..0xFFFF:
    let adr = adr - 0x8000
    let bank = adr div 0x2000
    let offset = adr mod 0x2000
    result = m.cartridge.prg[m.prgOffsets[bank]+offset.int]
  else: raise newException(ValueError, "unhandled mapper4 read at: " & $adr)

method `[]=`*(m: Mapper4, adr: uint16, val: uint8) =
  case adr
  of 0x0000..0x1FFF:
    let bank = adr div 0x0400
    let offset = adr mod 0x0400
    m.cartridge.chr[m.chrOffsets[bank]+offset.int] = val
  of 0x6000..0x7FFF: m.cartridge.sram[adr.int - 0x6000] = val
  of 0x8000..0xFFFF: m.writeRegister(adr, val)
  else: raise newException(ValueError, "unhandled mapper4 write at: " & $adr)
