// -----------------------------------------------------------------------------
// fifo_mem.sv
//
// Dual-port storage array for the asynchronous FIFO.
//
//   * Write port: synchronous to wclk. A location is written only when the
//     write-domain logic requests it (wclken) AND the FIFO is not full. The
//     wfull gate is redundant with the gating inside wptr_full, but keeping it
//     here makes the memory safe on its own and lets the SVA checker verify
//     "write-when-full never changes contents" at the storage level.
//   * Read port: asynchronous (combinational) read of mem[raddr]. This gives
//     "first-word fall-through" behaviour: whenever rempty is low, rdata already
//     holds the oldest entry, and asserting rinc pops it on the next rclk edge.
//
// Why is the async read safe across clock domains? raddr only ever points at a
// location whose write completed several wclk cycles earlier: the read side
// learns about a write only after the write pointer has gone through a 2-flop
// synchronizer. By the time raddr can legally point at an entry, that entry is
// stable. The storage itself is not a CDC hazard; the pointers are.
//
// Synthesis: maps to distributed RAM / flops on FPGA or to a 2-port register
// file in ASIC flows (where it would usually be replaced by a compiled macro).
// -----------------------------------------------------------------------------
module fifo_mem #(
  parameter int DATA_WIDTH = 8,
  parameter int ADDR_WIDTH = 4
) (
  input  logic                  wclk,
  input  logic                  wclken,   // write request (already qualified by winc)
  input  logic                  wfull,    // write is dropped when full
  input  logic [ADDR_WIDTH-1:0] waddr,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic [ADDR_WIDTH-1:0] raddr,
  output logic [DATA_WIDTH-1:0] rdata
);

  localparam int DEPTH = 1 << ADDR_WIDTH;

  // No reset on the storage: real RAMs have none, and the pointers guarantee
  // that an unwritten location is never presented as valid data.
  logic [DATA_WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge wclk) begin
    if (wclken && !wfull) begin
      mem[waddr] <= wdata;
    end
  end

  assign rdata = mem[raddr];

endmodule : fifo_mem
