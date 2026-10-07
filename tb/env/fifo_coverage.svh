// -----------------------------------------------------------------------------
// fifo_coverage.svh
//
// Functional coverage collector. Subscribes to both monitors and samples
// covergroups from the observed transactions (never from stimulus, so
// coverage reflects what the DUT actually did).
//
// Covergroups take their values as explicit sample() arguments instead of
// referring to class members. This keeps each covergroup a pure function of
// its inputs, makes the sampling point obvious in the code, and is the most
// portable style across simulators.
//
// What is covered (see docs/verification_plan.md for the mapping):
//   cg_wr       : write-op kind (idle / write / write-when-full), wfull and
//                 walmost_full values and rise/fall transitions, fill level,
//                 clock-ratio crossed with the interesting flags/ops.
//   cg_rd       : same for the read side (read-when-empty, rempty,
//                 ralmost_empty).
//   cg_wr_data  : data patterns on accepted writes, and whether the write
//                 happened while the reader was active (simultaneous access).
//   cg_rd_data  : data patterns on popped data, read while writer active.
//
// Fill level is tracked with a local counter (accepted writes - accepted
// reads). It is the TRUE occupancy as seen by the testbench, independent of
// the DUT's pessimistic flags.
// -----------------------------------------------------------------------------
typedef enum bit [2:0] {
  RATIO_W_FASTER_2X,   // wclk at least 2x faster than rclk
  RATIO_W_FASTER,      // wclk faster, less than 2x
  RATIO_EQUAL,         // same frequency (phase offset only)
  RATIO_R_FASTER,      // rclk faster, less than 2x
  RATIO_R_FASTER_2X    // rclk at least 2x faster than wclk
} clk_ratio_e;

typedef enum bit [1:0] {
  OP_IDLE,             // flag change with no request on this edge
  OP_ACCEPTED,         // request accepted (write when !full / read when !empty)
  OP_BLOCKED           // write-when-full / read-when-empty (must be ignored)
} op_kind_e;

class fifo_coverage extends uvm_component;
  `uvm_component_utils(fifo_coverage)

  uvm_analysis_imp_wr #(fifo_wr_item, fifo_coverage) wr_export;
  uvm_analysis_imp_rd #(fifo_rd_item, fifo_coverage) rd_export;

  fifo_env_cfg cfg;

  protected int unsigned level;       // true occupancy
  protected bit          wr_active;   // writer requested on its latest edge
  protected bit          rd_active;   // reader requested on its latest edge

  // ---------------------------------------------------------------------------
  covergroup cg_wr with function sample(op_kind_e   op,
                                        bit         full,
                                        bit         afull,
                                        int unsigned lvl,
                                        clk_ratio_e ratio);
    option.per_instance = 1;
    option.name         = "cg_wr";

    cp_op : coverpoint op {
      bins idle            = {OP_IDLE};
      bins write           = {OP_ACCEPTED};
      bins write_when_full = {OP_BLOCKED};
    }
    cp_full : coverpoint full {
      bins deasserted = {1'b0};
      bins asserted   = {1'b1};
    }
    cp_full_tr : coverpoint full {
      bins rise = (1'b0 => 1'b1);
      bins fall = (1'b1 => 1'b0);
    }
    cp_afull : coverpoint afull {
      bins deasserted = {1'b0};
      bins asserted   = {1'b1};
    }
    cp_afull_tr : coverpoint afull {
      bins rise = (1'b0 => 1'b1);
      bins fall = (1'b1 => 1'b0);
    }
    cp_level : coverpoint lvl {
      bins empty        = {0};
      bins almost_empty = {[1 : AE_THRESH]};
      bins middle       = {[AE_THRESH + 1 : AF_THRESH - 1]};
      bins almost_full  = {[AF_THRESH : DEPTH - 1]};
      bins full         = {DEPTH};
    }
    cp_ratio : coverpoint ratio;

    x_ratio_full : cross cp_ratio, cp_full;
    x_ratio_op   : cross cp_ratio, cp_op;
  endgroup

  // ---------------------------------------------------------------------------
  covergroup cg_rd with function sample(op_kind_e   op,
                                        bit         empty,
                                        bit         aempty,
                                        int unsigned lvl,
                                        clk_ratio_e ratio);
    option.per_instance = 1;
    option.name         = "cg_rd";

    cp_op : coverpoint op {
      bins idle            = {OP_IDLE};
      bins read            = {OP_ACCEPTED};
      bins read_when_empty = {OP_BLOCKED};
    }
    cp_empty : coverpoint empty {
      bins deasserted = {1'b0};
      bins asserted   = {1'b1};
    }
    cp_empty_tr : coverpoint empty {
      bins rise = (1'b0 => 1'b1);
      bins fall = (1'b1 => 1'b0);
    }
    cp_aempty : coverpoint aempty {
      bins deasserted = {1'b0};
      bins asserted   = {1'b1};
    }
    cp_aempty_tr : coverpoint aempty {
      bins rise = (1'b0 => 1'b1);
      bins fall = (1'b1 => 1'b0);
    }
    cp_level : coverpoint lvl {
      bins empty        = {0};
      bins almost_empty = {[1 : AE_THRESH]};
      bins middle       = {[AE_THRESH + 1 : AF_THRESH - 1]};
      bins almost_full  = {[AF_THRESH : DEPTH - 1]};
      bins full         = {DEPTH};
    }
    cp_ratio : coverpoint ratio;

    x_ratio_empty : cross cp_ratio, cp_empty;
    x_ratio_op    : cross cp_ratio, cp_op;
  endgroup

  // ---------------------------------------------------------------------------
  covergroup cg_wr_data with function sample(data_t d, bit other_side_active);
    option.per_instance = 1;
    option.name         = "cg_wr_data";

    cp_pattern : coverpoint d {
      bins zeros  = {PAT_ZEROS};
      bins ones   = {PAT_ONES};
      bins alt_01 = {PAT_ALT_01};
      bins alt_10 = {PAT_ALT_10};
    }
    cp_simultaneous : coverpoint other_side_active {
      bins write_only          = {1'b0};
      bins write_while_reading = {1'b1};
    }
  endgroup

  covergroup cg_rd_data with function sample(data_t d, bit other_side_active);
    option.per_instance = 1;
    option.name         = "cg_rd_data";

    cp_pattern : coverpoint d {
      bins zeros  = {PAT_ZEROS};
      bins ones   = {PAT_ONES};
      bins alt_01 = {PAT_ALT_01};
      bins alt_10 = {PAT_ALT_10};
    }
    cp_simultaneous : coverpoint other_side_active {
      bins read_only           = {1'b0};
      bins read_while_writing  = {1'b1};
    }
  endgroup

  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wr_export  = new("wr_export", this);
    rd_export  = new("rd_export", this);
    cg_wr      = new();
    cg_rd      = new();
    cg_wr_data = new();
    cg_rd_data = new();
  endfunction

  // Classify the current clock relationship from the live clock periods.
  function clk_ratio_e current_ratio();
    int unsigned w = cfg.clk_vif.wclk_period_ps;
    int unsigned r = cfg.clk_vif.rclk_period_ps;
    if (w == r)      return RATIO_EQUAL;
    if (2 * w <= r)  return RATIO_W_FASTER_2X;   // smaller period = faster
    if (w < r)       return RATIO_W_FASTER;
    if (2 * r <= w)  return RATIO_R_FASTER_2X;
    return RATIO_R_FASTER;
  endfunction

  // ---------------------------------------------------------------------------
  function void write_wr(fifo_wr_item t);
    op_kind_e op;
    if (t.reset_evt) begin
      level     = 0;
      wr_active = 1'b0;
      return;
    end

    op = !t.winc ? OP_IDLE : (t.full ? OP_BLOCKED : OP_ACCEPTED);
    // Sample with the level BEFORE this write is applied (the state the DUT
    // was in when it made the accept/drop decision).
    cg_wr.sample(op, t.full, t.almost_full, level, current_ratio());

    if (op == OP_ACCEPTED) begin
      cg_wr_data.sample(t.data, rd_active);
      level++;
    end
    wr_active = t.winc;
  endfunction

  function void write_rd(fifo_rd_item t);
    op_kind_e op;
    if (t.reset_evt) begin
      level     = 0;
      rd_active = 1'b0;
      return;
    end

    op = !t.rinc ? OP_IDLE : (t.empty ? OP_BLOCKED : OP_ACCEPTED);
    cg_rd.sample(op, t.empty, t.almost_empty, level, current_ratio());

    if (op == OP_ACCEPTED) begin
      cg_rd_data.sample(t.data, wr_active);
      if (level > 0) level--;   // scoreboard flags the underflow if this is 0
    end
    rd_active = t.rinc;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf(
      "functional coverage: cg_wr=%0.2f%% cg_rd=%0.2f%% cg_wr_data=%0.2f%% cg_rd_data=%0.2f%%",
      cg_wr.get_inst_coverage(), cg_rd.get_inst_coverage(),
      cg_wr_data.get_inst_coverage(), cg_rd_data.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : fifo_coverage
