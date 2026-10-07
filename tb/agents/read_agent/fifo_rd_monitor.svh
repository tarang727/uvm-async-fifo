// -----------------------------------------------------------------------------
// fifo_rd_monitor.svh
//
// Passive observer of the read interface. Publishing policy mirrors
// fifo_wr_monitor: one item per rclk edge on which a read is attempted or
// rinc/rempty/ralmost_empty changed, plus one reset_evt item per reset.
//
// For accepted reads (rinc=1 && rempty=0), `data` holds rdata as sampled at
// that edge (#1step), which is the entry being popped.
// -----------------------------------------------------------------------------
class fifo_rd_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_rd_monitor)

  uvm_analysis_port #(fifo_rd_item) ap;

  fifo_rd_agent_cfg  cfg;
  virtual fifo_rd_if vif;

  int unsigned n_reads;     // accepted reads
  int unsigned n_ignored;   // reads attempted while empty

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) begin
      `uvm_fatal("NOCFG", "fifo_rd_monitor: cfg handle not set by the agent")
    end
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    fifo_rd_item t;
    bit in_reset    = 1'b0;
    // Post-reset state of the read side: empty and almost-empty asserted.
    bit prev_rinc   = 1'b0;
    bit prev_empty  = 1'b1;
    bit prev_aempty = 1'b1;
    bit cur_rinc, cur_empty, cur_aempty;

    forever begin
      @(vif.mon_cb);

      if (vif.mon_cb.rrst_n !== 1'b1) begin
        if (!in_reset) begin
          t = fifo_rd_item::type_id::create("rd_rst");
          t.reset_evt = 1'b1;
          `uvm_info("RD_MON", "read-domain reset observed", UVM_MEDIUM)
          ap.write(t);
        end
        in_reset    = 1'b1;
        prev_rinc   = 1'b0;
        prev_empty  = 1'b1;
        prev_aempty = 1'b1;
        continue;
      end
      in_reset = 1'b0;

      cur_rinc   = vif.mon_cb.rinc;
      cur_empty  = vif.mon_cb.rempty;
      cur_aempty = vif.mon_cb.ralmost_empty;

      if (cur_rinc || cur_rinc != prev_rinc ||
          cur_empty != prev_empty || cur_aempty != prev_aempty) begin
        t = fifo_rd_item::type_id::create("rd_obs");
        t.rinc         = cur_rinc;
        t.empty        = cur_empty;
        t.almost_empty = cur_aempty;
        t.data         = vif.mon_cb.rdata;
        if (t.accepted())          n_reads++;
        if (cur_rinc && cur_empty) n_ignored++;
        `uvm_info("RD_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end

      prev_rinc   = cur_rinc;
      prev_empty  = cur_empty;
      prev_aempty = cur_aempty;
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("RD_MON", $sformatf("accepted reads: %0d, reads ignored (empty): %0d",
                                  n_reads, n_ignored), UVM_LOW)
  endfunction

endclass : fifo_rd_monitor
