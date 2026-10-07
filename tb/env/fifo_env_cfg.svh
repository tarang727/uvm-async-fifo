// -----------------------------------------------------------------------------
// fifo_env_cfg.svh
//
// Top-level configuration object. Owns the two agent configs and the
// clock-control interface, plus knobs that tests flip.
// -----------------------------------------------------------------------------
class fifo_env_cfg extends uvm_object;

  fifo_wr_agent_cfg   wr_cfg;
  fifo_rd_agent_cfg   rd_cfg;
  virtual fifo_clk_if clk_vif;

  bit has_coverage = 1'b1;
  bit has_scoreboard = 1'b1;

  // When set, the scoreboard reports an error if the reference model still
  // holds data at the end of the test (i.e. data was written but never read).
  // Tests whose virtual sequence drains the FIFO completely turn this on.
  bit expect_empty_at_end = 1'b0;

  `uvm_object_utils_begin(fifo_env_cfg)
    `uvm_field_object(wr_cfg,            UVM_ALL_ON)
    `uvm_field_object(rd_cfg,            UVM_ALL_ON)
    `uvm_field_int(has_coverage,         UVM_ALL_ON)
    `uvm_field_int(has_scoreboard,       UVM_ALL_ON)
    `uvm_field_int(expect_empty_at_end,  UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "fifo_env_cfg");
    super.new(name);
    wr_cfg = fifo_wr_agent_cfg::type_id::create("wr_cfg");
    rd_cfg = fifo_rd_agent_cfg::type_id::create("rd_cfg");
  endfunction

  // Wait until the pointer synchronizers have settled in both directions:
  // 2 flops + 1 registered flag stage, plus margin. Used before directed
  // flag checks, which are only exact when both sides are quiescent.
  task wait_sync_settle();
    fork
      wr_cfg.wait_clks(5);
      rd_cfg.wait_clks(5);
    join
    // A second round covers the round trip (a write is seen by the read
    // side, but nothing has to come back, so one round is enough in theory;
    // the extra round makes the check independent of clock ratio).
    fork
      wr_cfg.wait_clks(2);
      rd_cfg.wait_clks(2);
    join
  endtask

endclass : fifo_env_cfg
