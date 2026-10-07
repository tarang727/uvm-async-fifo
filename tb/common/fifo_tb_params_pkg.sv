// -----------------------------------------------------------------------------
// fifo_tb_params_pkg.sv
//
// Single source of truth for the DUT configuration used by the testbench.
// tb_top uses these to parameterize the DUT; interfaces, items, scoreboard and
// coverage use them for widths and bin boundaries.
//
// Design decision: the testbench is configured with package localparams (which
// can be overridden at compile time with +define+FIFO_DATA_WIDTH=... etc.)
// instead of parameterized interfaces + parameterized UVM classes. Parameterized
// classes work, but they make every `uvm_component_utils, config_db key and
// virtual-interface type carry the parameter list, which is noisy and a common
// source of factory-override mistakes. For a single DUT configuration per
// compile, a package is simpler and just as flexible.
// -----------------------------------------------------------------------------
`ifndef FIFO_DATA_WIDTH
  `define FIFO_DATA_WIDTH 8
`endif
`ifndef FIFO_ADDR_WIDTH
  `define FIFO_ADDR_WIDTH 4
`endif

package fifo_tb_params_pkg;

  localparam int DATA_WIDTH = `FIFO_DATA_WIDTH;
  localparam int ADDR_WIDTH = `FIFO_ADDR_WIDTH;
  localparam int DEPTH      = 1 << ADDR_WIDTH;

  // Almost-full when write-side occupancy >= AF_THRESH;
  // almost-empty when read-side occupancy <= AE_THRESH.
  // The coverage fill-level bins assume AE_THRESH < AF_THRESH - 1, which holds
  // for DEPTH >= 8 with these defaults.
  localparam int AF_THRESH  = DEPTH - 2;
  localparam int AE_THRESH  = 2;

  typedef logic [DATA_WIDTH-1:0] data_t;

  // Alternating bit patterns for any DATA_WIDTH (0101... and 1010...).
  // Built with a constant function so odd widths also work.
  function automatic data_t alt_pattern(bit lsb_one);
    data_t p;
    for (int i = 0; i < DATA_WIDTH; i++) begin
      p[i] = lsb_one ? ~i[0] : i[0];
    end
    return p;
  endfunction

  localparam data_t PAT_ZEROS  = '0;
  localparam data_t PAT_ONES   = '1;
  localparam data_t PAT_ALT_01 = alt_pattern(1'b1);  // ...0101 (LSB = 1)
  localparam data_t PAT_ALT_10 = alt_pattern(1'b0);  // ...1010 (LSB = 0)

  // Data "kind" used by the write item to bias stimulus towards the corner
  // patterns that the coverage model asks for.
  typedef enum bit [2:0] {
    DATA_RANDOM,
    DATA_ZEROS,
    DATA_ONES,
    DATA_ALT_01,
    DATA_ALT_10
  } data_kind_e;

endpackage : fifo_tb_params_pkg
