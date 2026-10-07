#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup_verilator.sh - build the open-source toolchain used by `make SIM=verilator`.
#
# What it does (the same steps used to produce the results in README.md):
#   1. builds Verilator from the master branch of github.com/verilator/verilator
#      (UVM 2020.3 support and covergroups need a recent 5.x; distro packages
#      such as Ubuntu 24.04's 5.020 are far too old),
#   2. clones the Verilator-compatible UVM library from
#      github.com/chipsalliance/uvm-verilator into third_party/.
#
# Prerequisites (Ubuntu/Debian):
#   sudo apt-get install git make autoconf g++ flex bison libfl-dev help2man \
#                        perl python3 zlib1g-dev libgoogle-perftools-dev z3
# (z3 is the constraint solver Verilator uses for randomize() with
#  constraints; it must be on PATH when ./configure runs.)
#
# Usage:
#   ./setup_verilator.sh [install_prefix]       # default: ../third_party/verilator
#   export VERILATOR_ROOT=<prefix>/src-tree; export PATH=$VERILATOR_ROOT/bin:$PATH
#
# Build time: roughly 10-20 minutes on 2 cores.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

TP=third_party
VL_SRC="${1:-$TP/verilator}"
mkdir -p "$TP"

command -v z3 >/dev/null || echo "WARNING: z3 not found; constrained randomize() will not work"

if [ ! -d "$VL_SRC" ]; then
  git clone --depth 1 https://github.com/verilator/verilator.git "$VL_SRC"
fi
(
  cd "$VL_SRC"
  autoconf
  ./configure
  # Only the optimized binaries are needed; this skips the debug build.
  make -j"$(nproc)" -C src opt
)

if [ ! -d "$TP/uvm-verilator" ]; then
  git clone --depth 1 https://github.com/chipsalliance/uvm-verilator.git "$TP/uvm-verilator"
fi

ROOT="$(cd "$VL_SRC" && pwd)"
echo
echo "Done. Use it with:"
echo "  export VERILATOR_ROOT=$ROOT"
echo "  export PATH=\$VERILATOR_ROOT/bin:\$PATH"
echo "  cd sim && make SIM=verilator regress"
