# Gen2Recomped PS5: a static SDL2 for LOVE in a native PS5 title.
#
# SDL 2.30.12 from ps5-payload-dev/SDL (scripts/ps5/deps.sh pins the commit),
# with its OSMesa video driver swapped for ps5-opengl's SDL2 video driver
# ("G19", integration/SDL2/SDL_ps5g19.c, patched by g19-love.patch so any
# window LOVE asks for becomes the fixed scanout size). Adapted from that
# integration's CMakeLists.txt, with two differences: SDL's PS5 audio driver
# (SceAudioOut) stays on, because OpenAL Soft plays through SDL audio here, and
# the game-controller layer stays on for love.joystick's gamepad API.
#
# Configured by scripts/ps5/build_runtime.sh with the payload SDK's
# prospero-cmake (toolchain/prospero.cmake sets PS5 and FreeBSD).
cmake_minimum_required(VERSION 3.16)
project(G2RSDL2 C)

if(NOT SDL_SOURCE OR NOT G19_SOURCE OR NOT PS5_OPENGL_PREFIX)
    message(FATAL_ERROR "set SDL_SOURCE, G19_SOURCE and PS5_OPENGL_PREFIX")
endif()

set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_STATIC_PIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_VIRTUAL_JOYSTICK OFF CACHE BOOL "" FORCE)
set(SDL_HIDAPI OFF CACHE BOOL "" FORCE)
set(SDL_HIDAPI_JOYSTICK OFF CACHE BOOL "" FORCE)
set(SDL_PTHREADS ON CACHE BOOL "" FORCE)
set(SDL2_DISABLE_SDL2MAIN ON CACHE BOOL "" FORCE)
set(SDL_AUDIO ON CACHE BOOL "" FORCE)
set(SDL_JOYSTICK ON CACHE BOOL "" FORCE)
# OPENGL stays OFF at SDL's level: the G19 driver defines SDL_VIDEO_OPENGL for
# itself and talks to ps5-opengl's EGL directly (static, no dlopen).
foreach(feature RENDER HAPTIC SENSOR OPENGL OPENGLES VULKAN X11 WAYLAND KMSDRM
                OFFSCREEN JACK PULSEAUDIO DBUS IBUS FCITX LIBUDEV LIBSAMPLERATE)
    set(SDL_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
# The title's libc does not export these; use SDL's own fallbacks.
foreach(symbol WCSLCPY WCSLCAT WCSCASECMP WCSNCASECMP)
    set(HAVE_${symbol} 0 CACHE INTERNAL "native libc contract" FORCE)
endforeach()

add_subdirectory("${SDL_SOURCE}" sdl)

get_target_property(sources SDL2-static SOURCES)
list(FILTER sources EXCLUDE REGEX "/video/ps5/")
set_property(TARGET SDL2-static PROPERTY SOURCES "${sources}")
target_sources(SDL2-static PRIVATE "${G19_SOURCE}/SDL_ps5g19.c")
target_include_directories(SDL2-static PRIVATE "${SDL_SOURCE}/src" "${G19_SOURCE}"
                                               "${PS5_OPENGL_PREFIX}/include")
target_compile_definitions(SDL2-static PRIVATE SDL_VIDEO_DRIVER_PS5=1 SDL_VIDEO_OPENGL=1)
