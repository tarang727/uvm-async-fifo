// -----------------------------------------------------------------------------
// fifo_wr_driver.svh
//
// Drives write requests on the wclk-domain interface.
//
// Protocol per item:
//   1. Make sure we are aligned to a wclk edge (see sync_to_edge()).
//   2. Idle for `delay` cycles (winc = 0).
//   3. Drive winc=1 / wdata right after an edge, so the DUT samples them at
//      the NEXT edge.
//   4. At that next edge, sample wfull through the clocking block (the value
//      the DUT saw) and return it to the sequence in the same item.
//   5. Default winc back to 0. If the sequence immediately supplies another
//      item with delay 0, that item's drive happens in the same time step and
//      overrides the 0 (last clocking drive wins), giving true back-to-back
//      writes with no bubble.
//
// A write while full is still driven: the DUT must ignore it. That is exactly
// what the overflow tests exercise.
// -----------------------------------------------------------------------------
class fifo_wr_driver extends uvm_driver #(fifo_wr_item);
  `uvm_component_utils(fifo_wr_driver)

  fifo_wr_agent_cfg  cfg;
  virtual fifo_wr_if vif;

  // Simulation time of the last clock edge this driver itself waited for.
  // Used to decide whether we are still "at" that edge when a new item arrives.
  protected time last_edge_t = '1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) begin
      `uvm_fatal("NOCFG", "fifo_wr_driver: cfg handle not set by the agent")
    end
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    // Outputs already default to 0 through the interface declaration; the
    // clocking drives below keep them that way until the first item.
    vif.drv_cb.winc <= 1'b0;
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  // Wait one edge unless we are still in the time step of the last edge we
  // observed. This prevents a mid-cycle drive (which would only take effect at
  // the next edge, so the result would be sampled one edge too early), while
  // still allowing zero-bubble back-to-back items.
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

  protected task drive_item(fifo_wr_item t);
    // The write domain must be out of reset before we touch it.
    if (vif.wrst_n !== 1'b1) begin
      @(posedge vif.wrst_n);
    end
    sync_to_edge();

    repeat (t.delay) begin
      vif.drv_cb.winc <= 1'b0;
      wait_edge();
    end

    vif.drv_cb.winc  <= 1'b1;
    vif.drv_cb.wdata <= t.data;
    wait_edge();

    // Response: what the DUT saw at the edge that consumed this request.
    t.winc        = 1'b1;
    t.full        = vif.drv_cb.wfull;
    t.almost_full = vif.drv_cb.walmost_full;

    vif.drv_cb.winc <= 1'b0;

    `uvm_info("WR_DRV", t.convert2string(), UVM_HIGH)
  endtask

endclass : fifo_wr_driver
