import types, unsigned

export types.Controller, types.Buttons

proc read*(c: var Controller): uint8 =
  if c.index < 8 and c.buttons[c.index]:
    result = 1
  inc c.index
  if (c.strobe and 1) == 1:
    c.index = 0

proc write*(c: var Controller, val: uint8) =
  c.strobe = val
  if (c.strobe and 1) == 1:
    c.index = 0

proc setButtons*(c: var Controller, buttons: Buttons) =
  c.buttons = buttons
