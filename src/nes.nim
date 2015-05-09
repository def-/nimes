import nes.types, nes.cpu, nes.apu, nes.ppu, nes.cartridge, nes.controller,
  nes.mapper, nes.mem, unsigned

export types.NES, types.Buttons, setButtons, resolution

proc newNES*(path: string): NES =
  new result
  try:
    result.cartridge = newCartridge(path)
  except ValueError:
    raise newException(ValueError,
      "failed to open " & path & ": " & getCurrentExceptionMsg())
  result.controllers[0] = newController()
  result.controllers[1] = newController()
  result.mapper = newMapper(result)
  result.cpu = newCPU(result)
  result.apu = newAPU(result)
  result.ppu = newPPU(result)

proc reset*(nes: NES) =
  nes.cpu.reset()
  nes.ppu.reset()

proc step*(nes: NES): int =
  result = nes.cpu.step()

  for i in 1 .. result*3:
    nes.ppu.step()
    nes.mapper.step()

  when not defined(emscripten):
    for i in 1 .. result:
      nes.apu.step()

proc run*(nes: NES, seconds: float) =
  var cycles = int(cpu.frequency * seconds)
  while cycles > 0:
    cycles -= nes.step()

proc buffer*(nes: NES): Picture =
  nes.ppu.front

import macros, typetraits

proc dotToName(x: NimNode): string {.compileTime.} =
  result = ""
  x.expectKind(nnkDotExpr)
  for y in x.children:
    if result.len > 0:
      result.add "_"
    result.add($y)

proc dotToTyp(typ, x: NimNode): NimNode {.compileTime.} =
  result = parseExpr("type(" & typ.repr & "." & x.repr & ")")

macro serializer(typ: expr, vals: openarray[expr]): stmt {.immediate.} =
  result = newStmtList()

  result.add quote do:
    var dummy {.inject.}: `typ`

  var
    recList = newNimNode(nnkRecList)
    serList = newStmtList()
    desList = newStmtList()

  let
    src = ident("src")
    dest = ident("dest")

  for val in vals.children:
    let name = ident dotToName(val)
    let typ = dotToTyp(ident("dummy"), val)
    recList.add newIdentDefs(name, typ)
    serList.add newAssignment(newDotExpr(dest, name), parseExpr("src." & val.repr))
    desList.add newAssignment(parseExpr("dest." & val.repr), newDotExpr(src, name))

  result.add newNimNode(nnkTypeSection).add(newNimNode(nnkTypeDef).add(postfix(ident("NESSerial"), "*"), newEmptyNode(), newNimNode(nnkObjectTy).add(newEmptyNode(), newEmptyNode(), recList)))
  result.add newProc(postfix(ident("serialize"), "*"), [newEmptyNode(), newIdentDefs(dest, newNimNode(nnkVarTy).add(ident("NESSerial"))), newIdentDefs(src, ident("NES"))], serList)
  result.add newProc(postfix(ident("deserialize"), "*"), [newEmptyNode(), newIdentDefs(dest, ident("NES")), newIdentDefs(src, ident("NESSerial"))], desList)

  #echo result.repr

NES.serializer([
  #ram, # TODO

  cpu.cycles, cpu.pc, cpu.sp, cpu.a, cpu.x, cpu.y, cpu.c, cpu.z, cpu.i, cpu.d,
  cpu.b, cpu.u, cpu.v, cpu.n, cpu.interrupt, cpu.stall,

  ppu.cycle, ppu.scanLine, ppu.frame, ppu.paletteData, ppu.nameTableData,
  ppu.oamData, ppu.v, ppu.t, ppu.x, ppu.w, ppu.f, ppu.register,
  ppu.nmiOccured, ppu.nmiOutput, ppu.nmiPrevious, ppu.nmiDelay, ppu.nameTable,
  ppu.attributeTable, ppu.lowTile, ppu.highTile, ppu.tileData, ppu.spriteCount,
  ppu.spritePatterns, ppu.spritePositions, ppu.spritePriorities,
  ppu.spriteIndices, ppu.flagNameTable, ppu.flagIncrement, ppu.flagSpriteTable,
  ppu.flagBackgroundTable, ppu.flagSpriteSize, ppu.flagMasterSlave,
  ppu.flagGrayscale, ppu.flagShowLeftBackground, ppu.flagShowLeftSprites,
  ppu.flagShowBackground, ppu.flagShowSprites, ppu.flagRedTint,
  ppu.flagGreenTint, ppu.flagBlueTint, ppu.flagSpriteZeroHit,
  ppu.flagSpriteOverflow, ppu.oamAddress, ppu.bufferedData,
])
