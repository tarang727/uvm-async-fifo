// -----------------------------------------------------------------------------
// fifo_vsequencer.svh
//
// Virtual sequencer: holds handles to the two real sequencers (one per clock
// domain) and the env config. Virtual sequences run here and start agent
// sequences on wr_sqr / rd_sqr, which is how cross-domain scenarios
// ("fill on the write side, then drain on the read side") are coordinated.
// -----------------------------------------------------------------------------
class fifo_vsequencer extends uvm_sequencer;
  `uvm_component_utils(fifo_vsequencer)

  fifo_wr_sequencer wr_sqr;
  fifo_rd_sequencer rd_sqr;
  fifo_env_cfg      cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : fifo_vsequencer
