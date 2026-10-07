// -----------------------------------------------------------------------------
// fifo_env.svh
//
//   fifo_env
//    |-- wr_agent (wclk)  : sqr, drv, mon --ap--+--> scoreboard.wr_export
//    |                                          +--> coverage.wr_export
//    |-- rd_agent (rclk)  : sqr, drv, mon --ap--+--> scoreboard.rd_export
//    |                                          +--> coverage.rd_export
//    |-- scoreboard
//    |-- coverage
//    `-- vsqr (virtual sequencer: wr_sqr, rd_sqr, cfg)
// -----------------------------------------------------------------------------
class fifo_env extends uvm_env;
  `uvm_component_utils(fifo_env)

  fifo_env_cfg    cfg;
  fifo_wr_agent   wr_agent;
  fifo_rd_agent   rd_agent;
  fifo_scoreboard sb;
  fifo_coverage   cov;
  fifo_vsequencer vsqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(fifo_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NOCFG", "fifo_env: no 'cfg' in uvm_config_db")
    end

    // Agent configs are scoped to their own agent only.
    uvm_config_db #(fifo_wr_agent_cfg)::set(this, "wr_agent", "cfg", cfg.wr_cfg);
    uvm_config_db #(fifo_rd_agent_cfg)::set(this, "rd_agent", "cfg", cfg.rd_cfg);

    wr_agent = fifo_wr_agent::type_id::create("wr_agent", this);
    rd_agent = fifo_rd_agent::type_id::create("rd_agent", this);
    vsqr     = fifo_vsequencer::type_id::create("vsqr", this);

    if (cfg.has_scoreboard) begin
      sb     = fifo_scoreboard::type_id::create("sb", this);
      sb.cfg = cfg;
    end
    if (cfg.has_coverage) begin
      cov     = fifo_coverage::type_id::create("cov", this);
      cov.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    vsqr.wr_sqr = wr_agent.sqr;
    vsqr.rd_sqr = rd_agent.sqr;
    vsqr.cfg    = cfg;

    if (cfg.has_scoreboard) begin
      wr_agent.ap.connect(sb.wr_export);
      rd_agent.ap.connect(sb.rd_export);
    end
    if (cfg.has_coverage) begin
      wr_agent.ap.connect(cov.wr_export);
      rd_agent.ap.connect(cov.rd_export);
    end
  endfunction

endclass : fifo_env
