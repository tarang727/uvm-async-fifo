// -----------------------------------------------------------------------------
// wptr_full.sv
//
// Write-domain pointer and FULL / ALMOST_FULL flag generation (wclk domain).
//
// Pointer representation (Cummings, "Simulation and Synthesis Techniques for
// Asynchronous FIFO Design", SNUG 2002, style #2):
//   * wbin  : (ADDR_WIDTH+1)-bit binary pointer. The low ADDR_WIDTH bits are the
//             memory address; the extra MSB is a "wrap" bit that distinguishes
//             full from empty when the address bits are equal.
//   * wptr  : Gray-coded copy of wbin, registered (never combinational), so the
//             value crossing into the rclk domain is glitch-free.
//
// FULL detection, done entirely in Gray code:
//   The FIFO is full when the write pointer is exactly DEPTH entries ahead of
//   the read pointer, i.e. the binary pointers differ only in the wrap MSB.
//   In (N+1)-bit reflected Gray code, adding 2^N to a value inverts the two
//   MSBs and leaves the rest unchanged. Therefore:
//       full  <=>  wgray == { ~rgray[N:N-1], rgray[N-2:0] }
//
// The flag is registered from the NEXT pointer value (wgraynext), so wfull is
// asserted on the same edge that writes the last free location: there is no
// cycle where the FIFO is full but wfull is still low.
//
// Pessimism: wq2_rptr lags the true read pointer by 2-3 wclk cycles, so wfull
// may stay asserted a little after the reader has freed a slot. It can never
// be deasserted early, so overflow is impossible. "Removal" of full is late,
// "assertion" of full is exact.
//
// ALMOST_FULL: the write side converts the synchronized Gray read pointer back
// to binary and computes an occupancy estimate. Because the read pointer is
// stale, this estimate is >= the true occupancy (again pessimistic and safe).
// walmost_full = (occupancy_estimate >= ALMOST_FULL_THRESH).
// -----------------------------------------------------------------------------
module wptr_full #(
  parameter int ADDR_WIDTH         = 4,
  parameter int ALMOST_FULL_THRESH = (1 << ADDR_WIDTH) - 2
) (
  input  logic                  wclk,
  input  logic                  wrst_n,
  input  logic                  winc,
  input  logic [ADDR_WIDTH:0]   wq2_rptr,     // Gray read ptr, synced into wclk
  output logic [ADDR_WIDTH-1:0] waddr,
  output logic [ADDR_WIDTH:0]   wptr,         // Gray write ptr (to sync_w2r)
  output logic                  wfull,
  output logic                  walmost_full
);

  logic                wpush;        // a write that is actually accepted
  logic [ADDR_WIDTH:0] wbin;
  logic [ADDR_WIDTH:0] wbinnext;
  logic [ADDR_WIDTH:0] wgraynext;
  logic [ADDR_WIDTH:0] wq2_rbin;     // synced read ptr converted back to binary
  logic [ADDR_WIDTH:0] wcount_next;  // occupancy estimate after this cycle
  logic                wfull_val;
  logic                walmost_full_val;

  // Gray -> binary: b[i] = XOR of g[N:i]. A right-shift-XOR chain does this.
  function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] g);
    logic [ADDR_WIDTH:0] b;
    b[ADDR_WIDTH] = g[ADDR_WIDTH];
    for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
      b[i] = b[i+1] ^ g[i];
    end
    return b;
  endfunction

  // Increment only when a write is requested AND the FIFO is not full:
  // a write attempted while full is silently dropped (no pointer movement).
  // The qualifier is computed as a 1-bit signal first. Writing
  // "wbin + (winc & ~wfull)" directly would evaluate ~wfull in the 5-bit
  // context of the addition (~1'b0 -> 5'b11111); it happens to be masked by
  // winc, but relying on that is fragile and lint-unclean.
  assign wpush     = winc & ~wfull;
  assign wbinnext  = wbin + (ADDR_WIDTH + 1)'(wpush);
  assign wgraynext = (wbinnext >> 1) ^ wbinnext;   // binary -> Gray
  assign waddr     = wbin[ADDR_WIDTH-1:0];

  assign wfull_val = (wgraynext == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1],
                                     wq2_rptr[ADDR_WIDTH-2:0]});

  // Modulo-2^(N+1) subtraction gives the occupancy in [0, DEPTH].
  assign wq2_rbin         = gray2bin(wq2_rptr);
  assign wcount_next      = wbinnext - wq2_rbin;
  assign walmost_full_val = (wcount_next >= (ADDR_WIDTH + 1)'(ALMOST_FULL_THRESH));

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wbin         <= '0;
      wptr         <= '0;
      wfull        <= 1'b0;
      walmost_full <= 1'b0;
    end else begin
      wbin         <= wbinnext;
      wptr         <= wgraynext;
      wfull        <= wfull_val;
      walmost_full <= walmost_full_val;
    end
  end

endmodule : wptr_full
