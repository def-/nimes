import nes

# TODO: State of Cartridge and Mapper is missing, a bit ugly to add

const rewindSize = 600

type Rewinder* = ref object
  states: array[rewindSize, NESObj]
  pos: int
  stored: int

proc newRewinder*: Rewinder =
  new result

proc empty*(r: Rewinder): bool =
  r.stored == 0

proc pop*(r: var Rewinder): NESObj = # This may be slow and need a popInto()
  r.pos = (r.pos + rewindSize - 1) mod rewindSize
  copyMem(addr result, addr r.states[r.pos], sizeof(result))
  r.stored = max(r.stored - 1, 0)

proc push*(r: var Rewinder, c: var NESObj) =
  copyMem(addr r.states[r.pos], addr c, sizeof(c))
  r.pos = (r.pos + 1) mod rewindSize
  r.stored = min(r.stored + 1, rewindSize)
