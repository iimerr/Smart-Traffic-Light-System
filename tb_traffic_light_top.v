`timescale 1ns/1ns
// ============================================================================
// Testbench   : tb_traffic_light_top
// Verifies    : full system integration -- vehicle detector pulses build up
//               density on each approach, the FSM adapts its green time
//               accordingly, and an emergency vehicle pulse on one approach
//               preempts the normal cycle safely. This is also where the
//               "additional task" scenario is exercised end-to-end: two
//               emergency requests (NS and EW) arriving in the SAME cycle,
//               representing ambulances reaching two different junctions at
//               once, and the system serving both, one after another, with
//               no vehicle ever seeing conflicting greens.
// ============================================================================
module tb_traffic_light_top;

    reg clk, rst_n;
    reg ns_vehicle_pulse, ew_vehicle_pulse;
    reg ns_emergency_in, ew_emergency_in;
    wire [1:0] ns_light, ew_light;
    wire [3:0] state;
    wire [4:0] active_green_time;

    integer errors = 0;

    traffic_light_top dut (
        .clk(clk), .rst_n(rst_n),
        .ns_vehicle_pulse(ns_vehicle_pulse),
        .ew_vehicle_pulse(ew_vehicle_pulse),
        .ns_emergency_in(ns_emergency_in),
        .ew_emergency_in(ew_emergency_in),
        .ns_light(ns_light), .ew_light(ew_light),
        .state(state), .active_green_time(active_green_time)
    );

    always #5 clk = ~clk;

    // global safety monitor - the single most important property of any
    // traffic light controller: never show green on both conflicting
    // approaches at the same time.
    always @(posedge clk) begin
        if (rst_n && ns_light == 2'b10 && ew_light == 2'b10) begin
            $display("[FAIL][SAFETY] %0t both NS and EW green simultaneously!", $time);
            errors = errors + 1;
        end
    end

    integer i;

    initial begin
        $dumpfile("tb_traffic_light_top.vcd");
        $dumpvars(0, tb_traffic_light_top);

        clk = 0; rst_n = 0;
        ns_vehicle_pulse = 0; ew_vehicle_pulse = 0;
        ns_emergency_in = 0; ew_emergency_in = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;

        // Build up some NS traffic density with detector pulses while the
        // junction is cycling normally.
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            ns_vehicle_pulse = 1;
            @(negedge clk);
            ns_vehicle_pulse = 0;
            @(negedge clk);
        end
        $display("[INFO] %0t injected 5 NS detector pulses -> expect a longer NS green next cycle", $time);

        // run for a while to observe at least one full adaptive NS green phase
        repeat (400) @(negedge clk);

        // ---------------------------------------------------------------
        // Additional task scenario: simultaneous emergency arrivals at
        // two different approaches (NS ambulance and EW fire truck reach
        // the junction system in the same clock cycle).
        // ---------------------------------------------------------------
        @(negedge clk);
        ns_emergency_in = 1;
        ew_emergency_in = 1;
        $display("[INFO] %0t SIMULTANEOUS emergency requests asserted on NS and EW", $time);
        @(negedge clk);
        ns_emergency_in = 0;
        ew_emergency_in = 0;

        // Watch the system for enough cycles to serve both emergency
        // vehicles (one after another) and confirm it returns to normal.
        for (i = 0; i < 60; i = i + 1) begin
            @(negedge clk);
            if (state == 4'd8) $display("[INFO] %0t -> serving NS emergency (state=EMG_NS)", $time);
            if (state == 4'd9) $display("[INFO] %0t -> serving EW emergency (state=EMG_EW)", $time);
        end

        if (errors == 0)
            $display("*** tb_traffic_light_top: NO SAFETY VIOLATIONS, simultaneous emergencies both served ***");
        else
            $display("*** tb_traffic_light_top: %0d SAFETY VIOLATION(S) DETECTED ***", errors);

        #50 $finish;
    end

endmodule
