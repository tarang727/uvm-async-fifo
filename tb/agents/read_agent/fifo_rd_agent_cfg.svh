// -----------------------------------------------------------------------------
// fifo_rd_agent_cfg.svh - configuration object for the read agent.
// See fifo_wr_agent_cfg.svh for the rationale.
// -----------------------------------------------------------------------------
class fifo_rd_agent_cfg extends uvm_object;

  virtual fifo_rd_if     vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  `uvm_object_utils_begin(fifo_rd_agent_cfg)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "fifo_rd_agent_cfg");
    super.new(name);
  endfunction

  task wait_clks(int unsigned n);
    repeat (n) @(vif.mon_cb);
  endtask

  task wait_reset_released();
    if (vif.rrst_n !== 1'b1) @(posedge vif.rrst_n);
  endtask

endclass : fifo_rd_agent_cfg
