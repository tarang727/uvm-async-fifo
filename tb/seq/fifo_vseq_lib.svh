// -----------------------------------------------------------------------------
// fifo_vseq_lib.svh
//
// Scenario-level virtual sequences. Each test runs one of these (the clock
// ratio test runs several, once per clock configuration).
// -----------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Smoke: a handful of known values in, the same values out, flags sane.
// The first thing to get passing on a new DUT/TB.
// ---------------------------------------------------------------------------
class fifo_smoke_vseq extends fifo_base_vseq;
  `uvm_object_utils(fifo_smoke_vseq)

  function new(string name = "fifo_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    data_t vals[$] = '{PAT_ZEROS, PAT_ONES, PAT_ALT_01, PAT_ALT_10};
    // A few more recognizable values (8'h10, 8'h11, ...) truncated to width.
    for (int i = 0; i < 4; i++) vals.push_back(data_t'(16 + i));

    check_flags("after reset");
    write_n(0, vals);
    check_flags("after writes");
    read_n(vals.size());
    check_flags("after reads");
  endtask

endclass : fifo_smoke_vseq

// ---------------------------------------------------------------------------
// Random: independent random writer and reader running concurrently, then a
// full drain. Writes may be dropped (full) and reads ignored (empty); the
// scoreboard checks everything that was accepted.
// ---------------------------------------------------------------------------
class fifo_random_vseq extends fifo_base_vseq;
  `uvm_object_utils(fifo_random_vseq)

  rand int unsigned n_wr;
  rand int unsigned n_rd;
  rand int unsigned wr_max_delay;
  rand int unsigned rd_max_delay;

  constraint c_lens {
    n_wr inside {[100 : 400]};
    n_rd inside {[100 : 400]};
    wr_max_delay inside {[0 : 6]};
    rd_max_delay inside {[0 : 6]};
  }

  function new(string name = "fifo_random_vseq");
    super.new(name);
  endfunction

  task body();
    fifo_wr_rand_seq wr = fifo_wr_rand_seq::type_id::create("wr_rand");
    fifo_rd_rand_seq rd = fifo_rd_rand_seq::type_id::create("rd_rand");

    if (!wr.randomize() with { num_items == local::n_wr; max_delay == local::wr_max_delay; } ||
        !rd.randomize() with { num_items == local::n_rd; max_delay == local::rd_max_delay; }) begin
      `uvm_fatal("RAND", "random sub-sequence randomization failed")
    end
    `uvm_info(get_type_name(),
              $sformatf("writes=%0d (max gap %0d), reads=%0d (max gap %0d)",
                        n_wr, wr_max_delay, n_rd, rd_max_delay), UVM_LOW)

    fork
      wr.start(p_sequencer.wr_sqr, this);
      rd.start(p_sequencer.rd_sqr, this);
    join

    `uvm_info(get_type_name(),
              $sformatf("writer: %0d accepted / %0d dropped; reader: %0d accepted / %0d ignored",
                        wr.n_accepted, wr.n_dropped, rd.n_accepted, rd.n_ignored), UVM_LOW)
    drain_until_empty();
    check_flags("after drain");
  endtask

endclass : fifo_random_vseq

// ---------------------------------------------------------------------------
// Full/empty corners:
//   1. Walk the level up 0 -> DEPTH one entry at a time, checking all four
//      flags exactly at every level (covers both almost thresholds +/- 1).
//   2. One write while full (must be dropped).
//   3. Walk back down DEPTH -> 0, again checking every level.
//   4. One read while empty (must be ignored).
//   5. Repeat a full fill/drain with bursts, twice, so the pointers wrap and
//      the wrap (MSB) bit takes both values while full/empty.
// ---------------------------------------------------------------------------
class fifo_full_empty_vseq extends fifo_base_vseq;
  `uvm_object_utils(fifo_full_empty_vseq)

  function new(string name = "fifo_full_empty_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned got;

    check_flags("reset");

    for (int i = 0; i < DEPTH; i++) begin
      write_n(1);
      check_flags("walk up");
    end

    fill_to_full(got, 1);
    if (got != 0) `uvm_error(get_type_name(), $sformatf("%0d writes accepted while full", got))
    check_flags("full + probe write");

    for (int i = 0; i < DEPTH; i++) begin
      read_n(1);
      check_flags("walk down");
    end

    read_to_empty(got, 1);
    if (got != 0) `uvm_error(get_type_name(), $sformatf("%0d reads accepted while empty", got))
    check_flags("empty + probe read");

    for (int pass = 0; pass < 2; pass++) begin
      fill_to_full(got, 1);
      if (got != DEPTH) begin
        `uvm_error(get_type_name(),
                   $sformatf("burst fill pass %0d: accepted %0d, expected DEPTH=%0d", pass, got, DEPTH))
      end
      check_flags($sformatf("burst full pass %0d", pass));

      read_to_empty(got, 1);
      if (got != DEPTH) begin
        `uvm_error(get_type_name(),
                   $sformatf("burst drain pass %0d: read %0d, expected DEPTH=%0d", pass, got, DEPTH))
      end
      check_flags($sformatf("burst empty pass %0d", pass));
    end
  endtask

endclass : fifo_full_empty_vseq

// ---------------------------------------------------------------------------
// Overflow / underflow:
//   * Reads on an empty FIFO right after reset must be ignored.
//   * Fill, then keep writing (n_extra writes while full): every extra write
//     must be dropped, and exactly DEPTH entries must come back out, in order
//     (the scoreboard proves that the dropped data never got in).
//   * Reads on the drained FIFO must be ignored again.
// ---------------------------------------------------------------------------
class fifo_overflow_underflow_vseq extends fifo_base_vseq;
  `uvm_object_utils(fifo_overflow_underflow_vseq)

  rand int unsigned n_extra;
  constraint c_extra { n_extra inside {[4 : 2 * DEPTH]}; }

  function new(string name = "fifo_overflow_underflow_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned got;

    read_to_empty(got, n_extra);
    if (got != 0) `uvm_error("UNDERFLOW", $sformatf("%0d reads accepted on an empty FIFO", got))
    check_flags("underflow after reset");

    fill_to_full(got, n_extra);
    if (got != DEPTH) begin
      `uvm_error("OVERFLOW", $sformatf("accepted %0d writes, expected DEPTH=%0d", got, DEPTH))
    end
    check_flags("after overflow attempt");

    read_n(DEPTH);
    check_flags("drained");

    read_to_empty(got, n_extra);
    if (got != 0) `uvm_error("UNDERFLOW", $sformatf("%0d reads accepted on an empty FIFO", got))
    check_flags("underflow after drain");

    // Overflow again from a non-zero pointer position (pointers have wrapped
    // once), to make sure full detection does not depend on the pointer base.
    write_n(DEPTH / 2);
    read_n(DEPTH / 2);
    fill_to_full(got, n_extra);
    if (got != DEPTH) begin
      `uvm_error("OVERFLOW", $sformatf("(offset) accepted %0d writes, expected %0d", got, DEPTH))
    end
    read_n(DEPTH);
    check_flags("end");
  endtask

endclass : fifo_overflow_underflow_vseq

// ---------------------------------------------------------------------------
// Simultaneous read/write: pre-fill to about half, then run a back-to-back
// writer and a back-to-back reader at the same time so that the FIFO is
// written and read in the same (and overlapping) cycles, with the level
// hovering mid-range or drifting towards full/empty depending on clock ratio.
// ---------------------------------------------------------------------------
class fifo_simul_rw_vseq extends fifo_base_vseq;
  `uvm_object_utils(fifo_simul_rw_vseq)

  int unsigned n_items = 8 * DEPTH;

  function new(string name = "fifo_simul_rw_vseq");
    super.new(name);
  endfunction

  task body();
    fifo_wr_rand_seq wr = fifo_wr_rand_seq::type_id::create("wr_simul");
    fifo_rd_rand_seq rd = fifo_rd_rand_seq::type_id::create("rd_simul");

    write_n(DEPTH / 2);

    if (!wr.randomize() with { num_items == local::n_items; max_delay == 0; } ||
        !rd.randomize() with { num_items == local::n_items; max_delay == 0; }) begin
      `uvm_fatal("RAND", "simul sub-sequence randomization failed")
    end
    fork
      wr.start(p_sequencer.wr_sqr, this);
      rd.start(p_sequencer.rd_sqr, this);
    join
    drain_until_empty();
    check_flags("after simultaneous traffic");
  endtask

endclass : fifo_simul_rw_vseq

// ---------------------------------------------------------------------------
// Mix used by the clock-ratio test for each clock configuration.
// ---------------------------------------------------------------------------
class fifo_ratio_mix_vseq extends fifo_base_vseq;
  `uvm_object_utils(fifo_ratio_mix_vseq)

  function new(string name = "fifo_ratio_mix_vseq");
    super.new(name);
  endfunction

  task body();
    fifo_overflow_underflow_vseq ou  = fifo_overflow_underflow_vseq::type_id::create("ou");
    fifo_simul_rw_vseq           sim = fifo_simul_rw_vseq::type_id::create("sim");
    fifo_random_vseq             rnd = fifo_random_vseq::type_id::create("rnd");

    if (!ou.randomize() || !rnd.randomize() with { n_wr <= 150; n_rd <= 150; }) begin
      `uvm_fatal("RAND", "ratio-mix sub-sequence randomization failed")
    end
    ou.start(p_sequencer, this);
    sim.start(p_sequencer, this);
    rnd.start(p_sequencer, this);
  endtask

endclass : fifo_ratio_mix_vseq
