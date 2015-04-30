import unsigned, types

type Mapper7* = ref object of Mapper
  cartridge: Cartridge
  prgBank: int

proc newMapper7*(cartridge: Cartridge): Mapper7 =
  new result
  result.cartridge = cartridge
  result.prgBank = 0

method step*(m: Mapper7) =
  discard

method `[]`*(m: Mapper7, adr: uint16): uint8 =
  case adr
  of 0x0000..0x1FFF: result = m.cartridge.chr[adr.int]
  of 0x6000..0x7FFF: result = m.cartridge.sram[adr.int - 0x6000]
  of 0x8000..0xFFFF: result = m.cartridge.prg[m.prgBank*0x8000 + int(adr - 0x8000)]
  else: raise newException(ValueError, "unhandled mapper7 read at: " & $adr)

method `[]=`*(m: Mapper7, adr: uint16, val: uint8) =
  case adr
  of 0x0000..0x1FFF: m.cartridge.chr[adr.int] = val
  of 0x6000..0x7FFF: m.cartridge.sram[adr.int - 0x6000] = val
  of 0x8000..0xFFFF:
    m.prgBank = int(val and 7)
    case val and 0x10
    of 0x00: m.cartridge.mirror = mirrorSingle0.uint8
    of 0x10: m.cartridge.mirror = mirrorSingle1.uint8
    else: discard
  else: raise newException(ValueError, "unhandled mapper7 write at: " & $adr)
