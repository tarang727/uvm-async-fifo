// -----------------------------------------------------------------------------
// fifo_rd_driver.svh
//
// Drives read requests on the rclk-domain interface. Same timing protocol as
// fifo_wr_driver (see that file): optional idle cycles, drive rinc=1 right
// after an edge, sample the response at the next edge, default rinc back to 0
// (overridden in the same time step by a back-to-back item).
//
// The response returned to the sequence includes rempty as seen by the DUT and
// the popped data. Reads while empty are driven on purpose by the underflow
// tests; the DUT must ignore them.
// -----------------------------------------------------------------------------
class fifo_rd_driver extends uvm_driver #(fifo_rd_item);
  `uvm_component_utils(fifo_rd_driver)

  fifo_rd_agent_cfg  cfg;
  virtual fifo_rd_if vif;

  protected time last_edge_t = '1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) begin
      `uvm_fatal("NOCFG", "fifo_rd_driver: cfg handle not set by the agent")
    end
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.rinc <= 1'b0;
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  protected task sync_to_edge();
    if (last_edge_t != $time) begin
      @(vif.drv_cb);
      last_edge_t = $time;
    end
  endtask

  protected task wait_edge();
    @(vif.drv_cb);
    last_edge_t = $time;
  endtask

  protected task drive_item(fifo_rd_item t);
    if (vif.rrst_n !== 1'b1) begin
      @(posedge vif.rrst_n);
    end
    sync_to_edge();

    repeat (t.delay) begin
      vif.drv_cb.rinc <= 1'b0;
      wait_edge();
    end

    vif.drv_cb.rinc <= 1'b1;
    wait_edge();

    t.rinc         = 1'b1;
    t.empty        = vif.drv_cb.rempty;
    t.almost_empty = vif.drv_cb.ralmost_empty;
    t.data         = vif.drv_cb.rdata;

    vif.drv_cb.rinc <= 1'b0;

    `uvm_info("RD_DRV", t.convert2string(), UVM_HIGH)
  endtask

endclass : fifo_rd_driver
