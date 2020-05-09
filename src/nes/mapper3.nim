import types

type Mapper3* = ref object of Mapper
  cartridge: Cartridge
  chrBank, prgBank1, prgBank2: int

proc newMapper3*(cartridge: Cartridge): Mapper3 =
  new result
  result.cartridge = cartridge
  let prgBanks = cartridge.prg.len div 0x4000
  result.chrBank = 0
  result.prgBank1 = 0
  result.prgBank2 = prgBanks - 1

method step*(m: Mapper3) =
  discard

method `[]`*(m: Mapper3, adr: uint16): uint8 =
  case adr
  of 0x0000..0x1FFF: result = m.cartridge.chr[adr.int]
  of 0x6000..0x7FFF: result = m.cartridge.sram[adr.int - 0x6000]
  of 0x8000..0xBFFF: result = m.cartridge.prg[m.prgBank1*0x4000 + int(adr - 0x8000)]
  of 0xC000..0xFFFF: result = m.cartridge.prg[m.prgBank2*0x4000 + int(adr - 0xC000)]
  else: raise newException(ValueError, "unhandled mapper3 read at: " & $adr)

method `[]=`*(m: Mapper3, adr: uint16, val: uint8) =
  case adr
  of 0x0000..0x1FFF: m.cartridge.chr[m.chrBank*0x2000 + adr.int] = val
  of 0x6000..0x7FFF: m.cartridge.sram[adr.int - 0x6000] = val
  of 0x8000..0xFFFF: m.prgBank1 = val.int and 3
  else: raise newException(ValueError, "unhandled mapper3 write at: " & $adr)
