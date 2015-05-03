import nes, os, times, sdl2, sdl2.audio, sdl2.joystick

when defined(emscripten):
  proc emscripten_set_main_loop(fun: proc() {.cdecl.}, fps,
    simulate_infinite_loop: cint) {.header: "<emscripten.h>".}

  proc emscripten_cancel_main_loop() {.header: "<emscripten.h>".}

  # Currently not working with SDL 2.0.4 from repo
  #proc queueAudio(dev: AudioDeviceID, data: pointer, len: uint32) {.
  #  header: "<SDL2/SDL.h>", importc: "SDL_QueueAudio".}

  #proc getQueuedAudioSize(dev: AudioDeviceID): uint32 {.
  #  header: "<SDL2/SDL.h>", importc: "SDL_GetQueuedAudioSize".}
else:
  const samples = 2048

  proc callback(userdata: pointer, stream: ptr uint8, len: cint) {.cdecl.} =
    # Could be a lot nicer with SDL_QueueAudio, but it's SDL >= 2.0.4, which
    # isn't released yet. Don't want to use yet another library.
    let nes = cast[ptr NES](userdata)
    let elems = len div sizeof(float32)
    if nes.apu.chanPos >= elems:
      let rest = nes.apu.chanPos - elems
      copyMem(stream, addr nes.apu.chan[0], len)
      moveMem(addr nes.apu.chan[0], addr nes.apu.chan[elems], rest * sizeof(float32))
      nes.apu.chanPos = rest
    else: # Audio has to be zeroed since SDL2
      zeroMem(stream, len)

const keys = [
  [SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_SPACE,
   SDL_SCANCODE_RETURN, SDL_SCANCODE_UP, SDL_SCANCODE_DOWN,
   SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT],
  # TODO: Player 2
  [SDL_SCANCODE_UNKNOWN, SDL_SCANCODE_UNKNOWN, SDL_SCANCODE_UNKNOWN,
   SDL_SCANCODE_UNKNOWN, SDL_SCANCODE_UNKNOWN, SDL_SCANCODE_UNKNOWN,
  SDL_SCANCODE_UNKNOWN, SDL_SCANCODE_UNKNOWN]
]

let pitch = cint(resolution.x * sizeof(Color))

var
  controllers: array[2, JoystickPtr]
  nesConsole: NES

try:
  when defined(android):
    # TODO: Proper Android support, this just shows a video of a single game
    nesConsole = newNES("smb3.nes")
  else:
    if paramCount() != 1:
      quit "Usage: nimes <rom.nes>"
    else:
      nesConsole = newNES(paramStr(1))
except:
  quit getCurrentExceptionMsg()

when defined(emscripten):
  const
    inits = INIT_VIDEO # or INIT_AUDIO
    windowProps = SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL
    title = nil # Keep website title
else:
  const
    inits = INIT_EVERYTHING
    windowProps = SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE
    title = "NimES"

if not sdl2.init(inits):
  raise newException(SystemError, "SDL2 initialization failed")

discard setHint("SDL_RENDER_SCALE_QUALITY", "0")

discard joystickEventState(SDL_ENABLE)

let
  window = createWindow(title, SDL_WINDOWPOS_CENTERED,
    SDL_WINDOWPOS_CENTERED, resolution.x, resolution.y, windowProps)

  renderer = createRenderer(window, -1,
    Renderer_Accelerated or Renderer_PresentVsync or Renderer_TargetTexture)

  texture = renderer.createTexture(SDL_PIXELFORMAT_ABGR8888,
    SDL_TEXTUREACCESS_STREAMING, resolution.x, resolution.y)

# auto-scaling and letterboxing
discard renderer.setLogicalSize(resolution.x, resolution.y)
discard showCursor(false)

#when defined(emscripten):
#  var
#    want = AudioSpec(freq: 44100, format: AUDIO_F32, channels: 1)
#else:
when not defined(emscripten):
  var
    want = AudioSpec(freq: 44100, format: AUDIO_F32, channels: 1, samples: samples,
      callback: callback, userdata: addr nesConsole)
    have = AudioSpec()

  let audioDevice = openAudioDevice(nil, 0, addr want, addr have, 0)
  audioDevice.pauseAudioDevice(0)

var
  runGame = true
  evt = defaultEvent
  buttons: array[2, Buttons]
  time = epochTime()
  speed = 1.0
  paused = false
  hidden = false
  muted = false

template setButton(e, val) =
  for player in 0..1:
    let button = keys[player].find(e.keysym.scancode)
    if button > -1:
      buttons[player][button] = val

proc loop {.cdecl.} =
  when defined(emscripten):
    if not runGame:
      emscripten_cancel_main_loop()

  if hidden:
    let newTime = epochTime()
    sleep(milsecs = max(0, int(16 - (newTime - time) * 1000)))

  if not paused:
    nesConsole.controllers[0].setButtons(buttons[0])
    nesConsole.controllers[1].setButtons(buttons[1])

    let newTime = epochTime()

    # Skip unreaonable time differences. Workaround for emscripten
    if newTime - time < 1:
      nesConsole.run((newTime - time) * speed)
    time = newTime

    if muted:
      nesConsole.apu.chanPos = 0

    texture.updateTexture(nil, addr nesConsole.buffer[], pitch)

    #when defined(emscripten):
    #  audioDevice.queueAudio(addr nesConsole.apu.chan[0], uint32(nesConsole.apu.chanPos * sizeof(float32)))
    #  nesConsole.apu.chanPos = 0

  if not hidden:
    renderer.clear()
    renderer.copy(texture, nil, nil)
    renderer.present()

  joystickUpdate()
  while pollEvent(evt):
    case evt.kind
    of QuitEvent:
      runGame = false
      break
    of KeyDown:
      let e = evt.key()

      case e.keysym.scancode
      of SDL_SCANCODE_1..SDL_SCANCODE_5:
        let factor = e.keysym.scancode.cint - SDL_SCANCODE_1.cint + 1
        window.setSize(resolution.x * factor, resolution.y * factor)
      of SDL_SCANCODE_P:
        paused = not paused
        time = epochTime()
        when not defined(emscripten):
          if not muted:
            audioDevice.pauseAudioDevice(paused.cint)
      of SDL_SCANCODE_M:
        muted = not muted
        when not defined(emscripten):
          audioDevice.pauseAudioDevice(muted.cint)
      of SDL_SCANCODE_R:   nesConsole.reset()
      of SDL_SCANCODE_F:   speed = 2.5
      of SDL_SCANCODE_F9:  speed = 1.0
      of SDL_SCANCODE_F10: speed = max(speed - 0.05, 0.05)
      of SDL_SCANCODE_F11: speed = min(speed + 0.05, 2.5)
      of SDL_SCANCODE_Y:   buttons[0][0] = true # Workaround for emscripten
      else:                setButton e, true
    of KeyUp:
      let e = evt.key()

      case e.keysym.scancode
      of SDL_SCANCODE_F:   speed = 1.0
      of SDL_SCANCODE_Y:   buttons[0][0] = false
      else:                setButton e, false
    of JoyDeviceAdded:
      let e = evt.jdevice()
      if e.which < 2:
        controllers[e.which] = joystickOpen(e.which)
    of JoyDeviceRemoved:
      let e = evt.jdevice()
      if e.which < 2:
        controllers[e.which].joystickClose()
    of JoyButtonDown:
      let e = evt.jbutton()
      case e.button # TODO: Proper, configurable joystick support
      of 0: buttons[e.which][0] = true
      of 1: buttons[e.which][1] = true
      of 8: buttons[e.which][2] = true
      of 9: buttons[e.which][3] = true
      else: discard
    of JoyButtonUp:
      let e = evt.jbutton()
      case e.button
      of 0: buttons[e.which][0] = false
      of 1: buttons[e.which][1] = false
      of 8: buttons[e.which][2] = false
      of 9: buttons[e.which][3] = false
      else: discard
    #of JoyAxisMotion:
    #  let e = evt.jaxis()
    of JoyHatMotion:
      let e = evt.jhat()
      buttons[e.which][4] = (e.value and 1) != 0
      buttons[e.which][7] = (e.value and 2) != 0
      buttons[e.which][5] = (e.value and 4) != 0
      buttons[e.which][6] = (e.value and 8) != 0
    of WindowEvent:
      let e = evt.window()
      case e.event
      of WindowEvent_Hidden, WindowEvent_Minimized: hidden = true
      of WindowEvent_Shown, WindowEvent_Restored  : hidden = false
      else: discard
    else: discard

try:
  when defined(emscripten):
    emscripten_set_main_loop(loop, 0, 1)
  else:
    while runGame:
      loop()
except:
  quit getCurrentExceptionMsg()

when not defined emscripten:
  audioDevice.closeAudioDevice()
sdl2.quit()

when defined(android):
  {.emit: """
  #include <SDL_main.h>

  extern int cmdCount;
  extern char** cmdLine;
  extern char** gEnv;

  N_CDECL(void, NimMain)(void);

  int main(int argc, char** args) {
      cmdLine = args;
      cmdCount = argc;
      gEnv = NULL;
      NimMain();
      return nim_program_result;
  }

  """.}
