cmake_minimum_required(VERSION 3.13)

file(GLOB TRIGCONFFILE "media-mux-trighappy.conf")
install(FILES ${TRIGCONFFILE} DESTINATION etc/triggerhappy/triggers.d/)

file(GLOB  EVNTSCRIPT "*.sh")
install(PROGRAMS ${EVNTSCRIPT} DESTINATION usr/sbin/)
