`timescale 1ns/1ns
// ============================================================================
// Testbench   : tb_timer_unit
// Verifies    : counter loads correctly, ticks down while tick=1, asserts
//               'done' for exactly one cycle when it reaches zero, and can be
//               reloaded with a new value (used for the different green /
//               yellow / all-red durations of the FSM).
// ============================================================================
module tb_timer_unit;

    reg clk, rst_n, load, tick;
    reg [4:0] load_value;
    wire done;
    integer errors = 0;

    timer_unit #(.WIDTH(5)) dut (
        .clk(clk), .rst_n(rst_n),
        .load(load), .load_value(load_value),
        .tick(tick), .done(done)
    );

    always #5 clk = ~clk;

    task check(input expected, input [127:0] msg);
        begin
            if (done !== expected) begin
                $display("[FAIL] %0t %0s : expected done=%0b got=%0b", $time, msg, expected, done);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0t %0s : done=%0b", $time, msg, done);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_timer_unit.vcd");
        $dumpvars(0, tb_timer_unit);

        clk = 0; rst_n = 0; load = 0; load_value = 0; tick = 0;
        @(negedge clk);
        rst_n = 1;

        // load 4, tick every cycle -> done should pulse after 4 ticks
        @(negedge clk);
        load = 1; load_value = 5'd4; tick = 1;
        @(negedge clk); load = 0;
        check(0, "just loaded, not done yet");
        @(negedge clk); check(0, "count=3");
        @(negedge clk); check(0, "count=2");
        @(negedge clk); check(0, "count=1->0 transition pending");
        @(negedge clk); check(1, "count reached 0, done pulses");
        @(negedge clk); check(0, "done deasserts next cycle");

        // reload with a shorter value while running
        load = 1; load_value = 5'd1; tick = 1;
        @(negedge clk); load = 0;
        @(negedge clk); check(1, "short reload of 1 -> done next cycle");

        if (errors == 0)
            $display("*** tb_timer_unit: ALL TESTS PASSED ***");
        else
            $display("*** tb_timer_unit: %0d TEST(S) FAILED ***", errors);

        #20 $finish;
    end

endmodule
