# -----------------------------------------------------------------------------
# Makefile - async FIFO UVM testbench
#
# Usage (from sim/):
#   make SIM=verilator TEST=fifo_smoke_test            # build + run one test
#   make SIM=verilator regress                         # all tests, summary
#   make SIM=questa    TEST=fifo_random_test SEED=7
#   make SIM=vcs       TEST=fifo_clock_ratio_test
#   make SIM=xcelium   TEST=fifo_reset_test
#   make lint                                          # Verilator -Wall on RTL
#   make coverage                                      # merge + summarize (Verilator)
#   make clean
#
# Variables:
#   SIM        verilator | questa | vcs | xcelium        (default verilator)
#   TEST       UVM test name                            (default fifo_smoke_test)
#   SEED       random seed                              (default 1)
#   VERBOSITY  UVM_NONE/LOW/MEDIUM/HIGH/DEBUG           (default UVM_LOW)
#   WCLK_PS / RCLK_PS   clock periods in ps (optional; tb default 10000/13000)
#   DUMP=1     dump waves (waves.vcd)
#   PLUSARGS   extra run-time plusargs
#   DATA_WIDTH / ADDR_WIDTH   DUT configuration (compile time)
#
#   UVM_HOME   Verilator flow only: path to a Verilator-compatible UVM source
#              tree (the 'src' directory of github.com/chipsalliance/uvm-verilator).
#              Commercial simulators use their bundled UVM.
# -----------------------------------------------------------------------------

SIM        ?= verilator
TEST       ?= fifo_smoke_test
SEED       ?= 1
VERBOSITY  ?= UVM_LOW
DATA_WIDTH ?= 8
ADDR_WIDTH ?= 4
UVM_HOME   ?= $(CURDIR)/../third_party/uvm-verilator/src

BUILD_DIR  := build/$(SIM)
LOG_DIR    := logs
FILELIST   := files.f
DEFINES    := +define+FIFO_DATA_WIDTH=$(DATA_WIDTH) +define+FIFO_ADDR_WIDTH=$(ADDR_WIDTH)

RUN_ARGS   := +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) +UVM_NO_RELNOTES
RUN_ARGS   += $(if $(WCLK_PS),+WCLK_PERIOD_PS=$(WCLK_PS))
RUN_ARGS   += $(if $(RCLK_PS),+RCLK_PERIOD_PS=$(RCLK_PS))
RUN_ARGS   += $(if $(DUMP),+DUMP)
RUN_ARGS   += $(PLUSARGS)

LOG        := $(LOG_DIR)/$(TEST)_$(SEED).log

TESTS := fifo_smoke_test \
         fifo_random_test \
         fifo_full_empty_test \
         fifo_overflow_underflow_test \
         fifo_simul_rw_test \
         fifo_clock_ratio_test \
         fifo_reset_test

.PHONY: all build run regress lint clean help uvm-verilator coverage

all: run

help:
	@sed -n '2,30p' Makefile

# -----------------------------------------------------------------------------
# Verilator (5.x, built with UVM support; see README "Open-source flow")
#   --timing          : delays, clocking blocks, fork/join in the TB
#   --assert          : enable SVA
#   --coverage-user   : covergroups + cover properties -> coverage.dat
#   --vpi + uvm_dpi.cc: UVM DPI (command line processing, regex, HDL access)
# Verilator has no built-in random seed plusarg handling for the UVM path;
# +verilator+seed+<n> seeds the process RNG used by $urandom/randomize().
# -----------------------------------------------------------------------------
VERILATOR       ?= verilator
VERILATOR_FLAGS := --binary -j 0 --timing --assert --coverage-user --vpi \
                   --timescale 1ns/1ps --top-module tb_top \
                   -Wno-fatal -Wno-lint -Wno-style

ifeq ($(SIM),verilator)
build: $(BUILD_DIR)/Vtb_top

$(BUILD_DIR)/Vtb_top: $(FILELIST) $(wildcard ../rtl/*.sv ../tb/*/*.sv ../tb/*/*.svh ../tb/*/*/*.sv ../tb/*/*/*.svh)
	@test -f $(UVM_HOME)/uvm_pkg.sv || { echo "UVM_HOME=$(UVM_HOME) has no uvm_pkg.sv; run 'make uvm-verilator' or set UVM_HOME"; exit 1; }
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -Mdir $(BUILD_DIR) $(DEFINES) \
	  +incdir+$(UVM_HOME) $(UVM_HOME)/uvm_pkg.sv $(UVM_HOME)/dpi/uvm_dpi.cc \
	  -f $(FILELIST)

# The model writes coverage.dat to the current directory; each run gets its own
# file so results can be merged later with verilator_coverage.
run: build | $(LOG_DIR)
	./$(BUILD_DIR)/Vtb_top $(RUN_ARGS) +verilator+seed+$(SEED) \
	  +verilator+coverage+file+$(LOG_DIR)/$(TEST)_$(SEED).coverage.dat 2>&1 | tee $(LOG)

# Merge all coverage.dat files from logs/ and print a covergroup summary.
coverage:
	verilator_coverage --write $(LOG_DIR)/merged.coverage.dat $(LOG_DIR)/*.coverage.dat
	python3 cov_report.py $(LOG_DIR)/merged.coverage.dat
endif

# -----------------------------------------------------------------------------
# Commercial simulators. All three ship UVM; the flows below use the bundled
# library. These targets are provided for convenience and have NOT been run by
# the author in this repository's CI (see README "What was actually run").
# All tools run from sim/ so the relative paths in files.f resolve.
# -----------------------------------------------------------------------------

# Questa: vlog finds the bundled uvm_pkg / uvm_macros.svh automatically in
# current releases; set QUESTA_UVM_INC if your install needs an explicit path.
QUESTA_UVM_INC ?=
ifeq ($(SIM),questa)
build: | $(BUILD_DIR)
	vlib $(BUILD_DIR)/work
	vlog -sv -timescale 1ns/1ps -work $(BUILD_DIR)/work $(DEFINES) \
	  $(if $(QUESTA_UVM_INC),+incdir+$(QUESTA_UVM_INC)) -f $(FILELIST)
	vopt -work $(BUILD_DIR)/work tb_top -o tb_top_opt +cover=bcesf $(if $(DUMP),+acc)

run: build | $(LOG_DIR)
	vsim -c -lib $(BUILD_DIR)/work tb_top_opt -sv_seed $(SEED) -coverage \
	  $(RUN_ARGS) -do "coverage save -onexit $(LOG_DIR)/$(TEST)_$(SEED).ucdb; run -all; quit -f" \
	  2>&1 | tee $(LOG)
endif

# Synopsys VCS
ifeq ($(SIM),vcs)
build: | $(BUILD_DIR)
	vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps -assert svaext \
	  -cm line+cond+fsm+tgl+assert -cm_dir $(BUILD_DIR)/simv.vdb \
	  -Mdir=$(BUILD_DIR)/csrc $(DEFINES) -f $(FILELIST) -top tb_top -o $(BUILD_DIR)/simv

run: build | $(LOG_DIR)
	$(BUILD_DIR)/simv +ntb_random_seed=$(SEED) -cm line+cond+fsm+tgl+assert \
	  -cm_name $(TEST)_$(SEED) $(RUN_ARGS) 2>&1 | tee $(LOG)
endif

# Cadence Xcelium
ifeq ($(SIM),xcelium)
build: | $(BUILD_DIR)
	xrun -elaborate -64bit -uvm -sv -timescale 1ns/1ps -access +r -coverage all \
	  -xmlibdirpath $(BUILD_DIR) $(DEFINES) -f $(FILELIST) -top tb_top

run: build | $(LOG_DIR)
	xrun -R -64bit -xmlibdirpath $(BUILD_DIR) -svseed $(SEED) -covtest $(TEST)_$(SEED) \
	  $(RUN_ARGS) 2>&1 | tee $(LOG)
endif

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -----------------------------------------------------------------------------
regress:
	./run_regression.sh --sim $(SIM)

lint:
	$(VERILATOR) --lint-only -Wall --top-module fifo_top \
	  ../rtl/fifo_mem.sv ../rtl/sync_r2w.sv ../rtl/sync_w2r.sv \
	  ../rtl/wptr_full.sv ../rtl/rptr_empty.sv ../rtl/fifo_top.sv

# Fetch the Verilator-compatible UVM library used by the open-source flow.
uvm-verilator:
	mkdir -p ../third_party
	test -d ../third_party/uvm-verilator || \
	  git clone --depth 1 https://github.com/chipsalliance/uvm-verilator.git ../third_party/uvm-verilator

$(LOG_DIR):
	mkdir -p $(LOG_DIR)

clean:
	rm -rf build logs work transcript *.wlf *.ucdb *.vcd *.fst csrc simv* xcelium.d xrun.* *.key
