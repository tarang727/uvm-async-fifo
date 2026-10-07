// -----------------------------------------------------------------------------
// fifo_rd_item.svh
//
// Read-domain transaction. As with fifo_wr_item, one class serves both as
// stimulus (only `delay` is randomized: a read request carries no data) and as
// the monitor's observation / the driver's response.
//
// `data` is meaningful only when accepted() is true: it is the rdata value the
// DUT presented at the edge that popped the entry (first-word fall-through).
// -----------------------------------------------------------------------------
class fifo_rd_item extends uvm_sequence_item;

  // ---- stimulus ----
  rand int unsigned delay;   // idle rclk cycles before the read request

  // ---- observed / response ----
  bit    rinc;          // read was requested on this edge
  bit    empty;         // rempty at this edge (read is ignored if 1)
  bit    almost_empty;  // ralmost_empty at this edge
  data_t data;          // popped data (valid only if accepted())
  bit    reset_evt;     // monitor-only: read-domain reset was observed

  constraint c_delay {
    delay dist { 0 :/ 60, [1:3] :/ 30, [4:15] :/ 10 };
  }

  `uvm_object_utils_begin(fifo_rd_item)
    `uvm_field_int(data,         UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(delay,        UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(rinc,         UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
    `uvm_field_int(empty,        UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
    `uvm_field_int(almost_empty, UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
    `uvm_field_int(reset_evt,    UVM_ALL_ON | UVM_BIN | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "fifo_rd_item");
    super.new(name);
  endfunction

  function bit accepted();
    return rinc && !empty;
  endfunction

  function string convert2string();
    if (reset_evt) return "RD reset";
    return $sformatf("RD rinc=%0b empty=%0b aempty=%0b%s",
                     rinc, empty, almost_empty,
                     accepted()          ? $sformatf(" data=0x%0h", data) :
                     (rinc && empty)     ? " (IGNORED: empty)" : "");
  endfunction

endclass : fifo_rd_item
