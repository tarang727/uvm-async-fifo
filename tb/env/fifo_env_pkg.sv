// -----------------------------------------------------------------------------
// fifo_env_pkg.sv - environment, scoreboard, coverage, virtual sequencer.
// -----------------------------------------------------------------------------
package fifo_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_tb_params_pkg::*;
  import fifo_wr_agent_pkg::*;
  import fifo_rd_agent_pkg::*;

  // Two analysis imps of different types in one component need distinct
  // write_*() method names; these macros declare uvm_analysis_imp_wr / _rd.
  `uvm_analysis_imp_decl(_wr)
  `uvm_analysis_imp_decl(_rd)

  `include "fifo_env_cfg.svh"
  `include "fifo_scoreboard.svh"
  `include "fifo_coverage.svh"
  `include "fifo_vsequencer.svh"
  `include "fifo_env.svh"
endpackage : fifo_env_pkg
