LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := main

SDL_PATH := ../SDL

LOCAL_C_INCLUDES := $(LOCAL_PATH)/$(SDL_PATH)/include

# Add your application source files here...
LOCAL_SRC_FILES := $(SDL_PATH)/src/main/android/SDL_android_main.c \
	 nimes_nimes.c nimes_apu.c nimes_cartridge.c nimes_controller.c nimes_cpu.c nimes_mapper1.c nimes_mapper2.c nimes_mapper3.c nimes_mapper4.c nimes_mapper7.c nimes_mapper.c nimes_mem.c nimes_nes.c nimes_ppu.c nimes_types.c sdl2_audio.c sdl2_joystick.c sdl2_sdl2.c stdlib_macros.c stdlib_os.c stdlib_parseutils.c stdlib_posix.c stdlib_strutils.c stdlib_system.c stdlib_times.c stdlib_unsigned.c nimbase.h

LOCAL_SHARED_LIBRARIES := SDL2

LOCAL_LDLIBS := -lGLESv1_CM -lGLESv2 -llog
LOCAL_CFLAGS += -O3

include $(BUILD_SHARED_LIBRARY)
