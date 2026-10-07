// -----------------------------------------------------------------------------
// fifo_rd_seq_lib.svh - read-agent sequences.
// -----------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Base: one helper that sends a single read request and records the response.
// ---------------------------------------------------------------------------
class fifo_rd_base_seq extends uvm_sequence #(fifo_rd_item);
  `uvm_object_utils(fifo_rd_base_seq)

  int unsigned n_accepted;
  int unsigned n_ignored;
  fifo_rd_item last_item;

  function new(string name = "fifo_rd_base_seq");
    super.new(name);
  endfunction

  protected task send_read(bit          fix_delay = 1'b0,
                           int unsigned delay     = 0,
                           int unsigned max_delay = 15);
    fifo_rd_item t = fifo_rd_item::type_id::create("t");
    start_item(t);
    if (!t.randomize() with {
          fix_delay -> delay == local::delay;
          delay <= local::max_delay;
        }) begin
      `uvm_fatal("RAND", "fifo_rd_item randomization failed")
    end
    finish_item(t);
    if (t.accepted()) n_accepted++;
    else              n_ignored++;
    last_item = t;
  endtask

endclass : fifo_rd_base_seq

// ---------------------------------------------------------------------------
// Random reads: num_items read attempts with random gaps.
// ---------------------------------------------------------------------------
class fifo_rd_rand_seq extends fifo_rd_base_seq;
  `uvm_object_utils(fifo_rd_rand_seq)

  rand int unsigned num_items;
  rand int unsigned max_delay;

  constraint c_defaults {
    soft num_items inside {[50:200]};
    soft max_delay inside {[0:8]};
  }

  function new(string name = "fifo_rd_rand_seq");
    super.new(name);
  endfunction

  task body();
    repeat (num_items) send_read(.max_delay(max_delay));
  endtask

endclass : fifo_rd_rand_seq

// ---------------------------------------------------------------------------
// Burst: back-to-back reads until `stop_after_ignored` reads have been ignored
// because the FIFO was empty (or max_reads attempts were made).
//   stop_after_ignored = 1 -> "read burst to empty"
//   stop_after_ignored = K -> underflow attempt with K reads while empty
// ---------------------------------------------------------------------------
class fifo_rd_burst_seq extends fifo_rd_base_seq;
  `uvm_object_utils(fifo_rd_burst_seq)

  int unsigned stop_after_ignored = 1;
  int unsigned max_reads          = 4 * DEPTH;

  function new(string name = "fifo_rd_burst_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned attempts = 0;
    while (n_ignored < stop_after_ignored && attempts < max_reads) begin
      send_read(.fix_delay(1'b1), .delay(0));
      attempts++;
    end
    `uvm_info(get_type_name(),
              $sformatf("burst done: %0d accepted, %0d ignored (empty)",
                        n_accepted, n_ignored), UVM_MEDIUM)
  endtask

endclass : fifo_rd_burst_seq

// ---------------------------------------------------------------------------
// Drain: keep reading (with no gaps) until `count` entries have been popped.
// Reads that hit an empty FIFO are simply retried; they are expected while
// the write pointer is still crossing the synchronizer.
// ---------------------------------------------------------------------------
class fifo_rd_count_seq extends fifo_rd_base_seq;
  `uvm_object_utils(fifo_rd_count_seq)

  int unsigned count;
  int unsigned max_attempts = 0;   // 0 -> 64 * count + 64

  function new(string name = "fifo_rd_count_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned limit = (max_attempts != 0) ? max_attempts : 64 * count + 64;
    int unsigned attempts = 0;
    while (n_accepted < count && attempts < limit) begin
      send_read(.fix_delay(1'b1), .delay(0));
      attempts++;
    end
    if (n_accepted < count) begin
      `uvm_error(get_type_name(),
                 $sformatf("only %0d of %0d entries could be read in %0d attempts",
                           n_accepted, count, attempts))
    end
  endtask

endclass : fifo_rd_count_seq
