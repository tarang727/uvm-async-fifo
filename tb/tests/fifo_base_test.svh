// -----------------------------------------------------------------------------
// fifo_base_test.svh
//
// Base test. Responsibilities:
//   build_phase   : fetch the virtual interfaces from config_db (put there by
//                   tb_top), build the env config, create the env.
//   end_of_elab   : print the topology once, for debugging.
//   run_phase     : apply reset, run the test's main virtual sequence
//                   (run_main(), overridden by each test), and hold an
//                   objection for the duration.
//   report_phase  : print a single PASS/FAIL line based on the UVM report
//                   server's error/fatal count; the regression script greps it.
//
// Reset is driven here rather than by an agent: there is one reset per domain,
// both are asserted together (asynchronously) and released synchronously to
// their own clocks, which is how a real SoC reset controller would do it.
// -----------------------------------------------------------------------------
class fifo_base_test extends uvm_test;
  `uvm_component_utils(fifo_base_test)

  fifo_env     env;
  fifo_env_cfg cfg;

  // Global watchdog (simulation time). A hang in a handshake would otherwise
  // run forever. Tests can raise it if they are legitimately long.
  time watchdog = 5ms;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = fifo_env_cfg::type_id::create("cfg");
    if (!uvm_config_db #(virtual fifo_wr_if)::get(this, "", "wr_vif", cfg.wr_cfg.vif) ||
        !uvm_config_db #(virtual fifo_rd_if)::get(this, "", "rd_vif", cfg.rd_cfg.vif) ||
        !uvm_config_db #(virtual fifo_clk_if)::get(this, "", "clk_vif", cfg.clk_vif)) begin
      `uvm_fatal("NOVIF", "virtual interfaces not found in uvm_config_db (check tb_top)")
    end

    configure(cfg);   // per-test knobs

    uvm_config_db #(fifo_env_cfg)::set(this, "env", "cfg", cfg);
    env = fifo_env::type_id::create("env", this);
  endfunction

  // Hook for derived tests to adjust the configuration before the env is built.
  virtual function void configure(fifo_env_cfg c);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    `uvm_info("CFG", $sformatf("DATA_WIDTH=%0d DEPTH=%0d AF_THRESH=%0d AE_THRESH=%0d wclk=%0dps rclk=%0dps",
                               DATA_WIDTH, DEPTH, AF_THRESH, AE_THRESH,
                               cfg.clk_vif.wclk_period_ps, cfg.clk_vif.rclk_period_ps), UVM_LOW)
    if (uvm_report_enabled(UVM_HIGH)) uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    fork
      begin
        apply_reset();
        run_main();
        // Let the last transactions propagate through the monitors.
        fork
          cfg.wr_cfg.wait_clks(4);
          cfg.rd_cfg.wait_clks(4);
        join
      end
      begin
        #(watchdog);
        `uvm_fatal("WATCHDOG", $sformatf("test did not finish within %0t", watchdog))
      end
    join_any
    disable fork;
    phase.drop_objection(this);
  endtask

  // Override in each test.
  virtual task run_main();
  endtask

  // Assert both resets asynchronously, hold for a few cycles of each clock,
  // release each synchronously to its own clock (on the inactive edge so the
  // release never coincides with an active edge), then let both domains run a
  // couple of cycles before traffic starts.
  virtual task apply_reset(int unsigned cycles = 5);
    assert_reset();
    release_reset(cycles);
  endtask

  // Asynchronous assertion: takes effect immediately, no clock needed.
  task assert_reset();
    `uvm_info("RESET", "asserting wrst_n / rrst_n", UVM_MEDIUM)
    cfg.wr_cfg.vif.wrst_n = 1'b0;
    cfg.rd_cfg.vif.rrst_n = 1'b0;
  endtask

  // Synchronous de-assertion, each domain on its own clock.
  task release_reset(int unsigned cycles = 5);
    virtual fifo_wr_if wv = cfg.wr_cfg.vif;
    virtual fifo_rd_if rv = cfg.rd_cfg.vif;
    fork
      begin repeat (cycles) @(posedge wv.wclk); @(negedge wv.wclk); wv.wrst_n = 1'b1; end
      begin repeat (cycles) @(posedge rv.rclk); @(negedge rv.rclk); rv.rrst_n = 1'b1; end
    join
    fork
      cfg.wr_cfg.wait_clks(2);
      cfg.rd_cfg.wait_clks(2);
    join
    `uvm_info("RESET", "reset released in both domains", UVM_MEDIUM)
  endtask

  // Start a virtual sequence on the env's virtual sequencer.
  task run_vseq(fifo_base_vseq vseq);
    vseq.start(env.vsqr);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int unsigned n_err = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    super.report_phase(phase);
    if (n_err == 0) begin
      `uvm_info("RESULT", $sformatf("TEST PASSED: %s", get_type_name()), UVM_NONE)
    end else begin
      `uvm_info("RESULT", $sformatf("TEST FAILED: %s (%0d errors)", get_type_name(), n_err), UVM_NONE)
    end
  endfunction

endclass : fifo_base_test
