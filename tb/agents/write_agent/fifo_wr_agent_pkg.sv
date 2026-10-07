// -----------------------------------------------------------------------------
// fifo_wr_agent_pkg.sv - write-domain (wclk) agent.
// -----------------------------------------------------------------------------
package fifo_wr_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_tb_params_pkg::*;

  `include "fifo_wr_item.svh"
  `include "fifo_wr_agent_cfg.svh"
  `include "fifo_wr_driver.svh"
  `include "fifo_wr_monitor.svh"
  `include "fifo_wr_agent.svh"
  `include "fifo_wr_seq_lib.svh"
endpackage : fifo_wr_agent_pkg
