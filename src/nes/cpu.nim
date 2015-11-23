import types, mem

export types.CPU, types.frequency

type
  StepInfo = object
    address, pc: uint16
    mode: AddressingMode

  AddressingMode = enum
    absolute, absoluteX, absoluteY, accumulator, immediate, implied,
    indexedIndirect, indirect, indirectIndexed, relative, zeroPage, zeroPageX,
    zeroPageY

template mem: expr{.immediate, dirty.} = cpu.mem

proc push(cpu: var CPU, val: uint8) =
  mem[cpu.sp.uint16 or 0x100] = val
  dec cpu.sp

proc pull(cpu: var CPU): uint8 =
  inc cpu.sp
  result = mem[cpu.sp.uint16 or 0x100]

proc push16(cpu: var CPU, val: uint16) =
  cpu.push uint8(val shr 8)
  cpu.push uint8(val)

proc pull16(cpu: var CPU): uint16 =
  uint16(cpu.pull()) or (uint16(cpu.pull()) shl 8)

proc setZ(cpu: var CPU, val: uint8) =
  cpu.z = val == 0

proc setN(cpu: var CPU, val: uint8) =
  cpu.n = (val and 0x80) != 0

proc setZN(cpu: var CPU, val: uint8) =
  cpu.setZ(val)
  cpu.setN(val)

proc flags(cpu: CPU): uint8 =
  cpu.c.uint8 or
    (cpu.z.uint8 shl 1) or
    (cpu.i.uint8 shl 2) or
    (cpu.d.uint8 shl 3) or
    (cpu.b.uint8 shl 4) or
    (cpu.u.uint8 shl 5) or
    (cpu.v.uint8 shl 6) or
    (cpu.n.uint8 shl 7)

proc `flags=`(cpu: var CPU, flags: uint8) =
  cpu.c = flags.bit(0)
  cpu.z = flags.bit(1)
  cpu.i = flags.bit(2)
  cpu.d = flags.bit(3)
  cpu.b = flags.bit(4)
  cpu.u = flags.bit(5)
  cpu.v = flags.bit(6)
  cpu.n = flags.bit(7)

proc reset*(cpu: var CPU) =
  cpu.pc = mem.read16(0xFFFC)
  cpu.sp = 0xFD
  cpu.flags = 0x24

proc initCPU*(nes: NES): CPU =
  result.mem = newCPUMemory(nes)
  result.reset()

proc pagesDiffer(a, b: uint16): bool =
  (a and 0xFF00) != (b and 0xFF00)

proc branch(cpu: var CPU, info: StepInfo) =
  cpu.pc = info.address
  inc cpu.cycles
  if pagesDiffer(info.pc, info.address):
    inc cpu.cycles

proc compare(cpu: var CPU, a, b: uint8) =
  cpu.setZN(a - b)
  cpu.c = a >= b

template op(name, code: expr): stmt {.dirty.} =
  proc name(cpu: var CPU, info = StepInfo()) =
    code

template op(name, zn, code: expr): stmt {.dirty.} =
  proc name(cpu: var CPU, info = StepInfo()) =
    code
    cpu.setZN(zn)

op adc, cpu.a: # Add with carry
  let a = cpu.a
  let b = mem[info.address]
  let c = cpu.c.uint8

  cpu.a = a + b + c
  cpu.c = a.int + b.int + c.int > 0xFF
  cpu.v = ((a xor b) and 0x80) == 0 and ((a xor cpu.a) and 0x80) != 0

op und, cpu.a: # Logical and
  cpu.a = cpu.a and mem[info.address]

op asl: # Arithmetic shift left
  if info.mode == accumulator:
    cpu.c = ((cpu.a shr 7) and 1) != 0
    cpu.a = cpu.a shl 1
    cpu.setZN(cpu.a)
  else:
    var val = mem[info.address]
    cpu.c = ((val shr 7) and 1) != 0
    val = val shl 1
    mem[info.address] = val
    cpu.setZN(val)

op bcc: # Branch if carry clear
  if not cpu.c:
    cpu.branch(info)

op bcs: # Branch if carry set
  if cpu.c:
    cpu.branch(info)

op beq: # Branch if equal
  if cpu.z:
    cpu.branch(info)

op bit: # Bit test
  let val = mem[info.address]
  cpu.v = ((val shr 6) and 1) != 0
  cpu.setZ(val and cpu.a)
  cpu.setN(val)

op bmi: # Branch if minus
  if cpu.n:
    cpu.branch(info)

op bne: # Branch if not equal
  if not cpu.z:
    cpu.branch(info)

op bpl: # Branch if positive
  if not cpu.n:
    cpu.branch(info)

op bvc: # Branch if overflow clear
  if not cpu.v:
    cpu.branch(info)

op bvs: # Branch if overflow set
  if cpu.v:
    cpu.branch(info)

op clc: # Clear carry flag
  cpu.c = false

op cld: # Clear decimal mode
  cpu.d = false

op cli: # Clear interrupt disable
  cpu.i = false

op clv: # Clear overflow flag
  cpu.v = false

op cmp: # Compare
  cpu.compare(cpu.a, mem[info.address])

op cpx: # Compare x register
  cpu.compare(cpu.x, mem[info.address])

op cpy: # Compare y register
  cpu.compare(cpu.y, mem[info.address])

op dec, val: # Decrement memory
  let val = mem[info.address] - 1
  mem[info.address] = val

op dex, cpu.x: # Decrement x register
  dec cpu.x

op dey, cpu.y: # Decrement y register
  dec cpu.y

op eor, cpu.a: # Exclusive or
  cpu.a = cpu.a xor mem[info.address]

op inc, val: # Increment memory
  let val = mem[info.address] + 1
  mem[info.address] = val

op inx, cpu.x: # Increment x register
  inc cpu.x

op iny, cpu.y: # Increment y register
  inc cpu.y

op jmp: # Jump
  cpu.pc = info.address

op jsr: # Jump to subroutine
  cpu.push16(cpu.pc - 1)
  cpu.pc = info.address

op lda, cpu.a: # Load accumulator
  cpu.a = mem[info.address]

op ldx, cpu.x: # Load x register
  cpu.x = mem[info.address]

op ldy, cpu.y: # Load y register
  cpu.y = mem[info.address]

op lsr: # Logical shift right
  if info.mode == accumulator:
    cpu.c = (cpu.a and 1) != 0
    cpu.a = cpu.a shr 1
    cpu.setZN(cpu.a)
  else:
    var val = mem[info.address]
    cpu.c = (val and 1) != 0
    val = val shr 1
    mem[info.address] = val
    cpu.setZN(val)

op nop: # No operation
  discard

op ora, cpu.a: # Logical inclusive or
  cpu.a = cpu.a or mem[info.address]

op pha: # Push accumulator
  cpu.push(cpu.a)

op php: # Push processor status
  cpu.push(cpu.flags or 0x10)

op pla, cpu.a: # Pull accumulator
  cpu.a = cpu.pull()

op plp: # Pull processor status
  cpu.flags = cpu.pull() and 0xEF or 0x20

op rol: # Rotate left
  let c = cpu.c.uint8
  if info.mode == accumulator:
    cpu.c = ((cpu.a shr 7) and 1) != 0
    cpu.a = (cpu.a shl 1) or c
    cpu.setZN(cpu.a)
  else:
    var val = mem[info.address]
    cpu.c = ((val shr 7) and 1) != 0
    val = (val shl 1) or c
    mem[info.address] = val
    cpu.setZN(val)

op ror: # Rotate right
  let c = cpu.c.uint8
  if info.mode == accumulator:
    cpu.c = (cpu.a and 1) != 0
    cpu.a = (cpu.a shr 1) or (c shl 7)
    cpu.setZN(cpu.a)
  else:
    var val = mem[info.address]
    cpu.c = (val and 1) != 0
    val = (val shr 1) or (c shl 7)
    mem[info.address] = val
    cpu.setZN(val)

op rti: # Return from interrupt
  cpu.flags = cpu.pull and 0xEF or 0x20
  cpu.pc = cpu.pull16()

op rts: # Return from subrouting
  cpu.pc = cpu.pull16() + 1

op sbc, cpu.a: # Subtract with carry
  let a = cpu.a
  let b = mem[info.address]
  let c = cpu.c.uint8

  cpu.a = a - b - (1'u8 - c)
  cpu.c = a.int - b.int - (1'u8-c).int >= 0
  cpu.v = ((a xor b) and 0x80) != 0 and ((a xor cpu.a) and 0x80) != 0

op sec: # Set carry flag
  cpu.c = true

op sed: # Set decimal flag
  cpu.d = true

op sei: # Set interrupt disable
  cpu.i = true

op sta: # Store accumulator
  mem[info.address] = cpu.a

op stx: # Store x register
  mem[info.address] = cpu.x

op sty: # Store y register
  mem[info.address] = cpu.y

op tax, cpu.x: # Transfer accumulator to x
  cpu.x = cpu.a

op tay, cpu.y: # Transfer accumulator to y
  cpu.y = cpu.a

op tsx, cpu.x: # Transfer stack pointer to x
  cpu.x = cpu.sp

op txa, cpu.a: # Transfer x to accumulator
  cpu.a = cpu.x

op txs: # Transfer x to stack pointer
  cpu.sp = cpu.x

op tya, cpu.a: # Transfer y to accumulator
  cpu.a = cpu.y

op brk: # Force interrupt
  cpu.push16(cpu.pc)
  cpu.php(info)
  cpu.sei(info)
  cpu.pc = mem.read16(0xFFFE)

# Illegal opcodes
op ahx: discard
op alr: discard
op anc: discard
op arr: discard
op axs: discard
op dcp: discard
op isc: discard
op kil: discard
op las: discard
op lax: discard
op rla: discard
op rra: discard
op sax: discard
op shx: discard
op shy: discard
op slo: discard
op sre: discard
op tas: discard
op xaa: discard

let
  instructions: array[uint8, proc] = [ # All 6502 instructions
   brk, ora, kil, slo, nop, ora, asl, slo, php, ora, asl, anc, nop, ora, asl, slo,
   bpl, ora, kil, slo, nop, ora, asl, slo, clc, ora, nop, slo, nop, ora, asl, slo,
   jsr, und, kil, rla, bit, und, rol, rla, plp, und, rol, anc, bit, und, rol, rla,
   bmi, und, kil, rla, nop, und, rol, rla, sec, und, nop, rla, nop, und, rol, rla,
   rti, eor, kil, sre, nop, eor, lsr, sre, pha, eor, lsr, alr, jmp, eor, lsr, sre,
   bvc, eor, kil, sre, nop, eor, lsr, sre, cli, eor, nop, sre, nop, eor, lsr, sre,
   rts, adc, kil, rra, nop, adc, ror, rra, pla, adc, ror, arr, jmp, adc, ror, rra,
   bvs, adc, kil, rra, nop, adc, ror, rra, sei, adc, nop, rra, nop, adc, ror, rra,
   nop, sta, nop, sax, sty, sta, stx, sax, dey, nop, txa, xaa, sty, sta, stx, sax,
   bcc, sta, kil, ahx, sty, sta, stx, sax, tya, sta, txs, tas, shy, sta, shx, ahx,
   ldy, lda, ldx, lax, ldy, lda, ldx, lax, tay, lda, tax, lax, ldy, lda, ldx, lax,
   bcs, lda, kil, lax, ldy, lda, ldx, lax, clv, lda, tsx, las, ldy, lda, ldx, lax,
   cpy, cmp, nop, dcp, cpy, cmp, dec, dcp, iny, cmp, dex, axs, cpy, cmp, dec, dcp,
   bne, cmp, kil, dcp, nop, cmp, dec, dcp, cld, cmp, nop, dcp, nop, cmp, dec, dcp,
   cpx, sbc, nop, isc, cpx, sbc, inc, isc, inx, sbc, nop, sbc, cpx, sbc, inc, isc,
   beq, sbc, kil, isc, nop, sbc, inc, isc, sed, sbc, nop, isc, nop, sbc, inc, isc,
  ]
const
  instructionModes: array[uint8, uint8] = [ # Addressing modes
     5'u8,6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     0,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     5,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     5,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   7,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  12,  12,   5,   2,   5,   2,   1,   1,   2,   2,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  12,  12,   5,   2,   5,   2,   1,   1,   2,   2,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
  ]

  instructionSizes: array[uint8, uint8] = [ # Size in bytes
     1'u8,2,   0,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
     3,   2,   0,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
     1,   2,   0,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
     1,   2,   0,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   0,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   0,   3,   0,   0,
     2,   2,   2,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   2,   1,   0,   3,   3,   3,   0,
     2,   2,   0,   0,   2,   2,   2,   0,   1,   3,   1,   0,   3,   3,   3,   0,
  ]

  instructionCycles: array[uint8, uint8] = [ # Number of cycles used
     7'u8,6,   2,   8,   3,   3,   5,   5,   3,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     6,   6,   2,   8,   3,   3,   5,   5,   4,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     6,   6,   2,   8,   3,   3,   5,   5,   3,   2,   2,   2,   3,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     6,   6,   2,   8,   3,   3,   5,   5,   4,   2,   2,   2,   5,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     2,   6,   2,   6,   3,   3,   3,   3,   2,   2,   2,   2,   4,   4,   4,   4,
     2,   6,   2,   6,   4,   4,   4,   4,   2,   5,   2,   5,   5,   5,   5,   5,
     2,   6,   2,   6,   3,   3,   3,   3,   2,   2,   2,   2,   4,   4,   4,   4,
     2,   5,   2,   5,   4,   4,   4,   4,   2,   4,   2,   4,   4,   4,   4,   4,
     2,   6,   2,   8,   3,   3,   5,   5,   2,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     2,   6,   2,   8,   3,   3,   5,   5,   2,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
  ]

  instructionPageCycles: array[uint8, uint8] = [ # Cycles used on a page cross
     0'u8,0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   1,   0,   0,   0,   0,   0,   1,   0,   1,   1,   1,   1,   1,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
  ]

proc nmi(cpu: var CPU) = # Non-maskable interrupt
  cpu.push16(cpu.pc)
  cpu.php()
  cpu.pc = mem.read16(0xFFFA)
  cpu.i = true
  cpu.cycles += 7

proc irq(cpu: var CPU) = # IRQ interrupt
  cpu.push16(cpu.pc)
  cpu.php()
  cpu.pc = mem.read16(0xFFFE)
  cpu.i = true
  cpu.cycles += 7

proc step*(cpu: var CPU): int =
  if cpu.stall > 0:
    dec cpu.stall
    return 1

  let cycles = cpu.cycles

  case cpu.interrupt
  of iNMI: cpu.nmi()
  of iIRQ: cpu.irq()
  else: discard

  cpu.interrupt = iNone

  let opcode = mem[cpu.pc]
  let mode = instructionModes[opcode].AddressingMode

  let adr = case mode
  of absolute:        mem.read16(cpu.pc+1)
  of absoluteX:       mem.read16(cpu.pc+1) + cpu.x
  of absoluteY:       mem.read16(cpu.pc+1) + cpu.y

  of indexedIndirect: mem.read16bug(mem[cpu.pc+1] + cpu.x)
  of indirect:        mem.read16bug(mem.read16(cpu.pc+1))
  of indirectIndexed: mem.read16bug(mem[cpu.pc+1]) + cpu.y

  of zeroPage:        mem[cpu.pc+1]
  of zeroPageX:       mem[cpu.pc+1] + cpu.x
  of zeroPageY:       mem[cpu.pc+1] + cpu.y

  of immediate:       cpu.pc + 1
  of accumulator, implied: 0
  of relative:
    let offset = mem[cpu.pc+1].uint16
    if offset < 0x80:
      cpu.pc + 2 + offset
    else:
      cpu.pc + 2 + offset - 0x100

  if mode == absoluteX and pagesDiffer(adr - cpu.x, adr) or
     mode in {absoluteY, indirectIndexed} and pagesDiffer(adr - cpu.y, adr):
    cpu.cycles += instructionPageCycles[opcode]

  cpu.pc += instructionSizes[opcode]
  cpu.cycles += instructionCycles[opcode]

  let info = StepInfo(address: adr, pc: cpu.pc, mode: mode)
  instructions[opcode](cpu, info)

  result = int(cpu.cycles - cycles)
