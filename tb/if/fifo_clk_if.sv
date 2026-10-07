// -----------------------------------------------------------------------------
// fifo_clk_if.sv
//
// Generates the two independent clocks. Periods are run-time variables, so:
//   * they are initialized from plusargs (+WCLK_PERIOD_PS, +RCLK_PERIOD_PS,
//     +RCLK_PHASE_PS) here, before the first delay is computed. Parsing them
//     in the same initial block as the generator avoids a time-0 race with
//     any other initial block that might set them, and
//   * a test can change them on the fly with set_periods() (used by
//     fifo_clock_ratio_test to sweep several ratios in one simulation).
//
// The new period takes effect at the next half-cycle boundary. Changing a clock
// while the FIFO is busy is legal for an async FIFO (each side only ever sees
// its own clock), but the clock_ratio test still quiesces traffic first so
// that coverage per ratio is attributable.
//
// The RCLK phase offset avoids the two clocks having coincident edges for
// equal periods, which would be an unrealistically "friendly" alignment.
// -----------------------------------------------------------------------------
interface fifo_clk_if;

  logic wclk = 1'b0;
  logic rclk = 1'b0;

  int unsigned wclk_period_ps = 10_000;  // 100 MHz
  int unsigned rclk_period_ps = 13_000;  // ~76.9 MHz
  int unsigned rclk_phase_ps  = 1_234;

  function automatic void set_periods(int unsigned w_ps, int unsigned r_ps);
    if (w_ps < 2 || r_ps < 2) begin
      $fatal(1, "fifo_clk_if: clock periods must be >= 2 ps (got %0d, %0d)", w_ps, r_ps);
    end
    wclk_period_ps = w_ps;
    rclk_period_ps = r_ps;
  endfunction

  // High phase = floor(period/2), low phase = the remainder, so odd periods
  // still sum to exactly one period.
  initial begin : gen_wclk
    int unsigned p;
    if ($value$plusargs("WCLK_PERIOD_PS=%d", p)) wclk_period_ps = p;
    if ($value$plusargs("RCLK_PERIOD_PS=%d", p)) rclk_period_ps = p;
    if ($value$plusargs("RCLK_PHASE_PS=%d",  p)) rclk_phase_ps  = p;
    set_periods(wclk_period_ps, rclk_period_ps);   // range check
    forever begin
      #(wclk_period_ps / 2 * 1ps);
      wclk = 1'b1;
      #((wclk_period_ps - wclk_period_ps / 2) * 1ps);
      wclk = 1'b0;
    end
  end

  initial begin : gen_rclk
    #0;  // let gen_wclk parse the plusargs first (same time step, ordered)
    #(rclk_phase_ps * 1ps);
    forever begin
      #(rclk_period_ps / 2 * 1ps);
      rclk = 1'b1;
      #((rclk_period_ps - rclk_period_ps / 2) * 1ps);
      rclk = 1'b0;
    end
  end

endinterface : fifo_clk_if
