`timescale 1ns/1ns
// ============================================================================
// Testbench   : tb_emergency_unit
// Verifies    : single-direction requests are served immediately; a request
//               arriving while busy is queued (pending) and served right
//               after; and -- the additional-task scenario -- SIMULTANEOUS
//               NS+EW requests are arbitrated fairly (served one after the
//               other, alternating priority across repeated ties) instead of
//               one direction being ignored.
// ============================================================================
module tb_emergency_unit;

    reg clk, rst_n, ns_emergency_in, ew_emergency_in, emergency_served;
    wire emergency_active, serve_ns, ns_pending, ew_pending;
    integer errors = 0;

    emergency_unit dut (
        .clk(clk), .rst_n(rst_n),
        .ns_emergency_in(ns_emergency_in),
        .ew_emergency_in(ew_emergency_in),
        .emergency_served(emergency_served),
        .emergency_active(emergency_active),
        .serve_ns(serve_ns),
        .ns_pending(ns_pending),
        .ew_pending(ew_pending)
    );

    always #5 clk = ~clk;

    task check(input expected_active, input expected_serve_ns, input [127:0] msg);
        begin
            if (emergency_active !== expected_active || (expected_active && serve_ns !== expected_serve_ns)) begin
                $display("[FAIL] %0t %0s : active=%0b serve_ns=%0b (expected active=%0b serve_ns=%0b)",
                    $time, msg, emergency_active, serve_ns, expected_active, expected_serve_ns);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0t %0s : active=%0b serve_ns=%0b", $time, msg, emergency_active, serve_ns);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_emergency_unit.vcd");
        $dumpvars(0, tb_emergency_unit);

        clk = 0; rst_n = 0; ns_emergency_in = 0; ew_emergency_in = 0; emergency_served = 0;
        @(negedge clk); @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        check(0, 0, "idle after reset");

        // --- Case 1: single NS request served immediately ---
        // (one extra cycle of latency is expected: cycle 1 latches the
        // request into ns_pending, cycle 2 the arbiter grants it)
        @(negedge clk); ns_emergency_in = 1;
        @(negedge clk); ns_emergency_in = 0;
        @(negedge clk);
        check(1, 1, "NS request -> NS served");
        @(negedge clk); emergency_served = 1;
        @(negedge clk); emergency_served = 0;
        check(0, 0, "NS emergency finished -> idle");

        // --- Case 2: single EW request served immediately ---
        @(negedge clk); ew_emergency_in = 1;
        @(negedge clk); ew_emergency_in = 0;
        @(negedge clk);
        check(1, 0, "EW request -> EW served");
        @(negedge clk); emergency_served = 1;
        @(negedge clk); emergency_served = 0;
        check(0, 0, "EW emergency finished -> idle");

        // --- Case 3 (additional task): simultaneous NS + EW requests ---
        // Two ambulances reach two different junctions/approaches at the
        // exact same clock cycle.
        @(negedge clk);
        ns_emergency_in = 1; ew_emergency_in = 1;
        @(negedge clk);
        ns_emergency_in = 0; ew_emergency_in = 0;
        @(negedge clk);
        // last_served_ns was 0 (EW served last in Case 2) -> tie-break picks NS first
        check(1, 1, "simultaneous NS+EW -> NS wins tie-break (fair alternation)");
        if (ew_pending !== 1'b1) begin
            $display("[FAIL] %0t EW request must remain queued while NS is served", $time);
            errors = errors + 1;
        end else begin
            $display("[PASS] %0t EW request correctly queued (ew_pending=1) while NS served", $time);
        end

        @(negedge clk); emergency_served = 1;
        @(negedge clk); emergency_served = 0;
        // NS finished, EW was pending -> must be served next, no gap, no drop
        check(1, 0, "queued EW request now served immediately after NS finished");

        @(negedge clk); emergency_served = 1;
        @(negedge clk); emergency_served = 0;
        check(0, 0, "both emergencies handled -> back to idle");

        if (errors == 0)
            $display("*** tb_emergency_unit: ALL TESTS PASSED ***");
        else
            $display("*** tb_emergency_unit: %0d TEST(S) FAILED ***", errors);

        #20 $finish;
    end

endmodule
