project('eagleemu', 'c',
  version: '1.0',
  default_options: [
    'c_std=gnu99',
    'warning_level=2',
    'buildtype=debugoptimized',
  ]
)

cc = meson.get_compiler('c')

dep_sdl2 = dependency('sdl2')
dep_sdl2_ttf = dependency('SDL2_ttf')
dep_sdl2_mixer = dependency('SDL2_mixer')
dep_m = cc.find_library('m', required: false)
dep_ncurses = cc.find_library('ncurses')
dep_saasound = cc.find_library('SAASound', dirs: '/usr/local/lib')

add_project_arguments(
  '-fno-omit-frame-pointer',
  language: 'c',
)

sources = files(
  'src/8255.c',
  'src/cpu.c',
  'src/gfx.c',
  'src/keyb.c',
  'src/main.c',
  'src/saa1099_ext.c',
  'src/sd.c',
  'src/serial.c',
)

executable('eagleemu', sources,
  dependencies: [
    dep_sdl2,
    dep_sdl2_ttf,
    dep_sdl2_mixer,
    dep_m,
    dep_ncurses,
    dep_saasound,
  ],
  install: false,
)
