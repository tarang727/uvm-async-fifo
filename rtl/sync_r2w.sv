// -----------------------------------------------------------------------------
// sync_r2w.sv
//
// Two-flop synchronizer that brings the Gray-coded READ pointer into the WRITE
// clock domain. The write side uses the synchronized value (wq2_rptr) to
// compute wfull and walmost_full.
//
// Why this is safe for a multi-bit bus: the source is Gray-coded, so between
// two consecutive values exactly one bit toggles. If the first flop goes
// metastable on that one bit, it resolves to either the old or the new value,
// and both are legal pointer values. The worst case is that the write side sees
// the read pointer one increment late, which only makes wfull pessimistic
// (asserted for longer than strictly necessary) and never causes an overflow.
//
// A binary pointer could change many bits at once (e.g. 0111 -> 1000) and the
// destination could capture any mix of old/new bits, i.e. a value the pointer
// never held. That is the core reason for Gray coding.
//
// Reset: synchronizer flops are reset by the DESTINATION domain reset, so the
// write domain comes out of reset with a known (zero) view of the read pointer.
// -----------------------------------------------------------------------------
module sync_r2w #(
  parameter int ADDR_WIDTH = 4
) (
  input  logic                wclk,
  input  logic                wrst_n,
  input  logic [ADDR_WIDTH:0] rptr,      // Gray read pointer, rclk domain
  output logic [ADDR_WIDTH:0] wq2_rptr   // Gray read pointer, synchronized to wclk
);

  logic [ADDR_WIDTH:0] wq1_rptr;  // first stage: may go metastable

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wq1_rptr <= '0;
      wq2_rptr <= '0;
    end else begin
      wq1_rptr <= rptr;
      wq2_rptr <= wq1_rptr;
    end
  end

endmodule : sync_r2w
