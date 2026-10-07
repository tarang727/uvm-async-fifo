// -----------------------------------------------------------------------------
// fifo_bind.sv
//
// Attaches fifo_sva to EVERY instance of fifo_top. Parameter and port
// expressions are evaluated in the scope of the target (fifo_top), so
// DATA_WIDTH/ADDR_WIDTH follow the DUT instance automatically and internal
// nets (wptr, wq2_rptr, ...) are reachable by their local names.
//
// The storage word at the current write address is reached through the memory
// instance (u_mem.mem[waddr]) so P3 can check that a write while full does not
// modify the array.
// -----------------------------------------------------------------------------
bind fifo_top fifo_sva #(
  .DATA_WIDTH (DATA_WIDTH),
  .ADDR_WIDTH (ADDR_WIDTH)
) u_fifo_sva (
  .wclk          (wclk),
  .wrst_n        (wrst_n),
  .winc          (winc),
  .wfull         (wfull),
  .walmost_full  (walmost_full),
  .wptr          (wptr),
  .wq2_rptr      (wq2_rptr),
  .waddr         (waddr),
  .mem_at_waddr  (u_mem.mem[waddr]),
  .rclk          (rclk),
  .rrst_n        (rrst_n),
  .rinc          (rinc),
  .rempty        (rempty),
  .ralmost_empty (ralmost_empty),
  .rptr          (rptr),
  .rq2_wptr      (rq2_wptr)
);
