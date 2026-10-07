// -----------------------------------------------------------------------------
// tb_top.sv
//
// Static top level:
//   * clock generator interface (periods from plusargs, changeable at runtime)
//   * one interface per clock domain
//   * the DUT, parameterized from fifo_tb_params_pkg
//   * virtual interfaces published to uvm_config_db, then run_test()
//
// Plusargs:
//   +UVM_TESTNAME=<test>       which test to run (standard UVM)
//   +WCLK_PERIOD_PS=<n>        write clock period in ps   (default 10000)  [fifo_clk_if]
//   +RCLK_PERIOD_PS=<n>        read clock period in ps    (default 13000)  [fifo_clk_if]
//   +RCLK_PHASE_PS=<n>         rclk start offset in ps    (default 1234)   [fifo_clk_if]
//   +DUMP                      write a VCD/FST waveform (simulator dependent)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_tb_params_pkg::*;
  import fifo_test_pkg::*;

  fifo_clk_if clk_if ();
  fifo_wr_if  wr_if  (.wclk(clk_if.wclk));
  fifo_rd_if  rd_if  (.rclk(clk_if.rclk));

  fifo_top #(
    .DATA_WIDTH          (DATA_WIDTH),
    .ADDR_WIDTH          (ADDR_WIDTH),
    .ALMOST_FULL_THRESH  (AF_THRESH),
    .ALMOST_EMPTY_THRESH (AE_THRESH)
  ) dut (
    .wclk          (clk_if.wclk),
    .wrst_n        (wr_if.wrst_n),
    .winc          (wr_if.winc),
    .wdata         (wr_if.wdata),
    .wfull         (wr_if.wfull),
    .walmost_full  (wr_if.walmost_full),
    .rclk          (clk_if.rclk),
    .rrst_n        (rd_if.rrst_n),
    .rinc          (rd_if.rinc),
    .rdata         (rd_if.rdata),
    .rempty        (rd_if.rempty),
    .ralmost_empty (rd_if.ralmost_empty)
  );

  initial begin
    // Clock plusargs are parsed inside fifo_clk_if.
    if ($test$plusargs("DUMP")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end

    uvm_config_db #(virtual fifo_wr_if )::set(null, "uvm_test_top", "wr_vif",  wr_if);
    uvm_config_db #(virtual fifo_rd_if )::set(null, "uvm_test_top", "rd_vif",  rd_if);
    uvm_config_db #(virtual fifo_clk_if)::set(null, "uvm_test_top", "clk_vif", clk_if);

    run_test();
  end

endmodule : tb_top
