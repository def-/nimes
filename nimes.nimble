# Package

version       = "0.1"
author        = "Dennis Felsing"
description   = "NimES: NES Emulator in Nim"
license       = "MIT"

srcDir        = "src"
bin           = @["nimes"]
skipExt       = @["nim"]

# Dependencies

requires "nim >= 0.12.0"
requires "sdl2 >= 1.0"
