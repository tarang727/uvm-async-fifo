# Verification Plan: Asynchronous FIFO

This plan maps every DUT feature to the mechanisms that verify it: tests
(stimulus), checkers (scoreboard, directed flag checks, SVA) and functional
coverage. A feature counts as verified when (a) at least one checker would
fail if the feature were broken, and (b) coverage shows the stimulus actually
exercised it.

Default configuration: `DATA_WIDTH=8`, `ADDR_WIDTH=4` (DEPTH=16),
`ALMOST_FULL_THRESH=14`, `ALMOST_EMPTY_THRESH=2`.

## 1. Checker inventory

| ID | Checker | Where | What it checks |
|----|---------|-------|----------------|
| SB-DATA | Scoreboard data compare | `fifo_scoreboard::write_rd` | Popped data == front of reference queue (order and value) |
| SB-OVF | Scoreboard overflow | `write_wr` | DUT never accepts a write when the model already holds DEPTH entries |
| SB-UNF | Scoreboard underflow | `write_rd` | DUT never pops when the model is empty |
| SB-FLAG | Flag safety | `write_wr` / `write_rd` | `!wfull => occ<DEPTH`, `!walmost_full => occ<AF`, `!rempty => occ>0`, `!ralmost_empty => occ>AE`, every observed edge |
| SB-END | Leftover data | `check_phase` | Nothing written-but-unread at end (tests that drain) |
| VS-FLAG | Exact flag check | `fifo_base_vseq::check_flags` | All four flags exactly match the level once both synchronizers have settled |
| VS-CNT | Accept/drop counts | `fill_to_full`, `read_to_empty`, vseqs | e.g. exactly DEPTH writes accepted before the first drop |
| R1-R4 | SVA reset values | `fifo_sva` | Flags at reset values during reset and on the first edge after release |
| G1-G2 | SVA Gray integrity | `fifo_sva` | `wptr`/`rptr` change by exactly one bit (`$onehot(p ^ $past(p))`) |
| P1-P5 | SVA pointer protocol | `fifo_sva` | Pointers move iff an op is accepted; write-when-full leaves memory unchanged |
| F1-F6 | SVA flag causality | `fifo_sva` | full/empty rise only due to a local op; fall only after the synced remote pointer moved; full=>almost_full, empty=>almost_empty |
| S1-S2 | SVA synchronizer depth | `fifo_sva` | Synced pointer == source pointer two destination edges ago (exactly two flops) |
| TB-RST | Reset test check | `fifo_reset_test` | Flags at reset values while reset is asserted mid-traffic |

## 2. Feature → verification mapping

| # | Feature | Tests | Checkers | Coverage |
|---|---------|-------|----------|----------|
| F1 | Data integrity and ordering across clock domains | all | SB-DATA, SB-END | `cg_wr_data`, `cg_rd_data` |
| F2 | Write when not full is accepted | all | SB-DATA, P1, VS-CNT | `cg_wr.cp_op.write` |
| F3 | Write when full is ignored (no pointer move, no memory change, data never appears) | overflow_underflow, full_empty, random, clock_ratio | SB-OVF, SB-DATA, P2, P3, VS-CNT | `cg_wr.cp_op.write_when_full`, `x_ratio_op`, SVA `C2_write_when_full` |
| F4 | Read when not empty pops the oldest entry (FWFT) | all | SB-DATA, P4 | `cg_rd.cp_op.read` |
| F5 | Read when empty is ignored | overflow_underflow, full_empty, random, clock_ratio | SB-UNF, P5, VS-CNT | `cg_rd.cp_op.read_when_empty`, SVA `C6_read_when_empty` |
| F6 | `wfull` asserts exactly when the last slot is written | full_empty, overflow_underflow | VS-FLAG, VS-CNT (exactly DEPTH accepted), SB-FLAG, F1 | `cg_wr.cp_full`, `cp_full_tr.rise`, `cp_level.full` |
| F7 | `wfull` deasserts (late but safe) after a read | full_empty, random, clock_ratio | VS-FLAG, F2 | `cg_wr.cp_full_tr.fall`, SVA `C3` |
| F8 | `rempty` asserts exactly when the last entry is read | full_empty, smoke | VS-FLAG, SB-FLAG, F4 | `cg_rd.cp_empty`, `cp_empty_tr.rise` |
| F9 | `rempty` deasserts (late but safe) after a write | all | VS-FLAG, F5 | `cg_rd.cp_empty_tr.fall`, SVA `C7` |
| F10 | `walmost_full` at occupancy >= AF threshold | full_empty (level walk covers AF-1, AF, AF+1) | VS-FLAG, SB-FLAG, F3 | `cg_wr.cp_afull`, `cp_afull_tr`, `cp_level.almost_full` |
| F11 | `ralmost_empty` at occupancy <= AE threshold | full_empty (level walk) | VS-FLAG, SB-FLAG, F6 | `cg_rd.cp_aempty`, `cp_aempty_tr`, `cp_level.almost_empty` |
| F12 | Gray-coded pointers (one bit per increment) | all | G1, G2 | implicitly via pointer wrap: full_empty does 3 full fill/drain cycles |
| F13 | Two-flop synchronizers in both directions | all | S1, S2 | n/a (structural) |
| F14 | Pointer wrap (MSB toggles; full vs empty disambiguation) | full_empty (3 full cycles), overflow_underflow (offset fill), random | SB-*, VS-FLAG | `cp_level.full` and `.empty` reached repeatedly |
| F15 | Simultaneous read and write | simul_rw, random, clock_ratio | SB-DATA | `cg_wr_data.cp_simultaneous.write_while_reading`, `cg_rd_data.cp_simultaneous.read_while_writing` |
| F16 | Fill levels (empty / almost empty / middle / almost full / full) | full_empty, random | SB-*, VS-FLAG | `cg_wr.cp_level`, `cg_rd.cp_level` |
| F17 | Data patterns (all-zeros, all-ones, 0101.., 1010..) through storage | smoke, random | SB-DATA | `cg_*_data.cp_pattern` |
| F18 | Clock ratios: wclk >= 2x faster, faster, equal, rclk faster, rclk >= 2x faster | clock_ratio (5 configs), any test with `WCLK_PS`/`RCLK_PS` | all of the above under each ratio | `cg_wr.cp_ratio`, `x_ratio_full`, `x_ratio_op`; `cg_rd.x_ratio_empty`, `x_ratio_op` |
| F19 | Reset: flags at reset values; FIFO usable after reset | all (start), reset (3x mid-traffic) | R1-R4, TB-RST, then SB/VS-FLAG on post-reset traffic | scoreboard `resets=` count in log |
| F20 | Reset during traffic discards contents | reset | Scoreboard flush on monitor reset event + subsequent SB-DATA | n/a |

## 3. Coverage model

All covergroups are in `tb/env/fifo_coverage.svh` and sample from **monitor**
transactions (what the DUT did), never from stimulus.

| Covergroup | Coverpoint / cross | Bins | Plan item |
|------------|--------------------|------|-----------|
| `cg_wr` | `cp_op` | idle, write, write_when_full | F2, F3 |
| | `cp_full`, `cp_full_tr` | 0/1, rise/fall | F6, F7 |
| | `cp_afull`, `cp_afull_tr` | 0/1, rise/fall | F10 |
| | `cp_level` | empty, almost_empty, middle, almost_full, full | F16 |
| | `cp_ratio` | 5 clock-ratio classes | F18 |
| | `x_ratio_full`, `x_ratio_op` | ratio x full, ratio x op | F18 x F3/F6 |
| `cg_rd` | mirror of `cg_wr` for read/empty | | F4, F5, F8, F9, F11, F16, F18 |
| `cg_wr_data` | `cp_pattern`, `cp_simultaneous` | 4 patterns, write-only / write-while-reading | F15, F17 |
| `cg_rd_data` | `cp_pattern`, `cp_simultaneous` | 4 patterns, read-only / read-while-writing | F15, F17 |

SVA cover properties `C1`..`C8` in `fifo_sva.sv` independently confirm that
the flag edges and blocked operations were seen at the RTL boundary.

**Closure criterion:** 100% of covergroup bins hit across the regression and
every SVA cover property hit at least once, with zero checker failures. The
status actually measured is in README.md.

## 4. Checker effectiveness (mutation testing)

A checker that never fails proves nothing. Each of these bugs was injected
into a copy of the RTL and the regression subset was re-run. Results are in
README.md ("Mutation testing").

| Mutant | Bug injected | Expected to be caught by |
|--------|--------------|--------------------------|
| M1 | Write pointer advances on write-when-full | SB-OVF, SB-FLAG, P3, F2, VS-FLAG |
| M2 | Full compare without inverting the two MSBs | F3, VS-FLAG |
| M3 | Binary instead of Gray pointer sent to synchronizer | G1, SB-FLAG, VS-FLAG |
| M4 | `rempty` reset value 0 | R3 |
| M5 | Data corruption at one memory address | SB-DATA |
| M6 | One-flop synchronizer (write -> read) | S1 |
| M7 | Almost-full uses `>` instead of `>=` | SB-FLAG, VS-FLAG |

## 5. Out of scope

* **Metastability itself.** RTL simulation is zero-delay and has no
  metastability; synchronizer correctness is checked structurally (S1/S2) and
  would be signed off with a CDC tool (e.g. structural CDC + reconvergence
  analysis) in a real flow.
* **Gate-level / timing.** No SDF, no clock-domain timing constraints
  (`set_max_delay`/`set_false_path` on the Gray buses) are part of this repo.
* **Independent resets.** The testbench always resets both domains together,
  which is the documented integration requirement. Resetting one side alone is
  not supported by this design.
* **Formal proof.** The SVA is written to be formal-friendly (single clock per
  property, no TB state) but has only been run in simulation.
