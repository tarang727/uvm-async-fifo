// -----------------------------------------------------------------------------
// fifo_test_pkg.sv - test classes.
// -----------------------------------------------------------------------------
package fifo_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_tb_params_pkg::*;
  import fifo_wr_agent_pkg::*;
  import fifo_rd_agent_pkg::*;
  import fifo_env_pkg::*;
  import fifo_seq_pkg::*;

  `include "fifo_base_test.svh"
  `include "fifo_tests.svh"
endpackage : fifo_test_pkg
