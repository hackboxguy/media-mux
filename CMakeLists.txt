cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME media-mux)
project(${PROJECT_NAME})
add_subdirectory(trighappy)

file(GLOB  ACT_SCR "media-mux-action*")
install(PROGRAMS ${ACT_SCR} DESTINATION usr/bin)

file(GLOB  PLAY_SCR "media-mux-play*")
install(PROGRAMS ${PLAY_SCR} DESTINATION usr/bin)

file(GLOB  VOL_SCR "media-mux-volume*")
install(PROGRAMS ${VOL_SCR} DESTINATION usr/bin)

file(GLOB  FRZ_SCR "media-mux-frozen-frame*")
install(PROGRAMS ${FRZ_SCR} DESTINATION usr/bin)
