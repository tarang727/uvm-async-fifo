#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_regression.sh - build once, run every test (optionally several seeds),
# print a PASS/FAIL table. Exit status is non-zero if any run failed.
#
#   ./run_regression.sh                       # verilator, seed 1
#   ./run_regression.sh --sim questa --seeds "1 2 3"
#
# A run PASSES only if its log contains "TEST PASSED" (printed by
# fifo_base_test::report_phase when there were zero UVM_ERROR/UVM_FATAL) and no
# simulator-level error lines. A crash, timeout or early abort has no PASSED
# line and is therefore a failure.
# -----------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"

SIM=verilator
SEEDS="1"
TIMEOUT=900

TESTS=(
  fifo_smoke_test
  fifo_random_test
  fifo_full_empty_test
  fifo_overflow_underflow_test
  fifo_simul_rw_test
  fifo_clock_ratio_test
  fifo_reset_test
)

while [ $# -gt 0 ]; do
  case "$1" in
    --sim)     SIM="$2";   shift 2 ;;
    --seeds)   SEEDS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

echo "== building ($SIM)"
make --no-print-directory SIM="$SIM" build > /dev/null || { echo "BUILD FAILED"; exit 1; }

mkdir -p logs
fail=0
summary="logs/regression_${SIM}.txt"
printf "%-32s %6s  %-6s  %s\n" "TEST" "SEED" "RESULT" "NOTES" | tee "$summary"
for t in "${TESTS[@]}"; do
  for s in $SEEDS; do
    log="logs/${t}_${s}.log"
    timeout "$TIMEOUT" make --no-print-directory SIM="$SIM" TEST="$t" SEED="$s" run > /dev/null 2>&1
    if grep -q "TEST PASSED" "$log" 2>/dev/null && ! grep -qE "^%Error|\*E,|Error-\[" "$log"; then
      res=PASS
      notes=$(grep -ho "writes=[0-9]* reads=[0-9]* matches=[0-9]* mismatches=[0-9]*" "$log" | head -1)
    else
      res=FAIL; fail=1
      notes=$(grep -hm1 -E "UVM_(ERROR|FATAL) [^:]|%Error" "$log" 2>/dev/null | cut -c1-90)
    fi
    printf "%-32s %6s  %-6s  %s\n" "$t" "$s" "$res" "$notes" | tee -a "$summary"
  done
done

[ $fail -eq 0 ] && echo "== ALL PASSED" || echo "== FAILURES (see logs/)"
exit $fail
