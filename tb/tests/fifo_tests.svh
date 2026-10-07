// -----------------------------------------------------------------------------
// fifo_tests.svh
//
// Test list (run with +UVM_TESTNAME=<name>):
//
//   fifo_smoke_test               known values in/out, flags after reset
//   fifo_random_test              concurrent random writer/reader + drain
//   fifo_full_empty_test          level walk 0..DEPTH..0 with exact flag checks
//   fifo_overflow_underflow_test  writes while full / reads while empty ignored
//   fifo_simul_rw_test            back-to-back reads and writes together
//   fifo_clock_ratio_test         same scenarios under several clock ratios
//   fifo_reset_test               reset in the middle of traffic, then recover
//
// Each test only chooses WHAT to run; HOW is in the virtual sequences.
// -----------------------------------------------------------------------------

class fifo_smoke_test extends fifo_base_test;
  `uvm_component_utils(fifo_smoke_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
  endfunction

  virtual task run_main();
    run_vseq(fifo_smoke_vseq::type_id::create("vseq"));
  endtask
endclass : fifo_smoke_test

// ---------------------------------------------------------------------------
class fifo_random_test extends fifo_base_test;
  `uvm_component_utils(fifo_random_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  int unsigned iterations = 4;

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
    void'($value$plusargs("ITERATIONS=%d", iterations));
  endfunction

  virtual task run_main();
    for (int i = 0; i < iterations; i++) begin
      fifo_random_vseq v = fifo_random_vseq::type_id::create($sformatf("vseq_%0d", i));
      if (!v.randomize()) `uvm_fatal("RAND", "fifo_random_vseq randomization failed")
      run_vseq(v);
    end
  endtask
endclass : fifo_random_test

// ---------------------------------------------------------------------------
class fifo_full_empty_test extends fifo_base_test;
  `uvm_component_utils(fifo_full_empty_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
  endfunction

  virtual task run_main();
    run_vseq(fifo_full_empty_vseq::type_id::create("vseq"));
  endtask
endclass : fifo_full_empty_test

// ---------------------------------------------------------------------------
class fifo_overflow_underflow_test extends fifo_base_test;
  `uvm_component_utils(fifo_overflow_underflow_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
  endfunction

  virtual task run_main();
    fifo_overflow_underflow_vseq v = fifo_overflow_underflow_vseq::type_id::create("vseq");
    if (!v.randomize()) `uvm_fatal("RAND", "randomization failed")
    run_vseq(v);
  endtask
endclass : fifo_overflow_underflow_test

// ---------------------------------------------------------------------------
class fifo_simul_rw_test extends fifo_base_test;
  `uvm_component_utils(fifo_simul_rw_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
  endfunction

  virtual task run_main();
    run_vseq(fifo_simul_rw_vseq::type_id::create("vseq"));
  endtask
endclass : fifo_simul_rw_test

// ---------------------------------------------------------------------------
// Clock ratio test: sweeps several (wclk, rclk) period pairs in one run. For
// each pair the FIFO is idle and empty when the clocks change, the domains
// are re-reset (clean, attributable start), then the ratio-mix virtual
// sequence runs. Coverage crosses each scenario with the ratio class.
//
// A single ratio can also be run from the command line with the plain
// +WCLK_PERIOD_PS / +RCLK_PERIOD_PS plusargs and any other test.
// ---------------------------------------------------------------------------
class fifo_clock_ratio_test extends fifo_base_test;
  `uvm_component_utils(fifo_clock_ratio_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  // {wclk period, rclk period} in ps.
  int unsigned ratios[5][2] = '{
    '{ 4_000, 17_000},   // wclk ~4.25x faster than rclk
    '{10_000, 13_000},   // wclk slightly faster
    '{10_000, 10_000},   // equal frequency, phase-shifted
    '{13_000, 10_000},   // rclk slightly faster
    '{17_000,  4_000}    // rclk ~4.25x faster than wclk
  };

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
    watchdog = 50ms;
  endfunction

  virtual task run_main();
    foreach (ratios[i]) begin
      `uvm_info("RATIO", $sformatf("=== wclk=%0dps rclk=%0dps ===", ratios[i][0], ratios[i][1]),
                UVM_LOW)
      cfg.clk_vif.set_periods(ratios[i][0], ratios[i][1]);
      apply_reset();
      run_vseq(fifo_ratio_mix_vseq::type_id::create($sformatf("mix_%0d", i)));
    end
  endtask
endclass : fifo_clock_ratio_test

// ---------------------------------------------------------------------------
// Reset test: run random concurrent traffic and, in parallel, assert both
// resets at a random point in the middle of it. Then check that the FIFO
// recovers and works normally.
//
// Traffic is deliberately NOT killed: the sequences keep issuing requests
// through the reset (drivers hold off while their domain is in reset), which
// is what a real system does. Killing sequences with stop_sequences() while a
// driver holds an item leaves the driver's item_done() without a request, a
// classic UVM pitfall.
//
// What checks what:
//   * monitors publish a reset event -> scoreboard flushes its model; any
//     data accepted before reset is (correctly) lost
//   * flags are checked at their reset values while reset is asserted
//   * SVA R1..R4 check flags in/after reset in parallel
//   * the random sequence's final drain + exact flag check, and a smoke
//     transfer afterwards, prove the FIFO is fully functional again
// ---------------------------------------------------------------------------
class fifo_reset_test extends fifo_base_test;
  `uvm_component_utils(fifo_reset_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void configure(fifo_env_cfg c);
    c.expect_empty_at_end = 1'b1;
  endfunction

  virtual task run_main();
    for (int i = 0; i < 3; i++) begin
      fifo_random_vseq v = fifo_random_vseq::type_id::create($sformatf("traffic_%0d", i));
      if (!v.randomize() with { n_wr >= 200; n_rd >= 200; wr_max_delay <= 2; rd_max_delay <= 2; })
        `uvm_fatal("RAND", "randomization failed")

      fork
        run_vseq(v);
        begin
          cfg.wr_cfg.wait_clks($urandom_range(20, 150));
          `uvm_info("RESET", $sformatf("mid-traffic reset #%0d", i), UVM_LOW)
          assert_reset();
          cfg.wr_cfg.wait_clks(1);
          check_reset_values();
          release_reset();
        end
      join

      run_vseq(fifo_smoke_vseq::type_id::create($sformatf("post_rst_%0d", i)));
    end
  endtask

  // While reset is asserted the flags must be at their reset values:
  // not full, not almost full, empty, almost empty.
  task check_reset_values();
    if (cfg.wr_cfg.vif.wfull !== 1'b0 || cfg.wr_cfg.vif.walmost_full !== 1'b0 ||
        cfg.rd_cfg.vif.rempty !== 1'b1 || cfg.rd_cfg.vif.ralmost_empty !== 1'b1) begin
      `uvm_error("RESET", $sformatf("flags in reset: wfull=%b walmost_full=%b rempty=%b ralmost_empty=%b",
                                    cfg.wr_cfg.vif.wfull, cfg.wr_cfg.vif.walmost_full,
                                    cfg.rd_cfg.vif.rempty, cfg.rd_cfg.vif.ralmost_empty))
    end else begin
      `uvm_info("RESET", "flags at reset values", UVM_MEDIUM)
    end
  endtask
endclass : fifo_reset_test
