#!/bin/bash
# arm64 stand-in for versioner: usage: versioner -o OUT IN DEPS
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2;; -*) shift;; *) break;; esac; done
mkdir -p "$out"; cp -rL "$1"/. "$out"/
