# Walkthrough: Design and Verification Decisions

This is a study guide for the repo. It explains why the code is written the
way it is, roughly in the order you would be asked about it, and ends with
interview questions and model answers.

Contents

1. [The problem an async FIFO solves](#1-the-problem-an-async-fifo-solves)
2. [Metastability and MTBF](#2-metastability-and-mtbf)
3. [Why 2-flop synchronizers](#3-why-2-flop-synchronizers)
4. [Why Gray code](#4-why-gray-code)
5. [Pointer width and full/empty detection](#5-pointer-width-and-fullempty-detection)
6. [Why full/empty are pessimistic, and why that is safe](#6-why-fullempty-are-pessimistic-and-why-that-is-safe)
7. [Almost-full / almost-empty](#7-almost-full--almost-empty)
8. [Reset](#8-reset)
9. [RTL module split](#9-rtl-module-split)
10. [Testbench architecture](#10-testbench-architecture)
11. [UVM phasing used](#11-uvm-phasing-used)
12. [Driver/monitor timing and clocking blocks](#12-drivermonitor-timing-and-clocking-blocks)
13. [Why the scoreboard is built this way](#13-why-the-scoreboard-is-built-this-way)
14. [Assertions: what goes in SVA vs the scoreboard](#14-assertions-what-goes-in-sva-vs-the-scoreboard)
15. [Coverage and how it maps to the plan](#15-coverage-and-how-it-maps-to-the-plan)
16. [Proving the checkers work: mutation testing](#16-proving-the-checkers-work-mutation-testing)
17. [Running UVM on Verilator](#17-running-uvm-on-verilator)
18. [Interview questions and model answers](#18-interview-questions-and-model-answers)

---

## 1. The problem an async FIFO solves

Two blocks run on unrelated clocks, for example a 250 MHz PCIe-side block
and a 400 MHz core. Data must cross between them without loss, without
duplication, and without either side sampling a signal while it is changing.

A FIFO decouples them. The writer only ever looks at its own clock and a
`wfull` flag; the reader only ever looks at its own clock and an `rempty`
flag. The only signals that cross the boundary are the two **pointers**,
and the design is entirely about crossing those safely.

The data itself does not need a synchronizer. A storage location is only
read after the reader has learned, through the synchronized write pointer,
that the location was written, which is several cycles after the write
completed. By then the location is stable.

## 2. Metastability and MTBF

A flip-flop has a setup/hold window around its clock edge. If D changes
inside that window, the output can hang at an intermediate voltage
(**metastable**) for an unbounded but exponentially unlikely time before it
resolves to 0 or 1. Between unrelated clocks you cannot prevent D changing
inside the window, so you have to tolerate it.

The standard estimate:

```
MTBF = e^(t_r / tau) / (T_w * f_clk * f_data)
```

* `t_r`: resolution time available (about one destination clock period minus
  setup and clock-to-q of the next flop)
* `tau`: the flop's regeneration time constant (technology dependent,
  picoseconds)
* `T_w`: the metastability window
* `f_clk`, `f_data`: destination clock frequency and data toggle rate

The key point is that MTBF is **exponential in resolution time**. Adding a
second flop gives the first flop's output a full extra cycle to resolve,
which multiplies MTBF by roughly `e^(T_clk / tau)`. That typically moves it
from seconds to far longer than the age of the universe. At very high
frequencies, or for safety-critical designs, a third flop is added.

Two consequences:

* **The two synchronizer flops must sit next to each other** with no logic
  between them, otherwise you are spending the resolution time on logic.
  In a real flow they are often a dedicated library cell or carry a
  `dont_touch`/`ASYNC_REG` attribute.
* **RTL simulation has no metastability.** It is zero-delay and two-valued at
  the edge. A design with only one synchronizer flop passes every functional
  test. This repo catches that with a structural assertion (S1/S2, section 14),
  but in production that is a CDC tool's job.

## 3. Why 2-flop synchronizers

`sync_w2r.sv` / `sync_r2w.sv` are two flops each, reset by the
**destination** domain's reset. Two flops is the standard trade-off: one
cycle of resolution time, and two cycles of latency. The latency is why the
flags are pessimistic (section 6).

A 2-flop synchronizer only makes a **single bit** safe. For a multi-bit bus,
each bit resolves independently, so with a binary count you could capture a
mixture of old and new bits. That is why the pointers are Gray coded.

## 4. Why Gray code

In Gray code, consecutive values differ in exactly one bit. If the
destination samples the pointer while it is changing, only one bit is
uncertain, and it resolves to either the old value or the new value. **Both
are real pointer values.** The worst case is seeing the pointer one step
late.

With binary, `0111 -> 1000` changes four bits. A sample during that change
could produce `1111`, `0000`, or any other combination: a pointer value
that never existed, which can make full/empty completely wrong.

Implementation details (Cummings, SNUG 2002, "style #2"):

* Each side keeps a **binary** pointer (easy to increment and use as an
  address) and a **registered Gray** copy. The Gray value must come straight
  from a flop. If it were combinational from the binary counter, glitches
  could make several bits change transiently, and the synchronizer might
  capture a glitch.
* `gray = bin ^ (bin >> 1)`; `bin[i] = ^gray[N:i]` (XOR of all higher bits).
* Gray code is only "one bit per step" if the counter wraps at a power of
  two. That is why depth is `2**ADDR_WIDTH`. Non-power-of-two async FIFOs
  need different encodings.
* **The synchronized pointer is not one step at a time.** If the writer is
  faster, `wptr` can advance several times between two `rclk` edges, and
  `rq2_wptr` jumps. That is fine, because each sampled value is a value
  `wptr` actually held. The SVA therefore checks single-bit change only on
  the source pointers (G1/G2) and not on the synchronized ones; see the note
  at the bottom of `fifo_sva.sv`.

## 5. Pointer width and full/empty detection

The pointers are `ADDR_WIDTH + 1` bits. The low bits address memory; the
extra MSB counts wraps. With equal address bits:

* **Same MSB**: the writer and reader are on the same lap, so the FIFO is **empty**.
* **Different MSB**: the writer is one full lap ahead, so the FIFO is **full**.

Without the extra bit, "full" and "empty" would both look like `waddr == raddr`.

In **binary**, "full" means the pointers differ only in the MSB. In **Gray**,
adding `2^N` to an (N+1)-bit value inverts the **top two** bits and leaves the
rest unchanged (because of how the reflected code mirrors). So:

```systemverilog
empty = (rgraynext == rq2_wptr);
full  = (wgraynext == {~wq2_rptr[N:N-1], wq2_rptr[N-2:0]});
```

A common bug is inverting only the MSB, as you would in binary. Mutant M2
removes the inversion entirely; see section 16.

Both flags are **registered from the next pointer value** (`wgraynext`,
`rgraynext`). As a result, `wfull` asserts on the same edge that writes the
last slot, and `rempty` on the same edge that pops the last entry. There is
never a cycle where the FIFO is full but `wfull` is low.

## 6. Why full/empty are pessimistic, and why that is safe

`wfull` is computed from `wq2_rptr`, which is the read pointer from two or
three `wclk` cycles ago. The reader may since have freed slots that the
writer does not know about yet. So:

* **Assertion of `wfull` is exact**, because it is caused by the writer's own
  write, which it knows about immediately.
* **De-assertion of `wfull` is late**, because it waits for the read pointer
  to cross the synchronizer.

Late de-assertion costs a few cycles of throughput. Early de-assertion
would be an overflow. The design can only err in the safe direction. The
same holds for `rempty`, which asserts exactly and de-asserts late.

The testbench mirrors this split:

* The scoreboard checks the **safe direction on every cycle**: a flag may be
  on when it "doesn't need to be", but never off when it must be on
  (SB-FLAG).
* Exact flag values are checked only at **quiet points** after the
  synchronizers settle (`check_flags()` in the virtual sequences).

This is also why pessimism can starve a slow reader: with a 4x faster
writer, the read side sees `rempty` drop late, and back-to-back reads see
gaps. The `cg_rd` ratio crosses confirm those situations occurred.

## 7. Almost-full / almost-empty

Each side converts the synchronized remote Gray pointer back to binary and
subtracts it from its own (next) pointer, modulo `2^(N+1)`:

```
write side: wcount = wbinnext - bin(wq2_rptr)   (>= true occupancy)
read side : rcount = bin(rq2_wptr) - rbinnext   (<= true occupancy)
```

The write side's estimate is high (stale read pointer), and the read side's
estimate is low (stale write pointer). Both errors point the safe way:
`walmost_full` may assert early or release late, and `ralmost_empty` likewise.
The thresholds are parameters (`ALMOST_FULL_THRESH`, `ALMOST_EMPTY_THRESH`);
the flags are registered like full/empty.

Gray-to-binary conversion is a chain of XORs whose depth is `ADDR_WIDTH`.
That is negligible for small FIFOs. For deep FIFOs at high frequency you
would pipeline it or synchronize a separate binary count.

## 8. Reset

* Asynchronous assert, active low, one reset per domain. Synchronizer flops
  are reset by the destination domain.
* `rempty` and `ralmost_empty` reset to **1**; `wfull` and `walmost_full`
  reset to **0**.
* **Both sides must be reset together.** Resetting only the write side would
  leave the read side with a stale view of the pointers. That is an
  integration requirement documented in `fifo_top.sv` and listed as out of
  scope in the verification plan.
* The storage array has no reset. Real RAMs do not have one, and the pointers
  guarantee that unwritten locations are never presented as valid.
* **TB subtlety that was found during bring-up:** the interface initially
  declared `wrst_n = 0` at time 0. With `always_ff @(posedge clk or negedge
  rst_n)`, a signal that *starts* at 0 never has a negedge, so the reset
  branch does not run until the first clock edge. In a 2-state simulator the
  flops silently start at 0, which is wrong for `rempty`, whose reset value
  is 1. SVA R3 caught this immediately. The fix is to initialize resets to 1
  and have the test drive them to 0 at time 0, producing a real edge. The
  comment in `fifo_wr_if.sv` explains it.

## 9. RTL module split

| Module | Clock | Contents |
|--------|-------|----------|
| `fifo_mem` | wclk (write) / none (read) | storage, write enable gated by `!wfull` |
| `sync_r2w` | wclk | 2-flop sync of `rptr` |
| `sync_w2r` | rclk | 2-flop sync of `wptr` |
| `wptr_full` | wclk | binary/Gray write pointer, `wfull`, `walmost_full` |
| `rptr_empty` | rclk | binary/Gray read pointer, `rempty`, `ralmost_empty` |
| `fifo_top` | both | wiring only |

Every module except `fifo_top` and `fifo_mem` is in exactly one clock
domain. That makes the design easy for synthesis constraints (one false path
or max-delay constraint per Gray bus) and easy for CDC tools to recognize.

Read is **first-word fall-through** (FWFT): `rdata = mem[raddr]`
combinationally, so data is valid whenever `rempty=0`, and `rinc` pops it.
The monitor therefore samples `rdata` at the same edge as `rinc`.

## 10. Testbench architecture

```
tb_top
 |-- fifo_clk_if    (wclk/rclk generators, periods changeable at runtime)
 |-- fifo_wr_if     (wclk domain, drv_cb / mon_cb clocking blocks)
 |-- fifo_rd_if     (rclk domain)
 |-- fifo_top dut   (+ bind fifo_sva)
 `-- run_test()
      uvm_test_top (fifo_*_test)
       `-- env
            |-- wr_agent: sqr, drv, mon --ap--> sb.wr_export, cov.wr_export
            |-- rd_agent: sqr, drv, mon --ap--> sb.rd_export, cov.rd_export
            |-- sb   (fifo_scoreboard)
            |-- cov  (fifo_coverage)
            `-- vsqr (virtual sequencer -> wr_sqr, rd_sqr, cfg)
```

Decisions worth being able to defend:

* **One agent per clock domain.** An agent is a protocol on one interface,
  and an interface belongs to one clock. Putting both ports in one agent
  would mean one driver serving two unrelated clocks.
* **Both agents active.** Reads are stimulus too: read timing determines
  whether the FIFO fills, so the reader needs a sequencer.
* **Config objects carry the virtual interface.** The test does the
  `config_db` lookup once, puts the vif in `fifo_wr_agent_cfg`, and the agent
  passes the cfg handle to its driver and monitor. That gives one source of
  truth and no string-keyed lookups scattered through components.
* **The same item class is used for stimulus and observation.** The driver
  writes back the response (`full`/`empty` as seen by the DUT, popped
  `data`), so sequences can react ("write until a write is dropped") without
  peeking at the interface.
* **Package localparams instead of parameterized classes.** One DUT
  configuration per compile, overridable with `+define+FIFO_ADDR_WIDTH=...`.
  This avoids `#(...)` on every class, factory registration and vif type.
* **Virtual sequences coordinate the two domains.** Agent sequences are
  single-domain and reusable (`fifo_wr_burst_seq`, `fifo_rd_count_seq`, ...);
  `fifo_base_vseq` composes them into scenarios and owns the directed flag
  checks.
* **Tests contain almost nothing.** Each test chooses a virtual sequence and
  a couple of config knobs. Reset generation, the watchdog and PASS/FAIL
  reporting live in `fifo_base_test`.

## 11. UVM phasing used

| Phase | Who | What |
|-------|-----|------|
| `build_phase` (top-down) | test | gets vifs from `config_db`, builds `fifo_env_cfg`, calls `configure()` hook, sets cfg for env |
| | env | sets agent cfgs (scoped to `wr_agent`/`rd_agent`), creates agents, scoreboard, coverage, vsqr |
| | agent | gets its cfg, creates monitor always, driver/sequencer if `UVM_ACTIVE` |
| `connect_phase` (bottom-up) | agent | driver `seq_item_port` to sequencer; re-exports monitor `ap` |
| | env | monitor ports to scoreboard/coverage imps; fills vsqr handles |
| `end_of_elaboration_phase` | test | prints DUT config; topology at `UVM_HIGH` |
| `run_phase` | test | raises objection, `apply_reset()`, `run_main()` (virtual sequence), drain cycles, drops objection; watchdog forked in parallel |
| | drivers / monitors | `forever` loops (no objections; the test owns end-of-test) |
| `check_phase` | scoreboard | leftover-data check |
| `report_phase` | monitors, sb, cov, test | statistics, coverage %, single `TEST PASSED/FAILED` line from the report server's error count |

Only the **test** raises objections. Components with `forever` loops never
do; otherwise the test would never end. A single objection owner makes the
end of the test easy to reason about.

The `run_phase` sub-phases (`reset_phase`, `main_phase`, ...) are not used.
They complicate phase jumping and are rarely used in practice; reset is an
explicit task in the base test instead.

## 12. Driver/monitor timing and clocking blocks

Each interface has `drv_cb` and `mon_cb` clocking blocks with
`default input #1step output #0`.

* `#1step` input skew: values are sampled in the Preponed region, i.e. the
  value **the DUT saw at that edge**, before any NBA updates. That removes all
  TB/DUT races. It is why the monitor can sample `rdata` at the edge where
  `rinc=1` and get the popped word.
* The driver drives `winc=1` right after edge *k*; the DUT samples it at edge
  *k+1*; at *k+1* the driver reads `drv_cb.wfull` (the value the DUT used for
  its accept/drop decision) and writes it back into the item.
* **Zero-bubble back-to-back.** After an item, the driver schedules `winc <= 0`.
  If the next item arrives in the same time step with `delay == 0`, it
  schedules `winc <= 1`, and the last clocking drive in a time step wins. The
  `last_edge_t` timestamp lets the driver tell "I'm still at the edge I just
  waited for" apart from "a new item arrived mid-cycle", so it never drives
  mid-cycle and never samples a response one edge early.
* **Monitors publish only interesting edges**: an op attempt, or a change in
  any request/flag. Coverage still sees every flag transition, and idle
  cycles cost nothing.
* Reset is not driven through a clocking block. Assertion is asynchronous;
  release is done on the inactive (negative) edge of each domain's own clock
  so it never coincides with an active edge.

## 13. Why the scoreboard is built this way

**Reference model = a queue.** Writes accepted by the DUT push, reads
accepted by the DUT pop and compare. Because a FIFO preserves order, this is
a complete functional model of the data path. There is no cycle accuracy, no
knowledge of clock ratio, and no synchronizer modeling.

**Decisions:**

* **Accept/drop is decided from the DUT's flags as sampled at the edge**
  (`winc && !wfull`), not predicted by the model. The model can't predict
  `wfull` exactly, because it depends on synchronizer latency. Instead, the
  scoreboard checks that the DUT's decision was legal (SB-OVF/SB-UNF/SB-FLAG)
  and then follows it. This is the standard way to scoreboard a design with
  intentionally non-deterministic but bounded timing.
* **Cross-domain ordering needs no extra logic.** Both monitors call
  `write()` in simulation-time order. A read can only pop an entry several
  `rclk` edges after it was written (two-flop sync plus registered flag), so the
  push always arrives first. Even when a write edge and read edge coincide in
  the same time step (order undefined), that read cannot be for that write.
  The comment at the top of `fifo_scoreboard.svh` states this argument,
  because it is the first thing a reviewer asks.
* **`uvm_analysis_imp_decl(_wr/_rd)`** gives two typed write methods in one
  component. The alternative, two `uvm_tlm_analysis_fifo`s plus a `run_phase`
  that `get()`s from them, adds a thread and makes ordering between the two
  fifos ambiguous. Direct imps keep the order the monitors produced.
* **The scoreboard checks safety; the virtual sequence checks exactness.**
  See section 6.
* **Reset flushes the model** on a monitor reset event. Data in flight at
  reset is legitimately lost; the reset test's `writes=563 reads=532` in the
  log is exactly that.
* **End-of-test leftover check** (`check_phase`) catches "data went in and
  never came out" (e.g. a stuck `rempty`), which per-transaction compares
  cannot see.

## 14. Assertions: what goes in SVA vs the scoreboard

Rule used: **SVA for local, cycle-level, single-clock properties of the RTL;
scoreboard for end-to-end data behavior across domains.**

* Every property is clocked by one clock and uses signals of that domain,
  except S1/S2 (below). Mixing clocks inside a property means sampling an
  asynchronous signal, which gives simulator-dependent results.
* The checker is a separate module attached with `bind`. The RTL stays
  clean, and the checker sees internals (`wptr`, `wq2_rptr`, `u_mem.mem[waddr]`)
  without RTL ports for verification.
* Action blocks use `` `uvm_error `` so assertion failures count toward the
  UVM error total, giving one PASS/FAIL criterion for everything.
* **S1/S2 deliberately sample the source pointer from the destination
  clock.** They assert `rq2_wptr == $past(wptr, 2)` at `rclk`, i.e. the
  synchronizer has exactly two stages. In zero-delay simulation this is
  deterministic: Preponed sampling at the `rclk` edge sees exactly what the
  first flop captures. Without S1, mutant M6 (single-flop synchronizer)
  passed **every** test, which is the textbook demonstration that functional
  simulation can't see CDC bugs.

Groups: **R** reset values, **G** Gray integrity, **P** pointer protocol
(including write-when-full leaves memory unchanged), **F** flag causality,
**S** synchronizer depth, **C** cover properties.

## 15. Coverage and how it maps to the plan

`docs/verification_plan.md` maps each feature to tests, checkers and bins.
Summary:

* **Op kinds** (`cp_op`): idle, accepted, blocked (write-when-full /
  read-when-empty). These cover the overflow/underflow requirements directly.
* **Flag values and transitions** (`cp_full`, `cp_full_tr`, ...): both
  values and both edges of every flag.
* **Fill level** (`cp_level`): empty, almost-empty band, middle,
  almost-full band, full. The bands are derived from the threshold
  parameters, so they move with the configuration.
* **Clock ratio** (`cp_ratio` and crosses with flags/ops): five classes
  derived from the live clock periods. The cross is the point: "write-when-full
  happened while wclk was 4x faster" is a different scenario from the same
  op at 1:1.
* **Data patterns**: all-zeros, all-ones, 0101.., 1010.. on writes and on
  reads. These catch stuck-at and coupling-style storage bugs. The write item
  has a `kind` field biased 20% toward these patterns, so they are hit
  without a directed test.
* **Simultaneous access**: whether the other side requested on its most
  recent edge when this side's op was accepted.

Coverage is sampled from **monitor** transactions only, so it measures what
the DUT did rather than what the TB intended.

**Coverage alone is not a verdict.** 100% of bins with a broken checker
means nothing; that is what section 16 is for.

## 16. Proving the checkers work: mutation testing

Each bug was injected into a copy of the RTL and the tests re-run. Measured
results are in README.md. Highlights:

* **M6 (one-flop synchronizer)** initially passed every test. That led to
  adding S1/S2, after which it is caught on the first transfer. This is the
  most instructive result in the repo.
* **M7 (`>` vs `>=` on almost-full)** is caught by the scoreboard's flag-safety
  check and by the exact check in the full/empty level walk. The level walk
  steps one entry at a time across both thresholds for this reason.
* **M5 (data corruption at one address)** is caught only by the data compare,
  as expected.
* Smoke does not catch M1, which is fine because smoke never fills the FIFO.
  The table shows which test catches which bug, which is useful for
  regression triage.

## 17. Running UVM on Verilator

* Verilator 5.x (recent master) compiles the Accellera UVM 2020.3 library,
  as adapted by the CHIPS Alliance `uvm-verilator` project, with
  `--timing` (delays, events, fork/join, clocking blocks), `--vpi` plus the
  UVM DPI C sources (command-line plusargs, regex), and z3 as the constraint
  solver for `randomize()`.
* `--assert` enables SVA; `--coverage-user` enables covergroups and cover
  properties, written to `coverage.dat` and merged with `verilator_coverage`.
* Things that needed care for portability:
  * `cg.cp.get_inst_coverage()` on a coverpoint is not supported in this
    Verilator version, so the TB reports per-covergroup percentages and
    `cov_report.py` lists unhit bins from the database.
  * Overlapping ranges inside one `dist` (a value both listed alone and
    inside a range) were replaced with a separate `kind` enum. That is
    clearer anyway.
* Commercial simulator targets (Questa, VCS, Xcelium) are in the Makefile
  but have not been run here; see README.

---

## 18. Interview questions and model answers

**Q1. Why can't you just put a 2-flop synchronizer on each bit of a binary
pointer?**
Each bit resolves independently. During a multi-bit transition such as
`0111 -> 1000`, the destination can capture any mix of old and new bits,
producing a value that never existed and a wildly wrong full/empty. Gray code
guarantees only one bit is in transition, so the captured value is either
the old or the new pointer.

**Q2. Why is the pointer one bit wider than the address?**
To tell full from empty. With equal address bits, matching wrap bits mean
empty and differing wrap bits mean full (the writer is a whole lap ahead).

**Q3. Derive the full condition in Gray code.**
Full means `wbin == rbin + 2^N`. In reflected Gray code, adding `2^N` to an
(N+1)-bit value inverts the two MSBs and leaves the rest equal. So
`full = (wgray == {~rgray[N:N-1], rgray[N-2:0]})`. Empty is plain equality.

**Q4. Why are full and empty "pessimistic"? Is that a bug?**
Each flag is computed from a synchronized, two-to-three-cycle-old copy of
the other pointer. Assertion is exact because it is caused locally, while
de-assertion is late. That costs a few cycles of throughput but can never
cause overflow or underflow. It is intended.

**Q5. What's MTBF and how does adding a flop change it?**
Mean time between synchronizer failures:
`MTBF = e^(t_r/tau) / (T_w * f_clk * f_data)`. It is exponential in
resolution time, so a second flop adds about a clock period of `t_r` and
multiplies MTBF by `e^(T/tau)`, typically many orders of magnitude.

**Q6. Can simulation find a missing synchronizer flop?**
Not functionally, because RTL simulation has no metastability. In this repo a
one-flop mutant passed every functional test until I added a white-box
assertion that the synchronized pointer equals the source pointer delayed by
two destination clocks. In production, CDC structure is signed off with a CDC
tool, not simulation.

**Q7. Why must the Gray pointer be registered?**
If it were combinational from the binary counter, the XOR network could
glitch, briefly changing several bits, and the synchronizer could capture the
glitch. A flop output changes once per edge.

**Q8. Why must depth be a power of two?**
Gray code is single-bit-change across the wrap only for a power-of-two
modulus. Other depths need a different code (e.g. a Gray sequence with a
symmetric offset) or a different crossing scheme.

**Q9. How does your scoreboard handle two clock domains?**
It doesn't need to model them. Monitors publish in simulation-time order; a
pop can only happen several read clocks after the matching push because of
the synchronizer, so the push always arrives first. The model is a queue;
accept/drop decisions are taken from the DUT's own sampled flags and checked
for legality rather than predicted.

**Q10. Why not predict `wfull` in the reference model?**
Its exact timing depends on synchronizer latency and clock phase, which is
non-deterministic by design. Predicting it would need a cycle-accurate CDC
model that is as complex as the DUT. Instead the scoreboard checks bounds
every cycle (never under-reports), and the sequences check exact values at
quiet points after the synchronizers settle.

**Q11. What's the difference between the scoreboard checks and the SVA?**
SVA covers local, single-clock, cycle-level RTL rules: Gray single-bit
change, pointer moves only on accepted ops, reset values, synchronizer
depth. The scoreboard covers end-to-end data correctness and ordering across
domains. Data integrity can't be expressed cleanly in single-clock SVA, and
pointer-level rules shouldn't be inferred indirectly from data.

**Q12. How did you verify write-when-full doesn't corrupt data?**
Three independent ways. SVA P2 checks the write pointer doesn't move. SVA P3
checks the memory word at the write address is unchanged. The scoreboard
checks every subsequent read matches, which would fail if the dropped data
had landed anywhere.

**Q13. What does `#1step` in a clocking block do and why use it?**
Input skew `#1step` samples in the Preponed region, giving the value before
any updates in this time step, i.e. what the DUT's flops saw at the edge. It
eliminates races between TB sampling and DUT NBA updates.

**Q14. Who raises objections in your TB and why?**
Only the test, around reset plus the main virtual sequence. Drivers and
monitors run forever loops and must not hold objections, or the test never
ends. A single owner makes end-of-test deterministic, and a forked watchdog
catches hangs.

**Q15. Why a virtual sequencer?**
Scenarios like "fill to full on the write side, then drain on the read side
and check flags" need coordinated control of two sequencers in different
clock domains. The virtual sequencer holds both handles plus config;
virtual sequences start single-domain agent sequences on them.

**Q16. How did you cover clock ratios?**
The clock generator takes periods from plusargs and can change them at
runtime. The clock-ratio test sweeps five configurations (wclk 4x faster,
slightly faster, equal, rclk slightly faster, rclk 4x faster), re-resetting
between them. Coverage classifies the live ratio and crosses it with op kind
and full/empty, so it shows that each corner happened under each ratio.

**Q17. How do you know your coverage model and checkers are meaningful?**
Coverage only shows the stimulus reached the scenarios. I ran mutation
testing: seven injected RTL bugs (missing full gate, wrong Gray full compare,
binary pointer, wrong reset value, data corruption, single-flop sync,
off-by-one threshold). Every one is caught, and the table records which test
and which checker caught it.

**Q18. What happens if only one side is reset?**
The other side keeps a stale pointer, and full/empty become wrong. This design
requires both domains to be reset together (async assert, each released
synchronously to its own clock). That is a documented integration
requirement, and independent reset is out of scope in the plan.

**Q19. How would you close timing on the Gray pointer buses?**
They're asynchronous paths, so you don't time them against either clock.
But you must bound the skew between bits, so the bus arrives as one coherent
Gray value within roughly one destination period. Use
`set_max_delay -datapath_only` (or equivalent) rather than a blanket
`set_false_path`, and keep the synchronizer flops adjacent (`ASYNC_REG` /
`dont_touch`).

**Q20. What would you add next?**
Formal property checking of the SVA (the properties are single-clock and
TB-independent, so they're formal-ready). A CDC tool run. Randomized
`DATA_WIDTH`/`ADDR_WIDTH` configurations in regression. Gate-level
simulation with SDF for the synchronizers. A passive-mode reuse of the
monitors at the SoC level.
