// -----------------------------------------------------------------------------
// fifo_wr_agent_cfg.svh
//
// Configuration object for the write agent. The test builds it, the env puts
// it into uvm_config_db for the agent, and the agent hands it to its children.
// Keeping the virtual interface inside the config object (rather than doing a
// separate config_db lookup in every component) means there is exactly one
// place where the interface is resolved.
// -----------------------------------------------------------------------------
class fifo_wr_agent_cfg extends uvm_object;

  virtual fifo_wr_if     vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  `uvm_object_utils_begin(fifo_wr_agent_cfg)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "fifo_wr_agent_cfg");
    super.new(name);
  endfunction

  // Clock-aware wait used by sequences (e.g. "let the pointer synchronizers
  // settle"). Sequences never touch the interface directly; they go through
  // the config object so they stay reusable.
  task wait_clks(int unsigned n);
    repeat (n) @(vif.mon_cb);
  endtask

  task wait_reset_released();
    if (vif.wrst_n !== 1'b1) @(posedge vif.wrst_n);
  endtask

endclass : fifo_wr_agent_cfg
