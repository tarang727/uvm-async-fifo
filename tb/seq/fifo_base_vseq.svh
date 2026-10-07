// -----------------------------------------------------------------------------
// fifo_base_vseq.svh
//
// Base virtual sequence. Provides the building blocks that the scenario
// sequences compose:
//
//   write_n / read_n          : exact number of accepted writes / reads
//   fill_to_full              : back-to-back writes until one is dropped
//   drain_until_empty         : read until the FIFO is (settled) empty
//   check_flags(level)        : after the synchronizers settle, all four flags
//                               must match the exact values for `level`
//
// Directed flag checks belong here (not in the scoreboard) because exact flag
// values are only defined once both pointer synchronizers have settled. The
// scoreboard checks the always-true safety direction on every cycle; this
// class checks exactness at chosen quiet points.
//
// `level` bookkeeping: the scenario sequences track the expected occupancy
// themselves (they know exactly what they wrote and read), which makes each
// directed check self-contained and easy to read.
// -----------------------------------------------------------------------------
class fifo_base_vseq extends uvm_sequence;
  `uvm_object_utils(fifo_base_vseq)
  `uvm_declare_p_sequencer(fifo_vsequencer)

  // Expected occupancy, maintained by the directed helpers below.
  int unsigned level;

  function new(string name = "fifo_base_vseq");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------------
  // Traffic helpers
  // ---------------------------------------------------------------------------

  // Write `n` entries. With `values` non-empty, those values are written in
  // order (n is ignored); otherwise data is random.
  task write_n(int unsigned n, data_t values[$] = {});
    fifo_wr_list_seq s = fifo_wr_list_seq::type_id::create("wr_list");
    if (values.size() == 0) begin
      repeat (n) s.values.push_back(data_t'($urandom()));
    end else begin
      s.values = values;
    end
    s.start(p_sequencer.wr_sqr, this);
    if (s.n_dropped != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("write_n: %0d writes unexpectedly dropped (FIFO full)", s.n_dropped))
    end
    level += s.n_accepted;
  endtask

  // Pop exactly `n` entries (retrying while the read side still sees empty).
  task read_n(int unsigned n);
    fifo_rd_count_seq s = fifo_rd_count_seq::type_id::create("rd_count");
    s.count = n;
    s.start(p_sequencer.rd_sqr, this);
    level -= (s.n_accepted > level) ? level : s.n_accepted;
  endtask

  // Write back-to-back until `drops` writes have been rejected as full.
  // Returns the number of writes that were accepted.
  task fill_to_full(output int unsigned accepted, input int unsigned drops = 1);
    fifo_wr_burst_seq s = fifo_wr_burst_seq::type_id::create("wr_burst");
    s.stop_after_drops = drops;
    s.start(p_sequencer.wr_sqr, this);
    accepted = s.n_accepted;
    level   += s.n_accepted;
    if (s.n_dropped != drops) begin
      `uvm_error(get_type_name(),
                 $sformatf("fill_to_full: wanted %0d dropped writes, saw %0d", drops, s.n_dropped))
    end
  endtask

  // Read back-to-back until `ignored` reads have been rejected as empty.
  task read_to_empty(output int unsigned accepted, input int unsigned ignored = 1);
    fifo_rd_burst_seq s = fifo_rd_burst_seq::type_id::create("rd_burst");
    s.stop_after_ignored = ignored;
    s.start(p_sequencer.rd_sqr, this);
    accepted = s.n_accepted;
    level   -= (s.n_accepted > level) ? level : s.n_accepted;
    if (s.n_ignored != ignored) begin
      `uvm_error(get_type_name(),
                 $sformatf("read_to_empty: wanted %0d ignored reads, saw %0d", ignored, s.n_ignored))
    end
  endtask

  // Read until the FIFO is empty AND stays empty after the synchronizers
  // settle. Use only when the writer is idle. Robust to an unknown level
  // (e.g. after random traffic), so it resets `level` to 0.
  task drain_until_empty();
    int unsigned got;
    int unsigned rounds = 0;
    do begin
      read_to_empty(got);
      p_sequencer.cfg.wait_sync_settle();
      rounds++;
    end while (p_sequencer.cfg.rd_cfg.vif.rempty !== 1'b1 && rounds < 4 * DEPTH);
    if (p_sequencer.cfg.rd_cfg.vif.rempty !== 1'b1) begin
      `uvm_error(get_type_name(), "drain_until_empty: FIFO never became empty")
    end
    level = 0;
  endtask

  // ---------------------------------------------------------------------------
  // Directed flag check at a quiet point
  // ---------------------------------------------------------------------------
  task check_flags(string where = "");
    bit exp_full   = (level == DEPTH);
    bit exp_afull  = (level >= AF_THRESH);
    bit exp_empty  = (level == 0);
    bit exp_aempty = (level <= AE_THRESH);
    bit act_full, act_afull, act_empty, act_aempty;

    p_sequencer.cfg.wait_sync_settle();
    act_full   = p_sequencer.cfg.wr_cfg.vif.wfull;
    act_afull  = p_sequencer.cfg.wr_cfg.vif.walmost_full;
    act_empty  = p_sequencer.cfg.rd_cfg.vif.rempty;
    act_aempty = p_sequencer.cfg.rd_cfg.vif.ralmost_empty;

    if ({act_full, act_afull, act_empty, act_aempty} !==
        {exp_full, exp_afull, exp_empty, exp_aempty}) begin
      `uvm_error("FLAGS", $sformatf(
        "%s level=%0d: expected full=%0b afull=%0b empty=%0b aempty=%0b, got %0b %0b %0b %0b",
        where, level, exp_full, exp_afull, exp_empty, exp_aempty,
        act_full, act_afull, act_empty, act_aempty))
    end else begin
      `uvm_info("FLAGS", $sformatf("%s level=%0d: flags OK (full=%0b afull=%0b empty=%0b aempty=%0b)",
                                   where, level, act_full, act_afull, act_empty, act_aempty),
                UVM_MEDIUM)
    end
  endtask

endclass : fifo_base_vseq
