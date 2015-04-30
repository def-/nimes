import unsigned, types, controller, mapper, mapper2

export types.CPUMemory, types.PPUMemory

proc newCPUMemory*(nes: NES): CPUMemory =
  CPUMemory(nes: nes)

proc newPPUMemory*(nes: NES): PPUMemory =
  PPUMemory(nes: nes)

proc mirrorAddress(mode: uint8, adr: uint16): uint16 =
  const mirrorLookup: array[5'u8, array[4'u8, uint16]] = [
    [0'u16, 0, 1, 1],
    [0'u16, 1, 0, 1],
    [0'u16, 0, 0, 0],
    [1'u16, 1, 1, 1],
    [0'u16, 1, 2, 3],
  ]

  let
    adr = (adr - 0x2000) mod 0x1000
    table = adr div 0x0400
    offset = adr mod 0x0400

  result = mirrorLookup[mode][table]*0x0400 + 0x2000 + offset

template paletteAdr(adr): expr =
  if (adr >= 16'u16) and ((adr mod 4) == 0): adr - 16 else: adr

proc readPalette*(ppu: PPU, adr: uint16): uint8 =
  result = ppu.paletteData[paletteAdr(adr)]

proc writePalette*(ppu: PPU, adr: uint16, val: uint8) =
  ppu.paletteData[paletteAdr(adr)] = val

proc `[]`*(mem: PPUMemory, adr: uint16): uint8 =
  let adr = adr mod 0x4000
  case adr
  of 0x0000..0x1FFF:
    result = mem.nes.mapper[adr]
  of 0x2000..0x3EFF:
    let mode = mem.nes.cartridge.mirror
    result = mem.nes.ppu.nameTableData[mirrorAddress(mode, adr) mod 2048]
  of 0x3F00..0x3FFF:
    result = mem.nes.ppu.readPalette(adr mod 32)
  else: discard

proc `[]=`*(mem: PPUMemory, adr: uint16, val: uint8) =
  let adr = adr mod 0x4000
  case adr
  of 0x0000..0x1FFF:
    mem.nes.mapper[adr] = val
  of 0x2000..0x3EFF:
    let mode = mem.nes.cartridge.mirror
    mem.nes.ppu.nameTableData[mirrorAddress(mode, adr) mod 2048] = val
  of 0x3F00..0x3FFF:
    mem.nes.ppu.writePalette(adr mod 32, val)
  else: discard

const
  lengthTable: array[32'u8, uint8] = [
    10'u8, 254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14,
    12,     16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
  ]

  noiseTable = [
    4'u16, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
  ]

  dmcTable = [
    214'u8, 190, 170, 160, 143, 127, 113, 107, 95, 80, 71, 64, 53, 42, 36, 27
  ]

proc `control=`(p: Pulse, val: uint8) =
  p.dutyMode = (val shr 6) and 3
  p.lengthEnabled = not val.bit(5)
  p.envelopeLoop = val.bit(5)
  p.envelopeEnabled = not val.bit(4)
  p.envelopePeriod = val and 15
  p.constantVolume = val and 15
  p.envelopeStart = true

proc `sweep=`(p: Pulse, val: uint8) =
  p.sweepEnabled = val.bit(7)
  p.sweepPeriod = (val shr 4) and 7
  p.sweepNegate = val.bit(3)
  p.sweepShift = val and 7
  p.sweepReload = true

proc `timerLow=`(p: Pulse, val: uint8) =
  p.timerPeriod = (p.timerPeriod and 0xFF00) or val

proc `timerHigh=`(p: Pulse, val: uint8) =
  p.lengthValue = lengthTable[val shr 3]
  p.timerPeriod = (p.timerPeriod and 0x00FF) or (uint16(val and 7) shl 8)
  p.envelopeStart = true
  p.dutyValue = 0

proc `control=`(t: Triangle, val: uint8) =
  t.lengthEnabled = not val.bit(7)
  t.counterPeriod = val and 0x7F

proc `timerLow=`(t: Triangle, val: uint8) =
  t.timerPeriod = (t.timerPeriod and 0xFF00) or val

proc `timerHigh=`(t: Triangle, val: uint8) =
  t.lengthValue = lengthTable[val shr 3]
  t.timerPeriod = (t.timerPeriod and 0x00FF) or (uint16(val and 7) shl 8)
  t.timerValue = t.timerPeriod
  t.counterReload = true

proc `control=`(n: Noise, val: uint8) =
  n.lengthEnabled = not val.bit(5)
  n.envelopeLoop =      val.bit(5)
  n.envelopeEnabled = not val.bit(4)
  n.envelopePeriod = val and 15
  n.constantVolume = val and 15
  n.envelopeStart = true

proc `period=`(n: Noise, val: uint8) =
  n.mode = (val and 0x80) == 0x80
  n.timerPeriod = noiseTable[val and 0x0F]

proc `length=`(n: Noise, val: uint8) =
  n.lengthValue = lengthTable[val shr 3]
  n.envelopeStart = true

proc `control=`(d: DMC, val: uint8) =
  d.irq = val.bit(7)
  d.loop = val.bit(6)
  d.tickPeriod = dmcTable[val and 0x0F]

proc restart*(d: DMC) =
  d.currentAddress = d.sampleAddress
  d.currentLength = d.sampleLength

proc `frameCounter=`(apu: APU, val: uint8) =
  apu.framePeriod = 4'u8 + ((val shr 7) and 1)
  apu.frameIRQ = ((val shr 6) and 1) == 0

proc `control=`(apu: APU, val: uint8) =
  apu.pulse[0].enabled = val.bit(0)
  apu.pulse[1].enabled = val.bit(1)
  apu.triangle.enabled = val.bit(2)
  apu.noise.enabled    = val.bit(3)
  apu.dmc.enabled      = val.bit(4)

  if not apu.pulse[0].enabled:
    apu.pulse[0].lengthValue = 0
  if not apu.pulse[1].enabled:
    apu.pulse[1].lengthValue = 0
  if not apu.triangle.enabled:
    apu.triangle.lengthValue = 0
  if not apu.noise.enabled:
    apu.noise.lengthValue = 0
  if not apu.dmc.enabled:
    apu.dmc.currentLength = 0
  elif apu.dmc.currentLength == 0:
    apu.dmc.restart()

proc `[]`*(apu: APU, adr: uint16): uint8 =
  if adr == 0x4015:
    result = (apu.pulse[0].lengthValue > 0'u8).uint8 or
      ((apu.pulse[1].lengthValue > 0'u8).uint8 shl 1) or
      ((apu.triangle.lengthValue > 0'u8).uint8 shl 2) or
      ((apu.noise.lengthValue > 0'u8).uint8 shl 3) or
      ((apu.dmc.currentLength > 0'u16).uint8 shl 4)

proc `[]=`*(apu: APU, adr: uint16, val: uint8) =
  case adr
  of 0x4000: apu.pulse[0].control = val
  of 0x4001: apu.pulse[0].sweep = val
  of 0x4002: apu.pulse[0].timerLow = val
  of 0x4003: apu.pulse[0].timerHigh = val

  of 0x4004: apu.pulse[1].control = val
  of 0x4005: apu.pulse[1].sweep = val
  of 0x4006: apu.pulse[1].timerLow = val
  of 0x4007: apu.pulse[1].timerHigh = val

  of 0x4008: apu.triangle.control = val
  of 0x400A: apu.triangle.timerLow = val
  of 0x400B: apu.triangle.timerHigh = val

  of 0x400C: apu.noise.control = val
  of 0x400E: apu.noise.period = val
  of 0x400F: apu.noise.length = val

  of 0x4010: apu.dmc.control = val
  of 0x4011: apu.dmc.value = val and 0x7F
  of 0x4012: apu.dmc.sampleAddress = 0xC000'u16 or (val.uint16 shl 6)
  of 0x4013: apu.dmc.sampleLength = (val.uint16 shl 4) or 1

  of 0x4015: apu.control = val
  of 0x4017: apu.frameCounter = val

  else: discard


proc `[]=`*(mem: CPUMemory, adr: uint16, val: uint8)
proc `[]`*(mem: CPUMemory, adr: uint16): uint8

proc nmiChange*(ppu: PPU) =
  let nmi = ppu.nmiOutput and ppu.nmiOccured
  if nmi and not ppu.nmiPrevious: # ???
    ppu.nmiDelay = 15
  ppu.nmiPrevious = nmi

proc `control=`*(ppu: PPU, val: uint8) =
  ppu.flagNameTable = val and 3
  ppu.flagIncrement =       val.bit(2)
  ppu.flagSpriteTable =     val.bit(3)
  ppu.flagBackgroundTable = val.bit(4)
  ppu.flagSpriteSize =      val.bit(5)
  ppu.flagMasterSlave =     val.bit(6)
  ppu.nmiOutput =           val.bit(7)
  ppu.nmiChange()
  ppu.t = (ppu.t and 0xF3FF) or (uint16(val.uint16 and 0x03) shl 10)

proc `mask=`*(ppu: PPU, val: uint8) =
  ppu.flagGrayscale =          val.bit(0)
  ppu.flagShowLeftBackground = val.bit(1)
  ppu.flagShowLeftSprites =    val.bit(2)
  ppu.flagShowBackground =     val.bit(3)
  ppu.flagShowSprites =        val.bit(4)
  ppu.flagRedTint =            val.bit(5)
  ppu.flagGreenTint =          val.bit(6)
  ppu.flagBlueTint =           val.bit(7)

proc status*(ppu: PPU): uint8 =
  result = (ppu.register and 0x1F).uint8 or
    (ppu.flagSpriteOverflow.uint8 shl 5) or
    (ppu.flagSpriteZeroHit.uint8 shl 6) or
    (ppu.nmiOccured.uint8 shl 7)
  ppu.nmiOccured = false
  ppu.nmiChange()
  ppu.w = 0

proc `scroll=`(ppu: PPU, val: uint8) =
  if ppu.w == 0:
    ppu.t = (ppu.t and 0xFFE0) or (val.uint16 shr 3)
    ppu.x = val and 0x07
    ppu.w = 1
  else:
    ppu.t = (ppu.t and 0x8FFF) or (uint16(val.uint16 and 0x07) shl 12)
    ppu.t = (ppu.t and 0xFC1F) or (uint16(val.uint16 and 0xF8) shl 2)
    ppu.w = 0

proc `address=`(ppu: PPU, val: uint8) =
  if ppu.w == 0:
    ppu.t = (ppu.t and 0x80FF) or (uint16(val.uint16 and 0x3F) shl 8)
    ppu.w = 1
  else:
    ppu.t = (ppu.t and 0xFF00) or val.uint16
    ppu.v = ppu.t
    ppu.w = 0

proc data*(ppu: PPU): uint8 =
  result = ppu.mem[ppu.v]

  # emulate buffered reads
  if ppu.v mod 0x4000 < 0x3F00:
    swap ppu.bufferedData, result
  else:
    ppu.bufferedData = ppu.mem[ppu.v - 0x1000]

  ppu.v += (if ppu.flagIncrement: 32 else: 1)

proc `data=`(ppu: PPU, val: uint8) =
  ppu.mem[ppu.v] = val
  ppu.v += (if ppu.flagIncrement: 32 else: 1)

proc `dma=`(ppu: PPU, val: uint8) =
  let cpu = ppu.nes.cpu
  var adr = val.uint16 shl 8
  for i in 0..255:
    ppu.oamData[ppu.oamAddress] = cpu.mem[adr]
    inc ppu.oamAddress
    inc adr

  cpu.stall += 513
  if (cpu.cycles mod 2) == 1:
    inc cpu.stall

proc `[]`*(ppu: PPU, adr: uint16): uint8 =
  case adr
  of 0x2002: ppu.status
  of 0x2004: ppu.oamData[ppu.oamAddress]
  of 0x2007: ppu.data
  else: 0

proc `[]=`*(ppu: PPU, adr: uint16, val: uint8) =
  ppu.register = val
  case adr
  of 0x2000: ppu.control = val
  of 0x2001: ppu.mask = val
  of 0x2003: ppu.oamAddress = val
  of 0x2004: ppu.oamData[ppu.oamAddress] = val; inc ppu.oamAddress
  of 0x2005: ppu.scroll = val
  of 0x2006: ppu.address = val
  of 0x2007: ppu.data = val
  of 0x4014: ppu.dma = val
  else: discard

proc `[]=`*(mem: CPUMemory, adr: uint16, val: uint8) =
  let n = mem.nes
  case adr
  of 0x0000..0x1FFF: n.ram[adr mod 0x0800] = val
  of 0x2000..0x3FFF: n.ppu[0x2000'u16 + (adr mod 8)] = val
  of 0x4014: n.ppu[adr] = val
  of 0x4000..0x4013, 0x4015, 0x4017: n.apu[adr] = val
  of 0x4016:
    n.controllers[0].write(val)
    n.controllers[1].write(val)
  of 0x6000..0xFFFF: n.mapper[adr] = val
  else: discard # TODO: IO registers

proc `[]`*(mem: CPUMemory, adr: uint16): uint8 =
  let n = mem.nes
  case adr
  of 0x0000..0x1FFF: n.ram[adr mod 0x0800]
  of 0x2000..0x3FFF: n.ppu[0x2000'u16 + (adr mod 8)]
  of 0x4014: n.ppu[adr]
  of 0x4015: n.apu[adr]
  of 0x4016: n.controllers[0].read()
  of 0x4017: n.controllers[1].read()
  of 0x6000..0xFFFF: n.mapper[adr]
  else: 0 # TODO: IO registers

proc read16*(mem: CPUMemory, adr: uint16): uint16 =
  mem[adr+1].uint16 shl 8 or mem[adr]

proc read16bug*(mem: CPUMemory, adr: uint16): uint16 =
  ## Low byte wraps without incrementing high byte
  let
    b = (adr and 0xFF00) or uint16(uint8(adr)+1)
    lo = mem[adr]
    hi = mem[b]
  lo.uint16 or (hi.uint16 shl 8)
