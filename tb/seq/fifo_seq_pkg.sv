// -----------------------------------------------------------------------------
// fifo_seq_pkg.sv - virtual sequences (cross-domain scenarios).
// Agent-level sequences live in the agent packages.
// -----------------------------------------------------------------------------
package fifo_seq_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_tb_params_pkg::*;
  import fifo_wr_agent_pkg::*;
  import fifo_rd_agent_pkg::*;
  import fifo_env_pkg::*;

  `include "fifo_base_vseq.svh"
  `include "fifo_vseq_lib.svh"
endpackage : fifo_seq_pkg
