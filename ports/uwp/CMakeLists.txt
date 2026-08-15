cmake_minimum_required(VERSION 3.24)
project(Gen2RecompedUWP LANGUAGES CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(FATAL_ERROR "Configure with a WindowsStore preset.")
endif()

get_filename_component(GAME_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(THIRD_PARTY_ROOT "${CMAKE_CURRENT_LIST_DIR}/third_party")
set(LOVE_ROOT "${THIRD_PARTY_ROOT}/love")
set(SDL2_ROOT "${THIRD_PARTY_ROOT}/sdl2")
set(ANGLE_ROOT "${THIRD_PARTY_ROOT}/angle")
set(RUNTIME_ROOT "${THIRD_PARTY_ROOT}/runtime")

set(GEN2RECOMPED_VERSION "0.0.0" CACHE STRING "Gen2Recomped release version")
if(NOT GEN2RECOMPED_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "GEN2RECOMPED_VERSION must use X.Y.Z format.")
endif()
string(REPLACE "." ";" VERSION_PARTS "${GEN2RECOMPED_VERSION}")
foreach(part IN LISTS VERSION_PARTS)
    if(part GREATER 65535)
        message(FATAL_ERROR "MSIX version components cannot exceed 65535.")
    endif()
endforeach()
set(GEN2RECOMPED_UWP_PUBLISHER "CN=Gen2Recomped" CACHE STRING
    "Publisher subject from the MSIX signing certificate")
set(UWP_PUBLISHER_XML "${GEN2RECOMPED_UWP_PUBLISHER}")
string(REPLACE "&" "&amp;" UWP_PUBLISHER_XML "${UWP_PUBLISHER_XML}")
string(REPLACE "\"" "&quot;" UWP_PUBLISHER_XML "${UWP_PUBLISHER_XML}")
string(REPLACE "<" "&lt;" UWP_PUBLISHER_XML "${UWP_PUBLISHER_XML}")
string(REPLACE ">" "&gt;" UWP_PUBLISHER_XML "${UWP_PUBLISHER_XML}")
set(UWP_PACKAGE_VERSION "${GEN2RECOMPED_VERSION}.0")
set(PACKAGE_MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/Package.appxmanifest")
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/Package.appxmanifest.in"
    "${PACKAGE_MANIFEST}"
    @ONLY
)

set(REQUIRED_FILES
    "${THIRD_PARTY_ROOT}/manifest.json"
    "${LOVE_ROOT}/lib/lovestatic.lib"
    "${LOVE_ROOT}/lib/liblove.lib"
    "${LOVE_ROOT}/lib/lua51.lib"
    "${LOVE_ROOT}/bin/love.dll"
    "${LOVE_ROOT}/bin/lua51.dll"
    "${SDL2_ROOT}/include/SDL2/SDL.h"
    "${SDL2_ROOT}/lib/SDL2.lib"
    "${SDL2_ROOT}/bin/SDL2.dll"
    "${ANGLE_ROOT}/bin/libEGL.dll"
    "${ANGLE_ROOT}/bin/libGLESv2.dll"
    "${ANGLE_ROOT}/bin/d3dcompiler_47.dll"
)
foreach(path IN LISTS REQUIRED_FILES)
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "Missing UWP dependency: ${path}")
    endif()
endforeach()

set(GEN2RECOMPED_LOVE "${GAME_ROOT}/.bazinga/work/game.love" CACHE FILEPATH
    "Path to the game.love payload produced by scripts/pack_love.sh")
if(NOT EXISTS "${GEN2RECOMPED_LOVE}")
    message(FATAL_ERROR
        "Missing game.love payload: ${GEN2RECOMPED_LOVE}\n"
        "Build it with scripts/build_xbox_uwp.sh or scripts/pack_love.sh.")
endif()

set(GAME_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/gen2recomp.love")
add_custom_command(
    OUTPUT "${GAME_ARCHIVE}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${GEN2RECOMPED_LOVE}" "${GAME_ARCHIVE}"
    DEPENDS "${GEN2RECOMPED_LOVE}"
    VERBATIM
)
add_custom_target(gen2recomp_love ALL DEPENDS "${GAME_ARCHIVE}")
set_source_files_properties("${GAME_ARCHIVE}" PROPERTIES GENERATED TRUE)

add_custom_target(verify_uwp_dependencies
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
        "${GAME_ROOT}/scripts/xbox-uwp/verify_dependencies.ps1"
    VERBATIM
)

add_executable(${PROJECT_NAME} WIN32 "app/main.cpp")
add_dependencies(${PROJECT_NAME} gen2recomp_love verify_uwp_dependencies)
set_target_properties(${PROJECT_NAME} PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    VS_GLOBAL_DefaultLanguage "en-US"
    VS_SDK_REFERENCES "Microsoft.VCLibs, Version=14.0"
)
target_include_directories(${PROJECT_NAME} PRIVATE "${SDL2_ROOT}/include/SDL2")
target_link_libraries(${PROJECT_NAME} PRIVATE
    "${LOVE_ROOT}/lib/lovestatic.lib"
    "${LOVE_ROOT}/lib/liblove.lib"
    "${SDL2_ROOT}/lib/SDL2.lib"
    "${LOVE_ROOT}/lib/lua51.lib"
    WindowsApp.lib
)

set(PACKAGE_ROOT_FILES
    "${PACKAGE_MANIFEST}"
    "${GAME_ARCHIVE}"
    "${LOVE_ROOT}/bin/love.dll"
    "${LOVE_ROOT}/bin/lua51.dll"
    "${SDL2_ROOT}/bin/SDL2.dll"
    "${ANGLE_ROOT}/bin/libEGL.dll"
    "${ANGLE_ROOT}/bin/libGLESv2.dll"
    "${ANGLE_ROOT}/bin/d3dcompiler_47.dll"
)
set_source_files_properties("${PACKAGE_MANIFEST}" PROPERTIES GENERATED TRUE)

set(RUNTIME_NAMES
    brotlicommon.dll brotlidec.dll bz2.dll fmt.dll freetype.dll libpng16.dll
    OpenAL32.dll theora.dll theoradec.dll vorbis.dll vorbisfile.dll ogg.dll z.dll
)
foreach(name IN LISTS RUNTIME_NAMES)
    set(runtime "${RUNTIME_ROOT}/bin/${name}")
    if(NOT EXISTS "${runtime}")
        message(FATAL_ERROR "Missing UWP runtime DLL: ${name}")
    endif()
    list(APPEND PACKAGE_ROOT_FILES "${runtime}")
endforeach()

set_source_files_properties(${PACKAGE_ROOT_FILES} PROPERTIES
    VS_COPY_TO_OUT_DIR Always
    VS_DEPLOYMENT_CONTENT TRUE
    VS_DEPLOYMENT_LOCATION "."
)

file(GLOB PACKAGE_ASSETS CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/Assets/*.png")
set_source_files_properties(${PACKAGE_ASSETS} PROPERTIES
    VS_DEPLOYMENT_CONTENT TRUE
    VS_DEPLOYMENT_LOCATION "Assets"
)

file(GLOB PACKAGE_LICENSES CONFIGURE_DEPENDS "${THIRD_PARTY_ROOT}/licenses/*.txt")
set_source_files_properties(${PACKAGE_LICENSES} PROPERTIES
    VS_TOOL_OVERRIDE "Content"
    VS_COPY_TO_OUT_DIR Always
    VS_DEPLOYMENT_CONTENT TRUE
    VS_DEPLOYMENT_LOCATION "licenses"
)
target_sources(${PROJECT_NAME} PRIVATE
    ${PACKAGE_ROOT_FILES}
    ${PACKAGE_ASSETS}
    ${PACKAGE_LICENSES}
)
