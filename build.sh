#!/bin/sh
# Build YANC.SYSTEM and the YANC.po disk image (needs cc65: ca65/ld65 in PATH)
set -e
cd "$(dirname "$0")"
mkdir -p build release
ca65 --cpu 65C02 -g -l build/yanc.lst src/yanc.s -o build/yanc.o
ld65 -C src/yanc.cfg -m build/yanc.map -Ln build/yanc.lbl build/yanc.o -o release/YANC.SYSTEM
(cd release && python3 ../tools/mkpo.py YANC.po)
ls -l release
