type
  NES* = ref NESObj
  NESObj* = object
    cpu*: CPU
    apu*: APU
    ppu*: PPU
    cartridge*: Cartridge
    controllers*: array[2, Controller]
    mapper*: Mapper
    ram*: array[2048'u16, uint8]

  CPU* = object
    mem*: CPUMemory
    cycles*: uint64
    pc*: uint16
    sp*, a*, x*, y*: uint8
    c*, z*, i*, d*, b*, u*, v*, n*: bool
    interrupt*: Interrupt
    stall*: int

  Interrupt* = enum iNone, iNMI, iIRQ

  CPUMemory* = ref object
    nes*: NES

  PPU* = object
    mem*: PPUMemory
    nes*: NES

    # Current state
    cycle*, scanLine*: int
    frame*: uint64

    # PPU memory
    paletteData*: array[32, uint8]
    nameTableData*: array[2048, uint8]
    oamData*: array[256, uint8]
    front*: Picture
    back*: ref Picture

    # Registers
    v*, t*: uint16
    x*, w*, f*, register*: uint8

    # NMI
    nmiOccured*, nmiOutput*, nmiPrevious*: bool
    nmiDelay*: uint8

    # Tiles
    nameTable*, attributeTable*, lowTile*, highTile*: uint8
    tileData*: uint64

    # Sprites
    spriteCount*: int
    spritePatterns*: array[8, uint32]
    spritePositions*, spritePriorities*, spriteIndices*: array[8, uint8]

    # $2000 PPU Control
    flagNameTable*: range[0'u8..3'u8]
    flagIncrement*, flagSpriteTable*, flagBackgroundTable*: bool
    flagSpriteSize*, flagMasterSlave*: bool

    # $2001 PPU Mask
    flagGrayscale*, flagShowLeftBackground*, flagShowLeftSprites*: bool
    flagShowBackground*, flagShowSprites*: bool
    flagRedTint*, flagGreenTint*, flagBlueTint*: bool

    # $2002 PPU Status
    flagSpriteZeroHit*, flagSpriteOverflow*: bool

    # $2003 OAM Address
    oamAddress*: uint8

    # Buffer for $2007 Data Read
    bufferedData*: uint8

  Color* = tuple[r, g, b, a: uint8]

  Picture* = array[240, array[256, Color]]

  PPUMemory* = ref object
    nes*: NES

  APU* = object
    nes*: NES
    chan*: array[4096, float32]
    chanPos*: int

    pulse*: array[2, Pulse]
    triangle*: Triangle
    noise*: Noise
    dmc*: DMC
    cycle*: uint64
    framePeriod*, frameValue*: uint8
    frameIRQ*: bool

  Pulse* = object
    enabled*: bool
    channel*: uint8

    lengthEnabled*: bool
    lengthValue*: uint8

    timerPeriod*, timerValue*: uint16

    dutyMode*, dutyValue*: uint8

    sweepReload*, sweepEnabled*, sweepNegate*: bool
    sweepShift*, sweepPeriod*, sweepValue*: uint8

    envelopeEnabled*, envelopeLoop*, envelopeStart*: bool
    envelopePeriod*, envelopeValue*, envelopeVolume*: uint8

    constantVolume*: uint8

  Noise* = object
    enabled*, mode*: bool

    shiftRegister*: uint16

    lengthEnabled*: bool
    lengthValue*: uint8

    timerPeriod*, timerValue*: uint16

    envelopeEnabled*, envelopeLoop*, envelopeStart*: bool
    envelopePeriod*, envelopeValue*, envelopeVolume*: uint8

    constantVolume*: uint8

  Triangle* = object
    enabled*: bool

    lengthEnabled*: bool
    lengthValue*: uint8

    timerPeriod*, timerValue*: uint16

    dutyValue*: uint8

    counterPeriod*, counterValue*: uint8
    counterReload*: bool

  DMC* = object
    cpu*: CPU
    enabled*: bool
    value*: uint8

    sampleAddress*, sampleLength*: uint16

    currentAddress*, currentLength*: uint16

    shiftRegister*, bitCount*, tickValue*, tickPeriod*: uint8
    loop*, irq*: bool

  Cartridge* = ref object
    prg*, chr*: seq[uint8]
    sram*: array[0x2000, uint8]
    mapper*, mirror*: uint8
    battery*: bool

  Controller* = object
    buttons*: Buttons
    index*, strobe*: uint8

  Buttons* = array[8, bool]

  Mapper* = ref object of RootObj

  MirrorModes* = enum
    mirrorHorizontal = 0, mirrorVertical, mirrorSingle0, mirrorSingle1, mirrorFour

  BitSet* = distinct uint8

const frequency* = 1789773

proc bit*(val: uint8, bit: range[0..7]): bool =
  ((val shr bit) and 1) != 0

proc triggerNMI*(cpu: var CPU) =
  cpu.interrupt = iNMI

proc triggerIRQ*(cpu: var CPU) =
  if not cpu.i:
    cpu.interrupt = iIRQ

method step*(m: Mapper) {.base.} = discard
method `[]`*(m: Mapper, adr: uint16): uint8 {.base.} = discard
method `[]=`*(m: Mapper, adr: uint16, val: uint8) {.base.} = discard
