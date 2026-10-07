// -----------------------------------------------------------------------------
// fifo_sva.sv
//
// White-box assertion checker for fifo_top. It is attached with `bind` (see
// fifo_bind.sv), so the RTL contains no verification code and the checker can
// see internal pointers without the RTL exporting them.
//
// Every property is clocked in ONE domain only. A property that mixed wclk and
// rclk signals would be sampling an asynchronous signal, which is exactly the
// kind of check that gives different answers in different simulators.
// Cross-domain behaviour (data integrity, ordering) is the scoreboard's job.
//
// Properties are disabled during their own domain's reset, except the reset
// value checks, which are only meaningful during/just after reset.
//
// Failures are reported with `uvm_error (not $error) so they are counted by
// the UVM report server: the test's PASS/FAIL line and the regression then
// include assertion failures, identically on every simulator.
//
// Groups:
//   R*  reset values          : flags are at their reset values in reset and
//                               immediately after release
//   G*  Gray-code integrity   : source pointers change by exactly one bit
//   P*  pointer protocol      : pointers move only on accepted ops; a write
//                               when full / read when empty leaves the
//                               pointer (and the memory) unchanged
//   F*  flag causality        : full/empty can only assert as a result of
//                               the local op, and only deassert after the
//                               synchronized remote pointer moved
//   C*  cover properties      : the interesting corners were reached
// -----------------------------------------------------------------------------
module fifo_sva #(
  parameter int DATA_WIDTH = 8,
  parameter int ADDR_WIDTH = 4
) (
  // Write domain
  input logic                  wclk,
  input logic                  wrst_n,
  input logic                  winc,
  input logic                  wfull,
  input logic                  walmost_full,
  input logic [ADDR_WIDTH:0]   wptr,          // Gray write pointer
  input logic [ADDR_WIDTH:0]   wq2_rptr,      // synchronized Gray read pointer
  input logic [ADDR_WIDTH-1:0] waddr,
  input logic [DATA_WIDTH-1:0] mem_at_waddr,  // storage word at waddr
  // Read domain
  input logic                  rclk,
  input logic                  rrst_n,
  input logic                  rinc,
  input logic                  rempty,
  input logic                  ralmost_empty,
  input logic [ADDR_WIDTH:0]   rptr,          // Gray read pointer
  input logic [ADDR_WIDTH:0]   rq2_wptr       // synchronized Gray write pointer
);

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ===========================================================================
  // Write domain
  // ===========================================================================
  default clocking wcb @(posedge wclk); endclocking

  // R1: in reset, and on the first edge after release, the write side is
  //     neither full nor almost full.
  R1_wflags_in_reset: assert property (
    !wrst_n |-> (!wfull && !walmost_full)
  ) else `uvm_error("SVA", $sformatf("R1: wfull/walmost_full not 0 during write reset"))

  R2_wflags_after_reset: assert property (
    $rose(wrst_n) |-> (!wfull && !walmost_full)
  ) else `uvm_error("SVA", $sformatf("R2: wfull/walmost_full not 0 after write reset release"))

  // G1: Gray pointer changes by exactly one bit per write-clock edge.
  //     (A one-hot XOR between consecutive values == one bit flipped.)
  G1_wptr_gray: assert property (disable iff (!wrst_n)
    $changed(wptr) |-> $onehot(wptr ^ $past(wptr))
  ) else `uvm_error("SVA", $sformatf("G1: wptr changed by more than one bit: %b -> %b", $past(wptr), wptr))

  // P1: an accepted write advances the pointer.
  P1_wptr_advances: assert property (disable iff (!wrst_n)
    (winc && !wfull) |=> $changed(wptr)
  ) else `uvm_error("SVA", $sformatf("P1: accepted write did not advance wptr"))

  // P2: no accepted write -> pointer holds. Covers "write when full is
  //     ignored" and "idle cycle does nothing".
  P2_wptr_holds: assert property (disable iff (!wrst_n)
    !(winc && !wfull) |=> $stable(wptr)
  ) else `uvm_error("SVA", $sformatf("P2: wptr moved without an accepted write"))

  // P3: a write while full must not change the memory. While full the write
  //     address cannot move (P2), so the word at waddr must be unchanged.
  P3_no_write_when_full: assert property (disable iff (!wrst_n)
    (winc && wfull) |=> $stable(mem_at_waddr)
  ) else `uvm_error("SVA", $sformatf("P3: write while full modified mem[%0d]", waddr))

  // F1: wfull can only rise on the edge right after a write request.
  F1_wfull_rise_cause: assert property (disable iff (!wrst_n)
    $rose(wfull) |-> $past(winc)
  ) else `uvm_error("SVA", $sformatf("F1: wfull rose without a write"))

  // F2: wfull can only fall after the synchronized read pointer has moved
  //     (the reader freed a slot and that information crossed the sync).
  F2_wfull_fall_cause: assert property (disable iff (!wrst_n)
    $fell(wfull) |-> ($past(wq2_rptr) != $past(wq2_rptr, 2))
  ) else `uvm_error("SVA", $sformatf("F2: wfull fell without read-pointer progress"))

  // F3: full implies almost full (AF threshold <= DEPTH).
  F3_full_implies_afull: assert property (disable iff (!wrst_n)
    wfull |-> walmost_full
  ) else `uvm_error("SVA", $sformatf("F3: wfull without walmost_full"))

  C1_wfull_seen:         cover property (disable iff (!wrst_n) $rose(wfull));
  C2_write_when_full:    cover property (disable iff (!wrst_n) winc && wfull);
  C3_wfull_released:     cover property (disable iff (!wrst_n) $fell(wfull));
  C4_walmost_full_seen:  cover property (disable iff (!wrst_n) $rose(walmost_full));

  // ===========================================================================
  // Read domain
  // ===========================================================================

  R3_rflags_in_reset: assert property (@(posedge rclk)
    !rrst_n |-> (rempty && ralmost_empty)
  ) else `uvm_error("SVA", $sformatf("R3: rempty/ralmost_empty not 1 during read reset"))

  R4_rflags_after_reset: assert property (@(posedge rclk)
    $rose(rrst_n) |-> (rempty && ralmost_empty)
  ) else `uvm_error("SVA", $sformatf("R4: rempty/ralmost_empty not 1 after read reset release"))

  G2_rptr_gray: assert property (@(posedge rclk) disable iff (!rrst_n)
    $changed(rptr) |-> $onehot(rptr ^ $past(rptr))
  ) else `uvm_error("SVA", $sformatf("G2: rptr changed by more than one bit"))

  P4_rptr_advances: assert property (@(posedge rclk) disable iff (!rrst_n)
    (rinc && !rempty) |=> $changed(rptr)
  ) else `uvm_error("SVA", $sformatf("P4: accepted read did not advance rptr"))

  // P5: "no read when empty": a read request while empty must not move the
  //     read pointer (nothing is popped, nothing is lost).
  P5_rptr_holds: assert property (@(posedge rclk) disable iff (!rrst_n)
    !(rinc && !rempty) |=> $stable(rptr)
  ) else `uvm_error("SVA", $sformatf("P5: rptr moved without an accepted read"))

  F4_rempty_rise_cause: assert property (@(posedge rclk) disable iff (!rrst_n)
    $rose(rempty) |-> $past(rinc)
  ) else `uvm_error("SVA", $sformatf("F4: rempty rose without a read"))

  F5_rempty_fall_cause: assert property (@(posedge rclk) disable iff (!rrst_n)
    $fell(rempty) |-> ($past(rq2_wptr) != $past(rq2_wptr, 2))
  ) else `uvm_error("SVA", $sformatf("F5: rempty fell without write-pointer progress"))

  F6_empty_implies_aempty: assert property (@(posedge rclk) disable iff (!rrst_n)
    rempty |-> ralmost_empty
  ) else `uvm_error("SVA", $sformatf("F6: rempty without ralmost_empty"))

  C5_rempty_seen:        cover property (@(posedge rclk) disable iff (!rrst_n) $rose(rempty));
  C6_read_when_empty:    cover property (@(posedge rclk) disable iff (!rrst_n) rinc && rempty);
  C7_rempty_released:    cover property (@(posedge rclk) disable iff (!rrst_n) $fell(rempty));
  C8_ralmost_empty_left:  cover property (@(posedge rclk) disable iff (!rrst_n) $fell(ralmost_empty));

  // ===========================================================================
  // Synchronizer structure
  // ===========================================================================
  // S1/S2: the synchronized pointer must equal the source pointer as it was
  // sampled TWO destination-clock edges earlier, i.e. there are exactly two
  // flops. Functional simulation has no metastability, so a design with a
  // single synchronizer flop passes every data/flag check; this white-box
  // property is what catches it in simulation. (Sign-off for CDC structure
  // is still done with a structural CDC tool, not with simulation.)
  //
  // These are the only properties that sample a signal from the other clock
  // domain. That is intentional and deterministic here: the property samples
  // the source pointer in the Preponed region of the destination edge, which
  // is exactly the value the first synchronizer flop captures.
  S1_w2r_two_stages: assert property (@(posedge rclk) disable iff (!rrst_n)
    ##2 (rq2_wptr == $past(wptr, 2))
  ) else `uvm_error("SVA", $sformatf("S1: rq2_wptr is not wptr delayed by 2 rclk edges"))

  S2_r2w_two_stages: assert property (@(posedge wclk) disable iff (!wrst_n)
    ##2 (wq2_rptr == $past(rptr, 2))
  ) else `uvm_error("SVA", $sformatf("S2: wq2_rptr is not rptr delayed by 2 wclk edges"))

  // Note on what is deliberately NOT asserted: the SYNCHRONIZED pointers
  // (wq2_rptr, rq2_wptr) are not required to move one Gray step at a time.
  // When the source clock is faster, the source pointer can advance several
  // times between two destination edges and the synchronized value jumps.
  // Each captured value is still a real pointer value (only one bit was in
  // flight at the sampling instant), which is all the design needs.

endmodule : fifo_sva
