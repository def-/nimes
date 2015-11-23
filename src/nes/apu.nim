import types, mem

export types.APU

proc initPulseTable: array[32, float32] =
  for i, x in result.mpairs:
    x = 95.52 / (8128/i.float32 + 100)

proc initTndTable: array[204, float32] =
  for i, x in result.mpairs:
    x = 163.67 / (24329/i.float32 + 100)

const
  frameCounterRate = frequency / 240.0
  sampleRate = frequency / 44100.0

  # slightly wrong with const. TODO: Report compiler VM bug
  pulseTable = initPulseTable()

  tndTable = initTndTable()

#echo repr pulseTable
#echo repr initPulseTable()
#echo repr tndTable
#echo repr initTndTable()

const
  dutyTable: array[4'u8, array[8'u8, uint8]] = [
    [0'u8, 1, 0, 0, 0, 0, 0, 0],
    [0'u8, 1, 1, 0, 0, 0, 0, 0],
    [0'u8, 1, 1, 1, 1, 0, 0, 0],
    [1'u8, 0, 0, 1, 1, 1, 1, 1],
  ]

  triangleTable: array[32'u8, uint8] = [
    15'u8, 14, 13, 12, 11, 10,  9,  8,  7,  6,  5,  4,  3,  2,  1,  0,
     0,     1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
  ]

proc initAPU*(nes: NES): APU =
  result.nes = nes
  result.noise.shiftRegister = 1
  result.pulse[0].channel = 1
  result.pulse[1].channel = 2
  result.dmc.cpu = nes.cpu

proc output(p: Pulse): uint8 =
  if not p.enabled: return
  if p.lengthValue == 0: return
  if dutyTable[p.dutyMode][p.dutyValue] == 0: return
  if p.timerPeriod notin 0x008'u16..0x7FF'u16: return

  if p.envelopeEnabled: return p.envelopeVolume
  else: return p.constantVolume

proc sweep(p: var Pulse) =
  let delta = p.timerPeriod shr p.sweepShift
  if p.sweepNegate:
    p.timerPeriod -= delta
    if p.channel == 1:
      dec p.timerPeriod
  else:
    p.timerPeriod += delta

proc stepTimer(p: var Pulse) =
  if p.timerValue == 0:
    p.timerValue = p.timerPeriod
    p.dutyValue = (p.dutyValue + 1) mod 8
  else:
    dec p.timerValue

proc stepEnvelope(p: var Pulse) =
  if p.envelopeStart:
    p.envelopeVolume = 15
    p.envelopeValue = p.envelopePeriod
    p.envelopeStart = false
  elif p.envelopeValue > 0'u8:
    dec p.envelopeValue
  else:
    if p.envelopeVolume > 0'u8:
      dec p.envelopeVolume
    elif p.envelopeLoop:
      p.envelopeVolume = 15
    p.envelopeValue = p.envelopePeriod

proc stepSweep(p: var Pulse) =
  if p.sweepReload:
    if p.sweepEnabled and p.sweepValue == 0:
      p.sweep()

    p.sweepValue = p.sweepPeriod
    p.sweepReload = false
  elif p.sweepValue > 0'u8:
    dec p.sweepValue
  else:
    if p.sweepEnabled:
      p.sweep()
    p.sweepValue = p.sweepPeriod

proc stepLength(p: var Pulse) =
  if p.lengthEnabled and p.lengthValue > 0'u8:
    dec p.lengthValue

proc stepTimer(t: var Triangle) =
  if t.timerValue == 0:
    t.timerValue = t.timerPeriod
    if t.lengthValue > 0'u8 and t.counterValue > 0'u8:
      t.dutyValue = (t.dutyValue + 1) mod 32
  else:
    dec t.timerValue

proc stepLength(t: var Triangle) =
  if t.lengthEnabled and t.lengthValue > 0'u8:
    dec t.lengthValue

proc stepCounter(t: var Triangle) =
  if t.counterReload:
    t.counterValue = t.counterPeriod
  elif t.counterValue > 0'u8:
    dec t.counterValue
  if t.lengthEnabled:
    t.counterReload = false

proc output(t: Triangle): uint8 =
  if not t.enabled: return
  if t.lengthValue == 0: return
  if t.counterValue == 0: return
  return triangleTable[t.dutyValue]

proc stepTimer(n: var Noise) =
  if n.timerValue == 0:
    n.timerValue = n.timerPeriod
    let
      shift = if n.mode: 6'u16 else: 1'u16
      b1 = n.shiftRegister and 1
      b2 = (n.shiftRegister shr shift) and 1
    n.shiftRegister = (n.shiftRegister shr 1) or (uint16(b1 xor b2) shl 14)
  else:
    dec n.timerValue

proc stepEnvelope(n: var Noise) =
  if n.envelopeStart:
    n.envelopeVolume = 15
    n.envelopeValue = n.envelopePeriod
    n.envelopeStart = false
  elif n.envelopeValue > 0'u8:
    dec n.envelopeValue
  else:
    if n.envelopeVolume > 0'u8:
      dec n.envelopeVolume
    elif n.envelopeLoop:
      n.envelopeVolume = 15
    n.envelopeValue = n.envelopePeriod

proc stepLength(n: var Noise) =
  if n.lengthEnabled and n.lengthValue > 0'u8:
    dec n.lengthValue

proc output(n: Noise): uint8 =
  if not n.enabled: return
  if n.lengthValue == 0: return
  if (n.shiftRegister and 1) == 1: return
  #echo n.timerPeriod, " ", n.timerValue
  if n.envelopeEnabled: return n.envelopeVolume
  else: return n.constantVolume

proc stepReader(d: var DMC) =
  if d.currentLength > 0'u16 and d.bitCount == 0:
    d.cpu.stall += 4
    d.shiftRegister = d.cpu.mem[d.currentAddress]
    d.bitCount = 8
    inc d.currentAddress
    if d.currentAddress == 0:
      d.currentAddress = 0x8000
    dec d.currentLength
    if d.currentLength == 0 and d.loop:
      d.restart()

proc stepShifter(d: var DMC) =
  if d.bitCount == 0:
    return

  if (d.shiftRegister and 1) == 1:
    if d.value <= 125:
      d.value += 2
  elif d.value >= 2'u8:
    d.value -= 2

  d.shiftRegister = d.shiftRegister shr 1
  dec d.bitCount

proc stepTimer(d: var DMC) =
  if not d.enabled:
    return

  d.stepReader()
  if d.tickValue == 0:
    d.tickValue = d.tickPeriod
    d.stepShifter()
  else:
    dec d.tickValue

proc stepTimer(apu: var APU) =
  if apu.cycle mod 2 == 0:
    apu.pulse[0].stepTimer()
    apu.pulse[1].stepTimer()
    apu.noise.stepTimer()
    apu.dmc.stepTimer()

  apu.triangle.stepTimer()

proc stepEnvelope(apu: var APU) =
  apu.pulse[0].stepEnvelope()
  apu.pulse[1].stepEnvelope()
  apu.triangle.stepCounter()
  apu.noise.stepEnvelope()

proc stepSweep(apu: var APU) =
  apu.pulse[0].stepSweep()
  apu.pulse[1].stepSweep()

proc stepLength(apu: var APU) =
  apu.pulse[0].stepLength()
  apu.pulse[1].stepLength()
  apu.triangle.stepLength()
  apu.noise.stepLength()

proc fireIRQ(apu: var APU) =
  if apu.frameIRQ:
    apu.nes.cpu.triggerIRQ()

proc stepFrameCounter(apu: var APU) =
  case apu.framePeriod
  of 4:
    apu.frameValue = (apu.frameValue + 1) mod 4
    case apu.frameValue
    of 0, 2:
      apu.stepEnvelope()
    of 1:
      apu.stepEnvelope()
      apu.stepSweep()
      apu.stepLength()
    of 3:
      apu.stepEnvelope()
      apu.stepSweep()
      apu.stepLength()
      apu.fireIRQ()
    else: discard
  of 5:
    apu.frameValue = (apu.frameValue + 1) mod 5
    case apu.frameValue
    of 1, 3:
      apu.stepEnvelope()
    of 0, 2:
      apu.stepEnvelope()
      apu.stepSweep()
      apu.stepLength()
    else: discard
  else: discard

proc output(apu: APU): float32 =
  let
    p0 = apu.pulse[0].output()
    p1 = apu.pulse[1].output()
    t = apu.triangle.output()
    n = apu.noise.output()
    d = apu.dmc.value

  result = pulseTable[p0+p1] + tndTable[t*3+n*2+d]

proc step*(apu: var APU) =
  let c1 = apu.cycle.float64
  inc apu.cycle
  let c2 = apu.cycle.float64
  apu.stepTimer()
  let f1 = int(c1 / frameCounterRate)
  let f2 = int(c2 / frameCounterRate)
  if f1 != f2:
    apu.stepFrameCounter()
  let s1 = int(c1 / sampleRate)
  let s2 = int(c2 / sampleRate)
  if s1 != s2:
    if apu.chanPos < apu.chan.len:
      apu.chan[apu.chanPos] = apu.output()
      inc apu.chanPos
