import types, mem, mapper

export types.PPU

const resolution* = (x: 256.cint, y: 240.cint)

proc initPalette: array[0x40'u8, Color] =
  const cs = [
    0x666666, 0x002A88, 0x1412A7, 0x3B00A4, 0x5C007E, 0x6E0040, 0x6C0600, 0x561D00,
    0x333500, 0x0B4800, 0x005200, 0x004F08, 0x00404D, 0x000000, 0x000000, 0x000000,
    0xADADAD, 0x155FD9, 0x4240FF, 0x7527FE, 0xA01ACC, 0xB71E7B, 0xB53120, 0x994E00,
    0x6B6D00, 0x388700, 0x0C9300, 0x008F32, 0x007C8D, 0x000000, 0x000000, 0x000000,
    0xFFFEFF, 0x64B0FF, 0x9290FF, 0xC676FF, 0xF36AFF, 0xFE6ECC, 0xFE8170, 0xEA9E22,
    0xBCBE00, 0x88D800, 0x5CE430, 0x45E082, 0x48CDDE, 0x4F4F4F, 0x000000, 0x000000,
    0xFFFEFF, 0xC0DFFF, 0xD3D2FF, 0xE8C8FF, 0xFBC2FF, 0xFEC4EA, 0xFECCC5, 0xF7D8A5,
    0xE4E594, 0xCFEF96, 0xBDF4AB, 0xB3F3CC, 0xB5EBF2, 0xB8B8B8, 0x000000, 0x000000]

  for i, x in result.mpairs:
    x = (r: uint8(cs[(int)i] shr 16), g: uint8(cs[(int)i] shr 8 and 0xFF),
         b: uint8(cs[(int)i] and 0xFF), a: 255'u8)

const palette* = initPalette()

proc reset*(ppu: var PPU) =
  ppu.cycle = 340
  ppu.scanLine = 240
  ppu.frame = 0
  ppu.control = 0
  ppu.mask = 0
  ppu.oamAddress = 0

proc initPPU*(nes: NES): PPU =
  new result.back
  result.mem = newPPUMemory(nes)
  result.nes = nes
  result.reset()

proc incrementX(ppu: var PPU) =
  if (ppu.v and 0x001F) == 31:
    ppu.v = (ppu.v and 0xFFE0) xor 0x0400
  else:
    inc ppu.v

proc incrementY(ppu: var PPU) =
  if (ppu.v and 0x7000) != 0x7000:
    ppu.v += 0x1000
  else:
    ppu.v = ppu.v and 0x8FFF
    var y = (ppu.v and 0x03E0) shr 5
    if y == 29:
      y = 0
      ppu.v = ppu.v xor 0x0800
    elif y == 31:
      y = 0
    else:
      inc y
    ppu.v = (ppu.v and 0xFC1F) or (y shl 5)

proc copyX(ppu: var PPU) =
  ppu.v = (ppu.v and 0xFBE0) or (ppu.t and 0x041F)

proc copyY(ppu: var PPU) =
  ppu.v = (ppu.v and 0x841F) or (ppu.t and 0x7BE0)

proc setVerticalBlank(ppu: var PPU) =
  #swap ppu.front, ppu.back[]
  var tmp: Picture
  copyMem(addr tmp, addr ppu.back[], sizeof(tmp))
  copyMem(addr ppu.back[], addr ppu.front, sizeof(tmp))
  copyMem(addr ppu.front, addr tmp, sizeof(tmp))
  ppu.nmiOccured = true
  ppu.nmiChange()

proc clearVerticalBlank(ppu: var PPU) =
  ppu.nmiOccured = false
  ppu.nmiChange()

proc fetchNameTableByte(ppu: var PPU) =
  let adr = 0x2000'u16 or (ppu.v and 0x0FFF)
  ppu.nameTable = ppu.mem[adr]

proc fetchAttributeTableByte(ppu: var PPU) =
  let
    adr = 0x23C0'u16 or ppu.v and 0x0C00 or (ppu.v shr 4) and 0x38 or
      (ppu.v shr 2) and 0x07
    shift = uint8(((ppu.v shr 4) and 4) or (ppu.v and 2))
  ppu.attributeTable = uint8((ppu.mem[adr] shr shift) and 3) shl 2

template tileAdr: untyped {.dirty.} =
  ppu.flagBackgroundTable.uint16*0x1000 + ppu.nameTable.uint16*16 +
    ((ppu.v shr 12) and 7)

proc fetchLowTileByte(ppu: var PPU) =
  ppu.lowTile = ppu.mem[tileAdr]

proc fetchHighTileByte(ppu: var PPU) =
  ppu.highTile = ppu.mem[tileAdr+8]

proc storeTileData(ppu: var PPU) =
  var data: uint32
  for i in 0..7:
    let a = ppu.attributeTable
    let p1 = (ppu.lowTile and 0x80) shr 7
    let p2 = (ppu.highTile and 0x80) shr 6
    ppu.lowTile = ppu.lowTile shl 1
    ppu.highTile = ppu.highTile shl 1
    data = (data shl 4) or a or p1 or p2
  ppu.tileData = ppu.tileData or data.uint64

proc fetchTileData(ppu: PPU): uint32 =
  uint32(ppu.tileData shr 32)

proc backgroundPixel(ppu: var PPU): uint8 =
  if not ppu.flagShowBackground:
    return

  let data = ppu.fetchTileData() shr ((7'u32-ppu.x)*4)
  result = uint8(data and 0x0F)

proc spritePixel(ppu: var PPU): (uint8, uint8) =
  if not ppu.flagShowSprites:
    return

  for i in 0 ..< ppu.spriteCount:
    var offset = ppu.cycle - 1 - ppu.spritePositions[i].int
    if offset notin 0..7:
      continue

    offset = 7 - offset
    let color = uint8((ppu.spritePatterns[i] shr uint32(offset*4)) and 0x0F)
    if color mod 4 == 0:
      continue

    return (i.uint8, color)

proc renderPixel(ppu: var PPU) =
  let x = ppu.cycle - 1
  let y = ppu.scanLine
  var background = ppu.backgroundPixel()
  var (i, sprite) = ppu.spritePixel()

  if x < 8:
    if not ppu.flagShowLeftBackground:
      background = 0
    if not ppu.flagShowLeftSprites:
      sprite = 0

  let b = (background mod 4) != 0
  let s = (sprite mod 4) != 0
  var color: uint8

  if not b:
    color = if s: sprite or 0x10 else: 0
  elif not s:
    color = background
  else:
    if ppu.spriteIndices[i] == 0 and x < 255:
      ppu.flagSpriteZeroHit = true
    if ppu.spritePriorities[i] == 0:
      color = sprite or 0x10
    else:
      color = background

  let c = palette[ppu.readPalette(color.uint16) mod 64]
  ppu.back[y][x] = c

proc fetchSpritePattern(ppu: var PPU, i, row: int): uint32 =
  var row = row
  var tile = ppu.oamData[i*4+1]
  let attributes = ppu.oamData[i*4+2]
  var adr: uint16
  var table: uint8

  if not ppu.flagSpriteSize:
    if (attributes and 0x80) == 0x80:
      row = 7 - row
    table = ppu.flagSpriteTable.uint8
  else:
    if (attributes and 0x80) == 0x80:
      row = 15 - row
    table = tile and 1
    tile = tile and 0xFE
    if row > 7:
      inc tile
      row -= 8

  adr = table.uint16*0x1000 + tile.uint16*16 + row.uint16

  let a = (attributes and 3'u8) shl 2'u8
  var lowTileByte = ppu.mem[adr]
  var highTileByte = ppu.mem[adr+8]
  #echo adr, " ", lowTileByte, " ", highTileByte

  for i in 0..7:
    var p1, p2: uint8
    if (attributes and 0x40) == 0x40:
      p1 = lowTileByte and 1
      p2 = (highTileByte and 1) shl 1'u8
      lowTileByte = lowTileByte shr 1'u8
      highTileByte = highTileByte shr 1'u8
    else:
      p1 = (lowTileByte and 0x80) shr 7'u8
      p2 = (highTileByte and 0x80) shr 6'u8
      lowTileByte = lowTileByte shl 1'u8
      highTileByte = highTileByte shl 1'u8

    result = (result shl 4'u32) or uint32(a or p1 or p2)

proc evaluateSprites(ppu: var PPU) =
  var h = if ppu.flagSpriteSize: 16 else: 8
  var count = 0
  for i in 0..63:
    let y = ppu.oamData[i*4+0]
    let a = ppu.oamData[i*4+2]
    let x = ppu.oamData[i*4+3]
    let row = ppu.scanLine - y.int

    if row notin 0 ..< h:
      continue

    if count < 8:
      ppu.spritePatterns[count] = ppu.fetchSpritePattern(i, row)
      ppu.spritePositions[count] = x
      ppu.spritePriorities[count] = (a shr 5) and 1
      ppu.spriteIndices[count] = i.uint8

    inc count

  if count > 8:
    count = 8
    ppu.flagSpriteOverflow = true

  ppu.spriteCount = count

proc tick(ppu: var PPU) =
  if ppu.nmiDelay > 0'u8:
    dec ppu.nmiDelay
    if ppu.nmiDelay == 0 and ppu.nmiOutput and ppu.nmiOccured:
      ppu.nes.cpu.triggerNMI()

  if ppu.flagShowBackground or ppu.flagShowSprites:
    if ppu.f == 1 and ppu.scanLine == 261 and ppu.cycle == 339:
      ppu.cycle = 0
      ppu.scanLine = 0
      inc ppu.frame
      ppu.f = ppu.f xor 1
      return

  inc ppu.cycle
  if ppu.cycle > 340:
    ppu.cycle = 0
    inc ppu.scanLine
    if ppu.scanLine > 261:
      ppu.scanLine = 0
      inc ppu.frame
      ppu.f = ppu.f xor 1

proc step*(ppu: var PPU) =
  ppu.tick()

  let
    preLine = ppu.scanLine == 261
    visibleLine = ppu.scanLine < 240
    renderLine = preLine or visibleLine
    preFetchCycle = ppu.cycle in 321..336
    visibleCycle = ppu.cycle in 1..256
    fetchCycle = preFetchCycle or visibleCycle

  if ppu.flagShowBackground or ppu.flagShowSprites:
    # Background logic
    if visibleLine and visibleCycle:
      ppu.renderPixel()

    if renderLine and fetchCycle:
      ppu.tileData = ppu.tileData shl 4
      case ppu.cycle mod 8
      of 0: ppu.storeTileData()
      of 1: ppu.fetchNameTableByte()
      of 3: ppu.fetchAttributeTableByte()
      of 5: ppu.fetchLowTileByte()
      of 7: ppu.fetchHighTileByte()
      else: discard

    if preLine and ppu.cycle in 280..304:
      ppu.copyY()

    if renderLine:
      if fetchCycle and (ppu.cycle mod 8) == 0:
        ppu.incrementX()
      if ppu.cycle == 256:
        ppu.incrementY()
      if ppu.cycle == 257:
        ppu.copyX()

    # Sprite logic
    if ppu.cycle == 257:
      if visibleLine:
        ppu.evaluateSprites()
      else:
        ppu.spriteCount = 0

  # VBlank logic
  if ppu.scanLine == 241 and ppu.cycle == 1:
    ppu.setVerticalBlank()
  if preLine and ppu.cycle == 1:
    ppu.clearVerticalBlank()
    ppu.flagSpriteZeroHit = false
    ppu.flagSpriteOverflow = false
