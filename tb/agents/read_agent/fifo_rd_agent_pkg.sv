// -----------------------------------------------------------------------------
// fifo_rd_agent_pkg.sv - read-domain (rclk) agent.
// -----------------------------------------------------------------------------
package fifo_rd_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_tb_params_pkg::*;

  `include "fifo_rd_item.svh"
  `include "fifo_rd_agent_cfg.svh"
  `include "fifo_rd_driver.svh"
  `include "fifo_rd_monitor.svh"
  `include "fifo_rd_agent.svh"
  `include "fifo_rd_seq_lib.svh"
endpackage : fifo_rd_agent_pkg
