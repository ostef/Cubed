@echo off

setlocal EnableDelayedExpansion

jai source/build.jai -import_dir ../modules/ %*
