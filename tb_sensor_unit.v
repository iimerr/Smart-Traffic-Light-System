`timescale 1ns/1ns
// ============================================================================
// Testbench   : tb_sensor_unit
// Verifies    : density increments once per vehicle_pulse while sample_en=1,
//               saturates at DENSITY_MAX, and resets to 0 on clear_density.
// ============================================================================
module tb_sensor_unit;

    reg clk, rst_n, vehicle_pulse, sample_en, clear_density;
    wire [3:0] density;
    integer errors = 0;

    sensor_unit #(.DENSITY_MAX(4'd15)) dut (
        .clk(clk), .rst_n(rst_n),
        .vehicle_pulse(vehicle_pulse),
        .sample_en(sample_en),
        .clear_density(clear_density),
        .density(density)
    );

    always #5 clk = ~clk; // 100 MHz-style test clock, 10ns period

    task check(input [3:0] expected, input [127:0] msg);
        begin
            if (density !== expected) begin
                $display("[FAIL] %0t %0s : expected=%0d got=%0d", $time, msg, expected, density);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0t %0s : density=%0d", $time, msg, density);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sensor_unit.vcd");
        $dumpvars(0, tb_sensor_unit);

        clk = 0; rst_n = 0; vehicle_pulse = 0; sample_en = 1; clear_density = 0;
        @(negedge clk); @(negedge clk);
        rst_n = 1;
        check(0, "after reset");

        // 3 vehicle pulses -> density should climb to 3
        repeat (3) begin
            @(negedge clk);
            vehicle_pulse = 1;
            @(negedge clk);
            vehicle_pulse = 0;
        end
        check(3, "after 3 pulses");

        // pulses while sample disabled must be ignored
        sample_en = 0;
        @(negedge clk); vehicle_pulse = 1;
        @(negedge clk); vehicle_pulse = 0;
        sample_en = 1;
        check(3, "pulse ignored while sample_en=0");

        // saturate at DENSITY_MAX (15): send 20 more pulses
        repeat (20) begin
            @(negedge clk); vehicle_pulse = 1;
            @(negedge clk); vehicle_pulse = 0;
        end
        check(15, "saturated at max");

        // clear_density resets counter
        @(negedge clk); clear_density = 1;
        @(negedge clk); clear_density = 0;
        check(0, "after clear_density");

        if (errors == 0)
            $display("*** tb_sensor_unit: ALL TESTS PASSED ***");
        else
            $display("*** tb_sensor_unit: %0d TEST(S) FAILED ***", errors);

        #20 $finish;
    end

endmodule
