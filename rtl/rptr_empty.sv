// -----------------------------------------------------------------------------
// rptr_empty.sv
//
// Read-domain pointer and EMPTY / ALMOST_EMPTY flag generation (rclk domain).
//
// Mirror image of wptr_full.sv:
//   * rbin : (ADDR_WIDTH+1)-bit binary read pointer (low bits = memory address).
//   * rptr : registered Gray copy, sent to the write domain via sync_r2w.
//
// EMPTY detection: the FIFO is empty when both pointers are identical,
// including the wrap bit. Since Gray<->binary is a bijection, comparing the
// Gray values directly is enough:
//       empty  <=>  rgray == wgray_synced
//
// rempty is registered from the NEXT read pointer so it asserts on the same
// rclk edge that pops the last entry (no cycle of "empty but flag low").
// It resets to 1: after reset the FIFO is empty.
//
// Pessimism: rq2_wptr lags the true write pointer, so rempty deasserts 2-3 rclk
// cycles after the write that made data available. It never deasserts early,
// so underflow (reading a location that was not yet written) is impossible.
//
// ALMOST_EMPTY: occupancy estimate = synced_wbin - rbin, which is <= the true
// occupancy. ralmost_empty = (estimate <= ALMOST_EMPTY_THRESH).
// -----------------------------------------------------------------------------
module rptr_empty #(
  parameter int ADDR_WIDTH          = 4,
  parameter int ALMOST_EMPTY_THRESH = 2
) (
  input  logic                  rclk,
  input  logic                  rrst_n,
  input  logic                  rinc,
  input  logic [ADDR_WIDTH:0]   rq2_wptr,     // Gray write ptr, synced into rclk
  output logic [ADDR_WIDTH-1:0] raddr,
  output logic [ADDR_WIDTH:0]   rptr,         // Gray read ptr (to sync_r2w)
  output logic                  rempty,
  output logic                  ralmost_empty
);

  logic                rpop;         // a read that is actually accepted
  logic [ADDR_WIDTH:0] rbin;
  logic [ADDR_WIDTH:0] rbinnext;
  logic [ADDR_WIDTH:0] rgraynext;
  logic [ADDR_WIDTH:0] rq2_wbin;
  logic [ADDR_WIDTH:0] rcount_next;
  logic                rempty_val;
  logic                ralmost_empty_val;

  function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] g);
    logic [ADDR_WIDTH:0] b;
    b[ADDR_WIDTH] = g[ADDR_WIDTH];
    for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
      b[i] = b[i+1] ^ g[i];
    end
    return b;
  endfunction

  // A read attempted while empty is ignored: the pointer does not move.
  assign rpop      = rinc & ~rempty;
  assign rbinnext  = rbin + (ADDR_WIDTH + 1)'(rpop);
  assign rgraynext = (rbinnext >> 1) ^ rbinnext;
  assign raddr     = rbin[ADDR_WIDTH-1:0];

  assign rempty_val = (rgraynext == rq2_wptr);

  assign rq2_wbin          = gray2bin(rq2_wptr);
  assign rcount_next       = rq2_wbin - rbinnext;
  assign ralmost_empty_val = (rcount_next <= (ADDR_WIDTH + 1)'(ALMOST_EMPTY_THRESH));

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rbin          <= '0;
      rptr          <= '0;
      rempty        <= 1'b1;
      ralmost_empty <= 1'b1;
    end else begin
      rbin          <= rbinnext;
      rptr          <= rgraynext;
      rempty        <= rempty_val;
      ralmost_empty <= ralmost_empty_val;
    end
  end

endmodule : rptr_empty
