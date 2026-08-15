# SDL2 UWP binaries

The bundled x64 UWP Release binaries use SDL 2.32.10 from the official `release-2.32.10` commit recorded in the dependency manifest. The rebuild script creates `source` and applies the WinRT only controller changes there.

`patches/xbox-wgi-controller.patch` records those changes for review. They read Xbox gamepads through `IGamepad::GetCurrentReading` and expose the standard SDL button, axis, trigger, and D-pad layout.

`SDL2.dll`, `SDL2.lib`, and the headers must be updated together.

`scripts/xbox-uwp/build_sdl2_angle.ps1` builds the source for x64 WindowsStore with GLES enabled and desktop OpenGL and Vulkan disabled. ANGLE supplies EGL and GLES at runtime.
