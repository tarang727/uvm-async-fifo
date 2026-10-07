// -----------------------------------------------------------------------------
// fifo_wr_agent.svh
//
// Standard UVM agent: monitor always, driver + sequencer only when active.
// The config object is fetched once here and pushed down by handle, so the
// driver and monitor do not each need their own config_db lookup.
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(fifo_wr_item) fifo_wr_sequencer;

class fifo_wr_agent extends uvm_agent;
  `uvm_component_utils(fifo_wr_agent)

  fifo_wr_agent_cfg  cfg;
  fifo_wr_sequencer  sqr;
  fifo_wr_driver     drv;
  fifo_wr_monitor    mon;

  uvm_analysis_port #(fifo_wr_item) ap;  // re-export of the monitor's port

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(fifo_wr_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NOCFG", "fifo_wr_agent: no 'cfg' in uvm_config_db")
    end
    if (cfg.vif == null) begin
      `uvm_fatal("NOVIF", "fifo_wr_agent: cfg.vif is null")
    end

    mon     = fifo_wr_monitor::type_id::create("mon", this);
    mon.cfg = cfg;

    if (cfg.is_active == UVM_ACTIVE) begin
      sqr     = fifo_wr_sequencer::type_id::create("sqr", this);
      drv     = fifo_wr_driver::type_id::create("drv", this);
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = mon.ap;
    if (cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass : fifo_wr_agent
