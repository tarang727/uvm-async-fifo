// -----------------------------------------------------------------------------
// fifo_rd_if.sv
//
// Read-domain interface. Everything here is synchronous to rclk.
// See fifo_wr_if.sv for the clocking-block rationale and for why the reset
// signal is initialized to 1.
//
// Note on rdata sampling: the DUT is first-word fall-through, so at the rclk
// edge where rinc=1 and rempty=0 the popped word is the rdata value present
// just BEFORE that edge. The #1step input skew samples exactly that value.
// -----------------------------------------------------------------------------
interface fifo_rd_if (input logic rclk);
  import fifo_tb_params_pkg::*;

  logic  rrst_n = 1'b1;   // see note above: test drives 0 at time 0
  logic  rinc   = 1'b0;
  data_t rdata;
  logic  rempty;
  logic  ralmost_empty;

  clocking drv_cb @(posedge rclk);
    default input #1step output #0;
    output rinc;
    input  rdata, rempty, ralmost_empty, rrst_n;
  endclocking

  clocking mon_cb @(posedge rclk);
    default input #1step;
    input rinc, rdata, rempty, ralmost_empty, rrst_n;
  endclocking

endinterface : fifo_rd_if
