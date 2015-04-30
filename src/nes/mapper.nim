import types, mapper1, mapper2, mapper3, mapper4, mapper7

export types.Mapper

proc newMapper*(nes: NES): Mapper =
  case nes.cartridge.mapper
  of 0, 2: result = newMapper2(nes.cartridge)
  of 1:    result = newMapper1(nes.cartridge)
  of 3:    result = newMapper3(nes.cartridge)
  of 4:    result = newMapper4(nes.cartridge, nes)
  of 7:    result = newMapper7(nes.cartridge)
  else: raise newException(ValueError, "unknown mapper " & $nes.cartridge.mapper)
