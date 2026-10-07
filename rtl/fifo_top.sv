// -----------------------------------------------------------------------------
// fifo_top.sv
//
// Parameterized asynchronous (dual-clock) FIFO.
//
//            wclk domain                   |              rclk domain
//                                          |
//   winc ──►┌───────────┐ waddr ┌──────────┴──────────┐ raddr ┌────────────┐◄── rinc
//  wdata ──►│ wptr_full │──────►│      fifo_mem       │◄──────│ rptr_empty │
//  wfull ◄──│           │       │ (write: wclk,       │       │            │──► rempty
//  walmost◄─│           │       │  read: async)       │──────►│            │──► ralmost_empty
//           └─────┬─────┘       └──────────┬──────────┘ rdata └─────┬──────┘
//            wptr │ ▲ wq2_rptr             |              rq2_wptr ▲ │ rptr
//          (Gray) │ │                      |                       │ │ (Gray)
//                 │ └──── sync_r2w ◄───────┼───────────────────────┼─┘
//                 └─────► sync_w2r ────────┼───────────────────────┘
//                                          |
//
// Parameters
//   DATA_WIDTH          : width of each entry
//   ADDR_WIDTH          : log2(depth); depth = 2**ADDR_WIDTH (must be >= 2)
//   ALMOST_FULL_THRESH  : walmost_full  = (write-side occupancy >= this)
//   ALMOST_EMPTY_THRESH : ralmost_empty = (read-side occupancy  <= this)
//
// Interface semantics
//   * Write: data is captured on posedge wclk when winc=1 and wfull=0.
//            winc while wfull=1 is ignored (no state change).
//   * Read : first-word fall-through. When rempty=0, rdata shows the oldest
//            entry; rinc=1 on posedge rclk pops it. rinc while rempty=1 is
//            ignored.
//   * Resets are asynchronous assert. Each domain has its own reset; the
//     integrating SoC is expected to provide a reset synchronizer per domain
//     (async assert, sync de-assert) and to reset both sides together.
// -----------------------------------------------------------------------------
module fifo_top #(
  parameter int DATA_WIDTH          = 8,
  parameter int ADDR_WIDTH          = 4,
  parameter int ALMOST_FULL_THRESH  = (1 << ADDR_WIDTH) - 2,
  parameter int ALMOST_EMPTY_THRESH = 2
) (
  // Write domain
  input  logic                  wclk,
  input  logic                  wrst_n,
  input  logic                  winc,
  input  logic [DATA_WIDTH-1:0] wdata,
  output logic                  wfull,
  output logic                  walmost_full,
  // Read domain
  input  logic                  rclk,
  input  logic                  rrst_n,
  input  logic                  rinc,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic                  rempty,
  output logic                  ralmost_empty
);

  // The Gray-compare full detection needs at least two pointer MSBs.
  if (ADDR_WIDTH < 2) begin : g_param_check
    $error("fifo_top: ADDR_WIDTH must be >= 2 (got %0d)", ADDR_WIDTH);
  end

  logic [ADDR_WIDTH-1:0] waddr, raddr;
  logic [ADDR_WIDTH:0]   wptr, rptr;          // Gray pointers (source domain)
  logic [ADDR_WIDTH:0]   wq2_rptr, rq2_wptr;  // Gray pointers (synchronized)

  sync_r2w #(.ADDR_WIDTH(ADDR_WIDTH)) u_sync_r2w (
    .wclk     (wclk),
    .wrst_n   (wrst_n),
    .rptr     (rptr),
    .wq2_rptr (wq2_rptr)
  );

  sync_w2r #(.ADDR_WIDTH(ADDR_WIDTH)) u_sync_w2r (
    .rclk     (rclk),
    .rrst_n   (rrst_n),
    .wptr     (wptr),
    .rq2_wptr (rq2_wptr)
  );

  fifo_mem #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH)
  ) u_mem (
    .wclk   (wclk),
    .wclken (winc),
    .wfull  (wfull),
    .waddr  (waddr),
    .wdata  (wdata),
    .raddr  (raddr),
    .rdata  (rdata)
  );

  wptr_full #(
    .ADDR_WIDTH         (ADDR_WIDTH),
    .ALMOST_FULL_THRESH (ALMOST_FULL_THRESH)
  ) u_wptr_full (
    .wclk         (wclk),
    .wrst_n       (wrst_n),
    .winc         (winc),
    .wq2_rptr     (wq2_rptr),
    .waddr        (waddr),
    .wptr         (wptr),
    .wfull        (wfull),
    .walmost_full (walmost_full)
  );

  rptr_empty #(
    .ADDR_WIDTH          (ADDR_WIDTH),
    .ALMOST_EMPTY_THRESH (ALMOST_EMPTY_THRESH)
  ) u_rptr_empty (
    .rclk          (rclk),
    .rrst_n        (rrst_n),
    .rinc          (rinc),
    .rq2_wptr      (rq2_wptr),
    .raddr         (raddr),
    .rptr          (rptr),
    .rempty        (rempty),
    .ralmost_empty (ralmost_empty)
  );

endmodule : fifo_top
