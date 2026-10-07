// -----------------------------------------------------------------------------
// fifo_wr_if.sv
//
// Write-domain interface. Everything here is synchronous to wclk.
//
// Two clocking blocks separate the roles cleanly:
//   * drv_cb : used by the driver. Outputs are driven right after the clock
//              edge (#0 skew here; any non-zero skew also works), inputs are
//              sampled in the Preponed region (#1step), i.e. the value the DUT
//              itself saw at that edge. This removes TB/DUT races.
//   * mon_cb : used by the monitor; input-only, so the monitor cannot drive.
//
// Reset (wrst_n) is driven directly by the test (not through a clocking block)
// because it is asynchronous on assertion.
//
// Why wrst_n starts at 1, not 0: the DUT flops use `always_ff @(posedge clk
// or negedge rst_n)`. If rst_n were 0 from time 0, there would be no negedge
// event, and the reset branch would not run until the first clock edge (in a
// 4-state simulator the flops would be X until then; in a 2-state simulator
// they would silently start at 0, which hides the problem for rempty, whose
// reset value is 1). Starting at 1 and having the test drive 0 at time 0
// produces a real negedge, so asynchronous reset is exercised as designed.
// -----------------------------------------------------------------------------
interface fifo_wr_if (input logic wclk);
  import fifo_tb_params_pkg::*;

  // Declaration initializers give defined values before the first drive,
  // so nothing is X while the DUT is held in reset at time 0.
  logic  wrst_n = 1'b1;   // see note above: test drives 0 at time 0
  logic  winc   = 1'b0;
  data_t wdata  = '0;
  logic  wfull;
  logic  walmost_full;

  clocking drv_cb @(posedge wclk);
    default input #1step output #0;
    output winc, wdata;
    input  wfull, walmost_full, wrst_n;
  endclocking

  clocking mon_cb @(posedge wclk);
    default input #1step;
    input winc, wdata, wfull, walmost_full, wrst_n;
  endclocking

endinterface : fifo_wr_if
