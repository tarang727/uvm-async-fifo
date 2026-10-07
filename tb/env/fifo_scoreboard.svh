// -----------------------------------------------------------------------------
// fifo_scoreboard.svh
//
// Reference model + checker for the asynchronous FIFO.
//
// Reference model: a SystemVerilog queue. An accepted write (winc && !wfull at
// a wclk edge) pushes wdata; an accepted read (rinc && !rempty at an rclk edge)
// pops the front and compares it to the observed rdata. Because the FIFO
// preserves order, a plain queue is a complete functional model of the data
// path; no timing or clock-ratio knowledge is needed.
//
// Why the cross-domain ordering is safe: both monitors publish at their own
// clock edges, so the scoreboard receives events in real simulation-time
// order. A read can only be accepted after the write pointer has crossed a
// 2-flop synchronizer, i.e. several rclk cycles after the write edge, so the
// write is always already in the queue when the matching read arrives. Even if
// a write edge and a read edge fall in the same time step (arbitrary order),
// that read can never be for that write.
//
// Checks performed:
//   1. Data integrity and order: popped data == model front (uvm_error).
//   2. No phantom reads: an accepted read when the model is empty means the
//      DUT reported !rempty without data (underflow).
//   3. No overflow: an accepted write when the model already holds DEPTH
//      entries means the DUT reported !wfull while full.
//   4. Flag safety (pessimism direction): at any observed edge
//        !wfull         => occupancy <  DEPTH
//        !walmost_full  => occupancy <  AF_THRESH
//        !rempty        => occupancy >  0
//        !ralmost_empty => occupancy >  AE_THRESH
//      The flags are allowed to be late in de-asserting (synchronizer
//      latency) but must never under-report. Exact flag values are checked by
//      the directed virtual sequences once the synchronizers have settled.
//   5. End of test: optionally require that every written entry was read.
//
// Reset: both domains are reset together in this testbench; a reset event
// from either monitor flushes the model.
//
// The uvm_analysis_imp_wr / _rd classes are declared in fifo_env_pkg.sv.
// -----------------------------------------------------------------------------
class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)

  uvm_analysis_imp_wr #(fifo_wr_item, fifo_scoreboard) wr_export;
  uvm_analysis_imp_rd #(fifo_rd_item, fifo_scoreboard) rd_export;

  fifo_env_cfg cfg;

  protected data_t model_q[$];

  // Statistics
  int unsigned n_writes;
  int unsigned n_reads;
  int unsigned n_matches;
  int unsigned n_mismatches;
  int unsigned n_resets;
  int unsigned max_occupancy;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    wr_export = new("wr_export", this);
    rd_export = new("rd_export", this);
  endfunction

  function int unsigned occupancy();
    return model_q.size();
  endfunction

  // ---------------------------------------------------------------------------
  // Write side
  // ---------------------------------------------------------------------------
  function void write_wr(fifo_wr_item t);
    int unsigned occ = model_q.size();

    if (t.reset_evt) begin
      flush("write-domain reset");
      return;
    end

    // Flag safety checks (values sampled at this edge, before this write).
    if (!t.full && occ >= DEPTH) begin
      `uvm_error("SB_WFULL",
                 $sformatf("wfull=0 but model occupancy is %0d (DEPTH=%0d)", occ, DEPTH))
    end
    if (!t.almost_full && occ >= AF_THRESH) begin
      `uvm_error("SB_WAFULL",
                 $sformatf("walmost_full=0 but model occupancy is %0d (threshold %0d)",
                           occ, AF_THRESH))
    end

    if (!t.accepted()) return;

    if (occ >= DEPTH) begin
      `uvm_error("SB_OVERFLOW",
                 $sformatf("DUT accepted write 0x%0h while model holds %0d entries",
                           t.data, occ))
    end
    model_q.push_back(t.data);
    n_writes++;
    if (model_q.size() > max_occupancy) max_occupancy = model_q.size();
  endfunction

  // ---------------------------------------------------------------------------
  // Read side
  // ---------------------------------------------------------------------------
  function void write_rd(fifo_rd_item t);
    int unsigned occ = model_q.size();
    data_t       exp;

    if (t.reset_evt) begin
      flush("read-domain reset");
      return;
    end

    if (!t.empty && occ == 0) begin
      `uvm_error("SB_REMPTY", "rempty=0 but the model is empty")
    end
    if (!t.almost_empty && occ <= AE_THRESH) begin
      `uvm_error("SB_RAEMPTY",
                 $sformatf("ralmost_empty=0 but model occupancy is %0d (threshold %0d)",
                           occ, AE_THRESH))
    end

    if (!t.accepted()) return;

    n_reads++;
    if (occ == 0) begin
      `uvm_error("SB_UNDERFLOW",
                 $sformatf("DUT popped 0x%0h but the model is empty", t.data))
      n_mismatches++;
      return;
    end

    exp = model_q.pop_front();
    if (t.data !== exp) begin
      n_mismatches++;
      `uvm_error("SB_MISMATCH",
                 $sformatf("read #%0d: expected 0x%0h, got 0x%0h", n_reads, exp, t.data))
    end else begin
      n_matches++;
      `uvm_info("SB_MATCH", $sformatf("read #%0d: 0x%0h", n_reads, t.data), UVM_HIGH)
    end
  endfunction

  protected function void flush(string why);
    if (model_q.size() != 0) begin
      `uvm_info("SB_FLUSH", $sformatf("%s: discarding %0d entries from model",
                                      why, model_q.size()), UVM_MEDIUM)
    end
    model_q.delete();
    n_resets++;
  endfunction

  // ---------------------------------------------------------------------------
  // End of test
  // ---------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (n_writes == 0) begin
      `uvm_warning("SB_NOWRITES", "no accepted writes were observed")
    end
    if (cfg != null && cfg.expect_empty_at_end && model_q.size() != 0) begin
      `uvm_error("SB_LEFTOVER",
                 $sformatf("%0d entries were written but never read (front = 0x%0h)",
                           model_q.size(), model_q[0]))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB_REPORT",
              $sformatf("writes=%0d reads=%0d matches=%0d mismatches=%0d left_in_model=%0d max_occupancy=%0d resets=%0d",
                        n_writes, n_reads, n_matches, n_mismatches,
                        model_q.size(), max_occupancy, n_resets), UVM_LOW)
  endfunction

endclass : fifo_scoreboard
