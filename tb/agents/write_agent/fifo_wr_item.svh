// -----------------------------------------------------------------------------
// fifo_wr_item.svh
//
// Write-domain transaction. The same class is used in two roles:
//
//   1. Stimulus (sequence -> driver): `data` and `delay` are randomized.
//      `delay` is the number of idle wclk cycles inserted BEFORE the write.
//      After the driver executes the item it fills in the response fields
//      (`winc`, `full`, `almost_full`), so a sequence can call accepted() after
//      finish_item() and react (e.g. "write until full").
//
//   2. Observation (monitor -> scoreboard/coverage): the monitor creates an
//      item for every wclk edge on which something observable happens (a write
//      attempt, or a change of winc/wfull/walmost_full), and one item with
//      `reset_evt` set when it sees the write-domain reset.
//
// All observed fields are the values the DUT saw AT the clock edge, i.e.
// sampled in the Preponed region via the clocking block (#1step).
// -----------------------------------------------------------------------------
class fifo_wr_item extends uvm_sequence_item;

  // ---- stimulus ----
  rand data_t       data;
  rand int unsigned delay;

  // ---- observed / response ----
  bit winc;         // write was requested on this edge
  bit full;         // wfull at this edge (write is dropped if 1)
  bit almost_full;  // walmost_full at this edge
  bit reset_evt;    // monitor-only: write-domain reset was observed

  // Bias towards back-to-back writes so the FIFO actually fills; occasional
  // long gaps let the reader catch up.
  constraint c_delay {
    delay dist { 0 :/ 60, [1:3] :/ 30, [4:15] :/ 10 };
  }

  // Corner data patterns get a guaranteed share of the distribution so the
  // data-pattern coverpoints close without a directed test. A separate
  // `kind` variable is used instead of listing the corner values inside one
  // `data dist {...}` together with the full range: overlapping dist entries
  // are a portability trap, and this form is easy to override (a test can
  // simply constrain kind == DATA_RANDOM).
  rand data_kind_e kind;

  constraint c_kind {
    kind dist {
      DATA_RANDOM :/ 80,
      DATA_ZEROS  :/ 5,
      DATA_ONES   :/ 5,
      DATA_ALT_01 :/ 5,
      DATA_ALT_10 :/ 5
    };
  }

  constraint c_data {
    (kind == DATA_ZEROS)  -> (data == PAT_ZEROS);
    (kind == DATA_ONES)   -> (data == PAT_ONES);
    (kind == DATA_ALT_01) -> (data == PAT_ALT_01);
    (kind == DATA_ALT_10) -> (data == PAT_ALT_10);
    solve kind before data;
  }

  `uvm_object_utils_begin(fifo_wr_item)
    `uvm_field_int(data,        UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(delay,       UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_enum(data_kind_e, kind, UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int(winc,        UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
    `uvm_field_int(full,        UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
    `uvm_field_int(almost_full, UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
    `uvm_field_int(reset_evt,   UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "fifo_wr_item");
    super.new(name);
  endfunction

  // A write takes effect only if it was requested while the FIFO was not full.
  function bit accepted();
    return winc && !full;
  endfunction

  function string convert2string();
    if (reset_evt) return "WR reset";
    return $sformatf("WR winc=%0b data=0x%0h full=%0b afull=%0b%s",
                     winc, data, full, almost_full,
                     (winc && full) ? " (DROPPED: full)" : "");
  endfunction

endclass : fifo_wr_item
