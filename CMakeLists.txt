cmake_minimum_required(VERSION 3.10)
project(eagleemu C)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Compiler flags
add_compile_options(-Wall)

# Find pkg-config first
find_package(PkgConfig REQUIRED)

# Use pkg-config to find SDL2 and related libraries
pkg_check_modules(SDL2 REQUIRED sdl2)
pkg_check_modules(SDL2_ttf REQUIRED SDL2_ttf)
pkg_check_modules(SDL2_mixer REQUIRED SDL2_mixer)

# Source files
set(SOURCES
    8255.c
    cpu.c
    gfx.c
    keyb.c
    main.c
    saa1099_ext.c
    sd.c
    serial.c
)

# Header files
set(HEADERS
    8255.h
    cpu.h
    gfx.h
    keyb.h
    saa1099_ext.h
    sd.h
    serial.h
)

# Create executable
add_executable(eagleemu ${SOURCES})

# Include directories
target_include_directories(eagleemu PRIVATE 
    ${SDL2_INCLUDE_DIRS}
    ${SDL2_ttf_INCLUDE_DIRS}
    ${SDL2_mixer_INCLUDE_DIRS}
)

# Link libraries
target_link_libraries(eagleemu 
    PRIVATE
    ${SDL2_LIBRARIES}
    ${SDL2_ttf_LIBRARIES}
    ${SDL2_mixer_LIBRARIES}
    m
    SAASound
    ncurses
)

# Add /usr/local/lib to library search path
link_directories(/usr/local/lib)

# Debug build settings
set(CMAKE_C_FLAGS_DEBUG "-O2 -ggdb -fno-omit-frame-pointer")

# Release build settings
set(CMAKE_C_FLAGS_RELEASE "-O2 -s")

# Set output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_BINARY_DIR}/bin/Debug)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/bin/Release)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_DEBUG ${CMAKE_BINARY_DIR}/obj/Debug)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/obj/Release)
