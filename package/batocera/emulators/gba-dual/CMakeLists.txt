cmake_minimum_required(VERSION 3.15)
project(gba-dual C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED sdl2)
find_path(MGBA_INCLUDE_DIR mgba/core/core.h REQUIRED)
find_library(MGBA_LIBRARY NAMES mgba REQUIRED)

add_executable(gba-dual main.c)
target_include_directories(gba-dual PRIVATE ${MGBA_INCLUDE_DIR} ${SDL2_INCLUDE_DIRS})
target_compile_options(gba-dual PRIVATE ${SDL2_CFLAGS_OTHER})
target_link_directories(gba-dual PRIVATE ${SDL2_LIBRARY_DIRS})
target_link_libraries(gba-dual PRIVATE ${MGBA_LIBRARY} ${SDL2_LIBRARIES} m)
install(TARGETS gba-dual RUNTIME DESTINATION bin)
