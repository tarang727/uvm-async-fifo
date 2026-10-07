// -----------------------------------------------------------------------------
// fifo_rd_agent.svh - read-domain agent (see fifo_wr_agent.svh).
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(fifo_rd_item) fifo_rd_sequencer;

class fifo_rd_agent extends uvm_agent;
  `uvm_component_utils(fifo_rd_agent)

  fifo_rd_agent_cfg  cfg;
  fifo_rd_sequencer  sqr;
  fifo_rd_driver     drv;
  fifo_rd_monitor    mon;

  uvm_analysis_port #(fifo_rd_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(fifo_rd_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NOCFG", "fifo_rd_agent: no 'cfg' in uvm_config_db")
    end
    if (cfg.vif == null) begin
      `uvm_fatal("NOVIF", "fifo_rd_agent: cfg.vif is null")
    end

    mon     = fifo_rd_monitor::type_id::create("mon", this);
    mon.cfg = cfg;

    if (cfg.is_active == UVM_ACTIVE) begin
      sqr     = fifo_rd_sequencer::type_id::create("sqr", this);
      drv     = fifo_rd_driver::type_id::create("drv", this);
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

endclass : fifo_rd_agent
