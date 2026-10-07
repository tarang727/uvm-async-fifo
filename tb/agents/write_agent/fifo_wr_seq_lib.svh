// -----------------------------------------------------------------------------
// fifo_wr_seq_lib.svh
//
// Write-agent sequences. They run on fifo_wr_sequencer and know nothing about
// the read side; cross-domain scenarios are composed by virtual sequences.
//
// Every sequence counts accepted / dropped writes using the response the
// driver writes back into the item, so the virtual sequences can make
// scenario-level checks (e.g. "exactly DEPTH writes were accepted").
// -----------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Base: one helper that sends a single write and reports whether it was taken.
// ---------------------------------------------------------------------------
class fifo_wr_base_seq extends uvm_sequence #(fifo_wr_item);
  `uvm_object_utils(fifo_wr_base_seq)

  int unsigned n_accepted;
  int unsigned n_dropped;
  fifo_wr_item last_item;   // most recent item, with the driver's response

  function new(string name = "fifo_wr_base_seq");
    super.new(name);
  endfunction

  // Send one randomized write. Callers can pin data/delay through the
  // fix_* arguments; otherwise the item's own constraints apply. The
  // `local::` prefix refers to the task arguments, not the item fields.
  protected task send_write(bit          fix_data  = 1'b0,
                            data_t       data      = '0,
                            bit          fix_delay = 1'b0,
                            int unsigned delay     = 0,
                            int unsigned max_delay = 15);
    fifo_wr_item t = fifo_wr_item::type_id::create("t");
    start_item(t);
    if (!t.randomize() with {
          fix_data  -> (data == local::data && kind == DATA_RANDOM);
          fix_delay -> delay == local::delay;
          delay <= local::max_delay;
        }) begin
      `uvm_fatal("RAND", "fifo_wr_item randomization failed")
    end
    finish_item(t);
    if (t.accepted()) n_accepted++;
    else              n_dropped++;
    last_item = t;
  endtask

endclass : fifo_wr_base_seq

// ---------------------------------------------------------------------------
// Random writes: num_items attempts with random data and gaps up to max_delay.
// ---------------------------------------------------------------------------
class fifo_wr_rand_seq extends fifo_wr_base_seq;
  `uvm_object_utils(fifo_wr_rand_seq)

  rand int unsigned num_items;
  rand int unsigned max_delay;

  constraint c_defaults {
    soft num_items inside {[50:200]};
    soft max_delay inside {[0:8]};
  }

  function new(string name = "fifo_wr_rand_seq");
    super.new(name);
  endfunction

  task body();
    repeat (num_items) send_write(.max_delay(max_delay));
  endtask

endclass : fifo_wr_rand_seq

// ---------------------------------------------------------------------------
// Burst: back-to-back writes until `stop_after_drops` writes have been dropped
// because the FIFO was full (or max_writes attempts were made).
//   stop_after_drops = 1  -> "write burst to full" (one probing write when full)
//   stop_after_drops = K  -> overflow attempt with K writes while full
// ---------------------------------------------------------------------------
class fifo_wr_burst_seq extends fifo_wr_base_seq;
  `uvm_object_utils(fifo_wr_burst_seq)

  int unsigned stop_after_drops = 1;
  int unsigned max_writes       = 4 * DEPTH;

  function new(string name = "fifo_wr_burst_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned attempts = 0;
    while (n_dropped < stop_after_drops && attempts < max_writes) begin
      send_write(.fix_delay(1'b1), .delay(0));
      attempts++;
    end
    `uvm_info(get_type_name(),
              $sformatf("burst done: %0d accepted, %0d dropped (full)",
                        n_accepted, n_dropped), UVM_MEDIUM)
  endtask

endclass : fifo_wr_burst_seq

// ---------------------------------------------------------------------------
// Fixed list of values written back-to-back (directed data, e.g. smoke test).
// ---------------------------------------------------------------------------
class fifo_wr_list_seq extends fifo_wr_base_seq;
  `uvm_object_utils(fifo_wr_list_seq)

  data_t values[$];

  function new(string name = "fifo_wr_list_seq");
    super.new(name);
  endfunction

  task body();
    foreach (values[i]) begin
      send_write(.fix_data(1'b1), .data(values[i]), .fix_delay(1'b1), .delay(0));
    end
  endtask

endclass : fifo_wr_list_seq
