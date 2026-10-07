// -----------------------------------------------------------------------------
// sync_w2r.sv
//
// Two-flop synchronizer that brings the Gray-coded WRITE pointer into the READ
// clock domain. The read side uses the synchronized value (rq2_wptr) to compute
// rempty and ralmost_empty.
//
// See sync_r2w.sv for the reasoning behind Gray code + 2-flop synchronization.
// The only difference is direction: a late view of the write pointer makes
// rempty pessimistic (the FIFO looks empty for a couple of extra rclk cycles
// after a write), which can never cause an underflow.
// -----------------------------------------------------------------------------
module sync_w2r #(
  parameter int ADDR_WIDTH = 4
) (
  input  logic                rclk,
  input  logic                rrst_n,
  input  logic [ADDR_WIDTH:0] wptr,      // Gray write pointer, wclk domain
  output logic [ADDR_WIDTH:0] rq2_wptr   // Gray write pointer, synchronized to rclk
);

  logic [ADDR_WIDTH:0] rq1_wptr;  // first stage: may go metastable

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rq1_wptr <= '0;
      rq2_wptr <= '0;
    end else begin
      rq1_wptr <= wptr;
      rq2_wptr <= rq1_wptr;
    end
  end

endmodule : sync_w2r
