import nake
import os

task "desktop", "Builds NimES for Desktop":
  shell "nim -d:release c src/nimes"

task "web", "Builds NimES for the Web":
  shell "nim -d:release -d:emscripten c src/nimes"

task "android", "Builds NimES for Android":
  shell "nim -d:release -d:android c src/nimes"
  shell "cd android && ndk-build"
  shell "cd android && ant debug"

task "clean", "Removes build files":
  removeDir "nimcache"
  removeDir "src/nimcache"

  removeFile "src/nimes"
  removeFile "src/nimes.js"
  removeFile "src/nimes.html"
  removeFile "src/nimes.html.mem"
  removeFile "src/nimes.data"

  removeDir "android/bin"
  removeDir "android/gen"
  removeDir "android/libs"
  removeDir "android/obj"
  for file in walkFiles "android/jni/src/*.c":
    removeFile file
