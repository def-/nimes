# NimES: NES emulator in Nim [![Build Status](https://circleci.com/gh/def-/nimes.png)](https://circleci.com/gh/def-/nimes)

This is a NES emulator written in the [Nim](http://nim-lang.org/) programming
language. I made it mainly for fun and demonstration purposes. Nim can be used
to write elegant and performant code and have it run almost anywhere, including
Android and JavaScript. You can build the emulator natively (should work on
Linux, Mac OS X, Windows and other platforms supporting SDL2), build it to
Android or use the [JavaScript](http://hookrace.net/nimes/) version that is
compiled from the same source code with the help of emscripten.

## [Live Demo](http://hookrace.net/nimes/)

![smb](https://cloud.githubusercontent.com/assets/2335377/7356197/e862d0ee-ed26-11e4-919a-55178873b7b3.gif) ![pacman](https://cloud.githubusercontent.com/assets/2335377/7356443/7bbd5fa2-ed28-11e4-8243-eb7d1316e371.gif) ![tetris](https://cloud.githubusercontent.com/assets/2335377/7357160/32fcd63a-ed2d-11e4-81fc-14fccb9aaa35.gif) ![smb3](https://cloud.githubusercontent.com/assets/2335377/7416215/1a3d03b2-ef5e-11e4-940f-49fa5ee47d44.gif)

## Building

You need [Nim 0.11](http://nim-lang.org/download.html) or [devel](https://github.com/Araq/Nim) and the SDL2 development libraries ([Windows, Mac OS X download](https://www.libsdl.org/download-2.0.php)) installed on your system:

    apt-get install libsdl2-dev # Ubuntu/Debian (wheezy-backports for Debian 7)
    homebrew install sdl2       # Mac OS X with homebrew
    yum install SDL2-devel      # Fedora/CentOS
    pacman -S sdl2              # Arch Linux
    emerge libsdl2              # Gentoo

With [nimble](https://github.com/nim-lang/nimble) installed you can then install NimES:

    nimble install nimes

There are a few possibilities to build NimES if you got the source already:

    nimble install # installs nimes into ~/.nimble/bin OR
    nimble build   # builds the binary in src/nimes OR
    nim -d:release c src/nimes # same without nimble

    $ nimes
    Usage: nimes <rom.nes>

If you don't want to use nimble, you'll have to get Nim's [SDL2
wrapper](https://github.com/nim-lang/sdl2) manually.

## Building with Emscripten

Building to JavaScript is a bit more complicated. You need the [Emscripten SDK](https://kripken.github.io/emscripten-site/docs/getting_started/downloads.html) installed.

    nim -d:release -d:emscripten c src/nimes

You need the files `tetris.nes, pacman.nes, smb.nes, smb3.nes` available for this.

## Building for Android

You need the Android SDK (12 or later) and NDK (7 or later) installed. So far NimES on Android only opens a predefined `smb3.nes` and controls don't even work. This is mainly to demonstrate that it could easily be ported to Android.

    nim -d:release -d:android c src/nimes
    cd android
    ndk-build
    ant debug

The resulting apk is in `bin/org.nimes-debug.apk`. You can try this [nimes.apk](http://hookrace.net/nimes/nimes.apk). Some work will be necessary to improve the performance of the program as well as implement Android controls.

Porting to Android was pretty simple by following [this guide](https://wiki.libsdl.org/Android).

## Controls

| Key   | Action                   |
| ----- | ------------------------ |
| ←↑↓→  | ←↑↓→                     |
| Z/Y   | A                        |
| X     | B                        |
| Enter | Start                    |
| Space | Select                   |
| 1-5   | Zoom 1-5×                |
| R     | Reset                    |
| P     | Pause                    |
| M     | Mute                     |
| F     | 250% speed while pressed |
| F9    | Reset speed              |
| F10   | Speed - 5%               |
| F11   | Speed + 5%               |

## TODO / What's missing

- Loading screen to select games (also in emscripten)
- Second player
- Settings for controls/gamepad/joystick
- Saving
- Android
- Performance could be improved significantly by making PPU render by scanline, not by pixel
- More mappers (0,1,2,3,4,7 working, [NES mapper list](http://tuxnes.sourceforge.net/nesmapper.txt))
- PAL video (NTSC only currently)

## Source code information

The NES emulation code largely follows fogleman's excellent [NES emulator in
Go](https://github.com/fogleman/nes) as well as these info materials and some
other emulators:

- http://www.obelisk.demon.co.uk/6502/
- http://nesdev.com/
