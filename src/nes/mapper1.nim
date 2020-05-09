import types

type Mapper1* = ref object of Mapper
  cartridge: Cartridge
  shiftRegister, control, prgMode, chrMode, prgBank, chrBank0, chrBank1: uint8
  prgOffsets, chrOffsets: array[0..1, int]

proc prgBankOffset(m: Mapper1, index: int): int =
  var index = if index >= 0x80: index - 0x100 else: index
  index = index mod (m.cartridge.prg.len div 0x4000)
  result = index * 0x4000
  if result < 0:
    result += m.cartridge.prg.len

proc chrBankOffset(m: Mapper1, index: int): int =
  var index = if index >= 0x80: index - 0x100 else: index
  index = index mod (m.cartridge.chr.len div 0x1000)
  result = index * 0x1000
  if result < 0:
    result += m.cartridge.chr.len

proc writeControl(m: Mapper1, val: uint8) =
  m.control = val
  m.chrMode = (val shr 4) and 1
  m.prgMode = (val shr 2) and 3

  case val and 3
  of 0: m.cartridge.mirror = mirrorSingle0.uint8
  of 1: m.cartridge.mirror = mirrorSingle1.uint8
  of 2: m.cartridge.mirror = mirrorVertical.uint8
  of 3: m.cartridge.mirror = mirrorHorizontal.uint8
  else: discard

proc updateOffsets(m: Mapper1) =
  case m.prgMode
  of 0, 1:
    m.prgOffsets[0] = m.prgBankOffset(int(m.prgBank and 0xFE))
    m.prgOffsets[1] = m.prgBankOffset(int(m.prgBank or 0x01))
  of 2:
    m.prgOffsets[0] = 0
    m.prgOffsets[1] = m.prgBankOffset(m.prgBank.int)
  of 3:
    m.prgOffsets[0] = m.prgBankOffset(m.prgBank.int)
    m.prgOffsets[1] = m.prgBankOffset(-1)
  else: discard

  case m.chrMode
  of 0:
    m.chrOffsets[0] = m.chrBankOffset(int(m.chrBank0 and 0xFE))
    m.chrOffsets[1] = m.chrBankOffset(int(m.chrBank0 or 0x01))
  of 1:
    m.chrOffsets[0] = m.chrBankOffset(m.chrBank0.int)
    m.chrOffsets[1] = m.chrBankOffset(m.chrBank1.int)
  else: discard

proc writeRegister(m: Mapper1, adr: uint16, val: uint8) =
  case adr
  of 0x0000..0x9FFF: m.writeControl(val)
  of 0xA000..0xBFFF: m.chrBank0 = val
  of 0xC000..0xDFFF: m.chrBank1 = val
  of 0xE000..0xFFFF: m.prgBank = val and 0x0F
  m.updateOffsets()

proc loadRegister(m: Mapper1, adr: uint16, val: uint8) =
  if (val and 0x80) == 0x80:
    m.shiftRegister = 0x10
    m.writeControl(m.control and 0x0C)
    m.updateOffsets()
  else:
    let complete = (m.shiftRegister and 1) == 1
    m.shiftRegister = (m.shiftRegister shr 1) or (uint8(val and 1) shl 4)
    if complete:
      m.writeRegister(adr, m.shiftRegister)
      m.shiftRegister = 0x10

proc step*(m: Mapper) =
  discard

proc idx*(m: Mapper, adr: uint16): uint8 =
  var m = Mapper1(m)
  case adr
  of 0x0000..0x1FFF:
    let bank = adr div 0x1000
    let offset = adr mod 0x1000
    result = m.cartridge.chr[m.chrOffsets[bank]+offset.int]
  of 0x6000..0x7FFF: result = m.cartridge.sram[adr.int - 0x6000]
  of 0x8000..0xFFFF:
    let adr = adr - 0x8000
    let bank = adr div 0x4000
    let offset = adr mod 0x4000
    result = m.cartridge.prg[m.prgOffsets[bank]+offset.int]
  else: raise newException(ValueError, "unhandled mapper1 read at: " & $adr)

proc idxSet*(m: Mapper, adr: uint16, val: uint8) =
  var m = Mapper1(m)
  case adr
  of 0x0000..0x1FFF:
    let bank = adr div 0x1000
    let offset = adr mod 0x1000
    m.cartridge.chr[m.chrOffsets[bank]+offset.int] = val
  of 0x6000..0x7FFF: m.cartridge.sram[adr.int - 0x6000] = val
  of 0x8000..0xFFFF: m.loadRegister(adr, val)
  else: raise newException(ValueError, "unhandled mapper1 write at: " & $adr)

proc newMapper1*(cartridge: Cartridge): Mapper1 =
  new result
  result.cartridge = cartridge
  result.shiftRegister = 0x10
  result.prgOffsets[1] = result.prgBankOffset(-1)
  result.idx = idx
  result.idxSet = idxSet
  result.step = step