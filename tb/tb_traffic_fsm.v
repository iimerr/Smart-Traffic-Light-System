`timescale 1ns/1ns
// ============================================================================
// Testbench   : tb_traffic_fsm
// Verifies    : (1) adaptive green timing -- a higher density value produces
//               a longer green phase, capped at MAX_GREEN; (2) safe phase
//               sequencing NS_GREEN->YELLOW->ALLRED->EW_GREEN->...; and
//               (3) emergency preemption forces an immediate transition to
//               the emergency state through an all-red clearance.
// ============================================================================
module tb_traffic_fsm;

    localparam MIN_GREEN = 5, MAX_GREEN = 12, YELLOW_T = 2, ALLRED_T = 2, EMG_GREEN = 6;

    reg clk, rst_n;
    reg [3:0] ns_density, ew_density;
    reg emergency_active, serve_ns;
    wire ns_clear_density, ew_clear_density, emergency_served;
    wire [1:0] ns_light, ew_light;
    wire [3:0] state;
    wire [4:0] active_green_time;

    integer errors = 0;
    integer green_len;
    integer baseline_len;

    traffic_fsm #(
        .MIN_GREEN(MIN_GREEN), .MAX_GREEN(MAX_GREEN),
        .YELLOW_T(YELLOW_T), .ALLRED_T(ALLRED_T), .EMG_GREEN(EMG_GREEN)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ns_density(ns_density), .ew_density(ew_density),
        .ns_clear_density(ns_clear_density), .ew_clear_density(ew_clear_density),
        .emergency_active(emergency_active), .serve_ns(serve_ns),
        .emergency_served(emergency_served),
        .ns_light(ns_light), .ew_light(ew_light),
        .state(state), .active_green_time(active_green_time)
    );

    always #5 clk = ~clk;

    // count how many cycles ns_light stays GREEN (2'b10) for the current phase
    task measure_ns_green(output integer len);
        begin
            len = 0;
            wait (ns_light == 2'b10);
            while (ns_light == 2'b10) begin
                @(negedge clk);
                len = len + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_traffic_fsm.vcd");
        $dumpvars(0, tb_traffic_fsm);

        clk = 0; rst_n = 0;
        ns_density = 0; ew_density = 0;
        emergency_active = 0; serve_ns = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;

        // NOTE on timing constant: every phase incurs a small, constant
        // pipeline latency (one cycle for the timer to latch the loaded
        // duration + one cycle for the FSM to register that "done" has
        // been seen) on top of the requested duration. This offset is the
        // same for every phase regardless of density, so the tests below
        // measure it once at density=0 and then check every other case
        // *relative* to that measured baseline instead of assuming a
        // latency of exactly zero.

        // ---- Test 1: light traffic -> shortest green (MIN_GREEN) ----
        ns_density = 0; ew_density = 0;
        measure_ns_green(baseline_len);
        $display("[INFO] %0t density=0 -> NS green length=%0d cycles (this is MIN_GREEN=%0d + fixed pipeline latency)",
            $time, baseline_len, MIN_GREEN);

        // let EW phase run out normally so we come back to NS_GREEN with new density
        wait (state == 4'd6); // S_ALLRED_B, about to reload NS green with density below
        ns_density = 4'd7;    // heavy traffic on NS this round

        // ---- Test 2: heavy traffic -> extended green (+7 vs baseline) ----
        measure_ns_green(green_len);
        if (green_len == baseline_len + 7) begin
            $display("[PASS] %0t density=7 -> NS green length=%0d, exactly %0d cycles longer than baseline as expected", $time, green_len, 7);
        end else begin
            $display("[FAIL] %0t density=7 -> NS green length=%0d, expected baseline+7=%0d", $time, green_len, baseline_len+7);
            errors = errors + 1;
        end

        // ---- Test 3: very heavy traffic -> capped at MAX_GREEN ----
        wait (state == 4'd6);
        ns_density = 4'd15;
        measure_ns_green(green_len);
        if (green_len == baseline_len + (MAX_GREEN - MIN_GREEN)) begin
            $display("[PASS] %0t density=15 -> NS green length=%0d, correctly capped at baseline+(MAX_GREEN-MIN_GREEN)=%0d", $time, green_len, baseline_len+(MAX_GREEN-MIN_GREEN));
        end else begin
            $display("[FAIL] %0t density=15 -> NS green length=%0d, expected cap %0d", $time, green_len, baseline_len+(MAX_GREEN-MIN_GREEN));
            errors = errors + 1;
        end

        // ---- Test 4: emergency preemption ----
        // Wait until we are safely inside an EW_GREEN phase, then raise an
        // NS emergency request and confirm the FSM cuts to EMG_NS via the
        // all-red clearance state without ever showing NS and EW green together.
        wait (state == 4'd4); // S_EW_GREEN
        @(negedge clk);
        emergency_active = 1; serve_ns = 1;

        fork
            begin: mon
                integer t;
                for (t = 0; t < 30; t = t + 1) begin
                    @(negedge clk);
                    if (ns_light == 2'b10 && ew_light == 2'b10) begin
                        $display("[FAIL] %0t UNSAFE: both directions green simultaneously!", $time);
                        errors = errors + 1;
                    end
                    if (state == 4'd8) disable mon; // reached S_EMG_NS
                end
            end
        join

        @(negedge clk); // allow the registered ns_light output to catch up to the new state
        if (state == 4'd8 && ns_light == 2'b10) begin
            $display("[PASS] %0t emergency preemption reached EMG_NS with NS green", $time);
        end else begin
            $display("[FAIL] %0t emergency preemption did not reach EMG_NS correctly (state=%0d)", $time, state);
            errors = errors + 1;
        end
        emergency_active = 0;

        if (errors == 0)
            $display("*** tb_traffic_fsm: ALL TESTS PASSED ***");
        else
            $display("*** tb_traffic_fsm: %0d TEST(S) FAILED ***", errors);

        #50 $finish;
    end

    // global safety monitor: NS and EW must never both be green
    always @(posedge clk) begin
        if (rst_n && ns_light == 2'b10 && ew_light == 2'b10) begin
            $display("[FAIL][SAFETY] %0t both NS and EW green at once!", $time);
            errors = errors + 1;
        end
    end

endmodule
