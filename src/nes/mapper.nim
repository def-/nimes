import types, mapper1, mapper2, mapper3, mapper4, mapper7

proc newMapper*(nes: NES): Mapper =
  echo "Using mapper ", nes.cartridge.mapper
  result = case nes.cartridge.mapper
  of 0, 2: newMapper2(nes.cartridge)
  of 1: newMapper1(nes.cartridge)
  of 3: newMapper3(nes.cartridge)
  of 4: newMapper4(nes.cartridge, nes)
  of 7: newMapper7(nes.cartridge)
  else: raise newException(ValueError, "unknown mapper " & $nes.cartridge.mapper)

template step*(m: Mapper) = 
  m.step(m)

template `[]`*(m: Mapper, adr: uint16): uint8 = 
  m.idx(m, adr)

template `[]=`*(m: Mapper, adr: uint16, val: uint8) = 
  m.idxSet(m, adr, val)