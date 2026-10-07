// -----------------------------------------------------------------------------
// files.f - compile list shared by all simulators (paths relative to sim/).
// The UVM library itself is added by the Makefile, per simulator.
// Order matters: packages before their users.
// -----------------------------------------------------------------------------
+incdir+../tb/common
+incdir+../tb/agents/write_agent
+incdir+../tb/agents/read_agent
+incdir+../tb/env
+incdir+../tb/seq
+incdir+../tb/tests

// RTL
../rtl/fifo_mem.sv
../rtl/sync_r2w.sv
../rtl/sync_w2r.sv
../rtl/wptr_full.sv
../rtl/rptr_empty.sv
../rtl/fifo_top.sv

// Assertions (checker module + bind)
../tb/sva/fifo_sva.sv
../tb/sva/fifo_bind.sv

// Testbench packages
../tb/common/fifo_tb_params_pkg.sv
../tb/if/fifo_clk_if.sv
../tb/if/fifo_wr_if.sv
../tb/if/fifo_rd_if.sv
../tb/agents/write_agent/fifo_wr_agent_pkg.sv
../tb/agents/read_agent/fifo_rd_agent_pkg.sv
../tb/env/fifo_env_pkg.sv
../tb/seq/fifo_seq_pkg.sv
../tb/tests/fifo_test_pkg.sv

// Top
../tb/top/tb_top.sv
