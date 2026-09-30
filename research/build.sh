#!/bin/sh
# Build the WASM kernels (clang from the emscripten toolchain; any clang with the wasm32 target works)
set -e
CC=${CC:-/opt/homebrew/Cellar/emscripten/6.0.5/libexec/llvm/bin/clang}
cd "$(dirname "$0")"
$CC --target=wasm32 -O3 -msimd128 -nostdlib -Wl,--no-entry -Wl,--export-dynamic \
    -Wl,--initial-memory=67108864 -Wl,--max-memory=4294967296 -o bigmul.wasm src/bigmul.c
echo built bigmul.wasm
