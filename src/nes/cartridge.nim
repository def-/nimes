import types

export types.Cartridge

const iNESMagic = 0x1A53454E

type iNESHeader {.packed.} = object
  magic: uint32
  numPRG, numCHR, control1, control2, numRAM: uint8
  padding: array[7, uint8]

when not defined(android):
  proc newCartridge*(path: string): Cartridge =
    new result

    var file = open path
    defer: close file

    var header: iNESHeader
    # Read directly into the header object
    if file.readBuffer(addr header, sizeof header) != sizeof header:
      raise newException(ValueError, "header can't be read")

    if header.magic != iNESMagic:
      raise newException(ValueError, "header not conforming to iNES format")

    let
      mapper1 = header.control1 shr 4
      mapper2 = header.control2 shr 4
    result.mapper = mapper1 or (mapper2 shl 4)

    let
      mirror1 = header.control1 and 1
      mirror2 = (header.control1 shr 3) and 1
    result.mirror = mirror1 or (mirror2 shl 1'u8)

    result.battery = ((header.control1 shr 1) and 1) != 0

    result.prg = newSeq[uint8](header.numPRG.int * 16384)
    result.chr = newSeq[uint8](header.numCHR.int * 8192)

    if (header.control1 and 4) == 4:
      var trainer: array[512, uint8]
      if file.readBytes(trainer, 0, trainer.len) != trainer.len:
        raise newException(ValueError, "Trainer can't be read")

    if file.readBytes(result.prg, 0, result.prg.len) != result.prg.len:
      raise newException(ValueError, "PRG ROM can't be read")

    if header.numCHR == 0:
      result.chr.setLen(8192)
    elif file.readBytes(result.chr, 0, result.chr.len) != result.chr.len:
      raise newException(ValueError, "CHR ROM can't be read")

else:
  # Just a hack for Android
  # TODO: Unify with proper proc if we get real Android support

  from sdl2 import rwFromFile, read, freeRW

  proc newCartridge*(path: string): Cartridge =
    new result

    var file = rwFromFile(path.cstring, "r")
    defer: freeRW file

    var header: iNESHeader
    # Read directly into the header object
    if read(file, addr header, 1, sizeof header) != sizeof header:
      raise newException(ValueError, "header can't be read")

    if header.magic != iNESMagic:
      raise newException(ValueError, "header not conforming to iNES format")

    let
      mapper1 = header.control1 shr 4
      mapper2 = header.control2 shr 4
    result.mapper = mapper1 or (mapper2 shl 4)

    let
      mirror1 = header.control1 and 1
      mirror2 = (header.control1 shr 3) and 1
    result.mirror = mirror1 or (mirror2 shl 1'u8)

    result.battery = ((header.control1 shr 1) and 1) != 0

    result.prg = newSeq[uint8](header.numPRG.int * 16384)
    result.chr = newSeq[uint8](header.numCHR.int * 8192)

    if (header.control1 and 4) == 4:
      var trainer: array[512, uint8]
      if read(file, addr trainer[0], 1, trainer.len) != trainer.len:
        raise newException(ValueError, "Trainer can't be read")

    if read(file, addr result.prg[0], 1, result.prg.len) != result.prg.len:
      raise newException(ValueError, "PRG ROM can't be read")

    if header.numCHR == 0:
      result.chr.setLen(8192)
    elif read(file, addr result.chr[0], 1, result.chr.len) != result.chr.len:
      raise newException(ValueError, "CHR ROM can't be read")
