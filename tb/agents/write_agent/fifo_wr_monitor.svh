// -----------------------------------------------------------------------------
// fifo_wr_monitor.svh
//
// Passive observer of the write interface. It never looks at the driver or at
// sequence items; everything comes from pins via the mon_cb clocking block.
//
// Publishing policy: one transaction per wclk edge on which
//   * a write is attempted (winc = 1), or
//   * winc, wfull or walmost_full changed since the previous published edge.
// This keeps the analysis traffic small (idle cycles with no change are
// skipped) while giving coverage every flag transition and letting other
// components know when the writer goes idle (needed for the "simultaneous
// access" coverage).
//
// Reset: while wrst_n is low, nothing is published except a single item with
// reset_evt = 1 at the first edge of the reset. The scoreboard uses that to
// flush its reference model.
// -----------------------------------------------------------------------------
class fifo_wr_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_wr_monitor)

  uvm_analysis_port #(fifo_wr_item) ap;

  fifo_wr_agent_cfg  cfg;
  virtual fifo_wr_if vif;

  int unsigned n_writes;    // accepted writes
  int unsigned n_dropped;   // writes attempted while full

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) begin
      `uvm_fatal("NOCFG", "fifo_wr_monitor: cfg handle not set by the agent")
    end
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    fifo_wr_item t;
    bit in_reset   = 1'b0;
    // Previous published values; initialized to the post-reset state.
    bit prev_winc  = 1'b0;
    bit prev_full  = 1'b0;
    bit prev_afull = 1'b0;
    bit cur_winc, cur_full, cur_afull;

    forever begin
      @(vif.mon_cb);

      if (vif.mon_cb.wrst_n !== 1'b1) begin
        if (!in_reset) begin
          t = fifo_wr_item::type_id::create("wr_rst");
          t.reset_evt = 1'b1;
          `uvm_info("WR_MON", "write-domain reset observed", UVM_MEDIUM)
          ap.write(t);
        end
        in_reset   = 1'b1;
        prev_winc  = 1'b0;
        prev_full  = 1'b0;
        prev_afull = 1'b0;
        continue;
      end
      in_reset = 1'b0;

      cur_winc  = vif.mon_cb.winc;
      cur_full  = vif.mon_cb.wfull;
      cur_afull = vif.mon_cb.walmost_full;

      if (cur_winc || cur_winc != prev_winc ||
          cur_full != prev_full || cur_afull != prev_afull) begin
        t = fifo_wr_item::type_id::create("wr_obs");
        t.winc        = cur_winc;
        t.data        = vif.mon_cb.wdata;
        t.full        = cur_full;
        t.almost_full = cur_afull;
        if (t.accepted())        n_writes++;
        if (cur_winc && cur_full) n_dropped++;
        `uvm_info("WR_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end

      prev_winc  = cur_winc;
      prev_full  = cur_full;
      prev_afull = cur_afull;
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("WR_MON", $sformatf("accepted writes: %0d, writes dropped (full): %0d",
                                  n_writes, n_dropped), UVM_LOW)
  endfunction

endclass : fifo_wr_monitor
