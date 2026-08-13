// ============================================================================
// Module      : traffic_fsm
// Description : Core Moore FSM for a 4-approach junction organised as two
//               opposing phase groups: NS (North-South) and EW (East-West).
//               - Adaptive timing: at the start of every green phase the
//                 FSM loads the phase timer with MIN_GREEN + the vehicle
//                 density reported by the sensor of that approach group
//                 (capped at MAX_GREEN) -> heavier traffic gets a longer
//                 green window, light traffic is cut short.
//               - Emergency priority: 'emergency_active'/'serve_ns' from the
//                 emergency_unit preempt the normal cycle. The FSM always
//                 inserts an all-red clearance phase before switching to an
//                 emergency green so no two approaches are ever green at
//                 once, then another all-red clearance before resuming the
//                 interrupted normal cycle.
// Light code  : 00 = RED , 01 = YELLOW , 10 = GREEN
// ============================================================================
module traffic_fsm #(
    parameter MIN_GREEN = 5,
    parameter MAX_GREEN = 12,
    parameter YELLOW_T  = 2,
    parameter ALLRED_T  = 2,
    parameter EMG_GREEN = 6
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [3:0] ns_density,
    input  wire [3:0] ew_density,
    output reg        ns_clear_density,
    output reg        ew_clear_density,

    input  wire       emergency_active,
    input  wire       serve_ns,
    output reg        emergency_served,

    output reg  [1:0] ns_light,
    output reg  [1:0] ew_light,
    output reg  [3:0] state,
    output reg  [4:0] active_green_time  // debug: duration loaded for current green
);

    localparam S_RESET      = 4'd0;
    localparam S_NS_GREEN   = 4'd1;
    localparam S_NS_YELLOW  = 4'd2;
    localparam S_ALLRED_A   = 4'd3;
    localparam S_EW_GREEN   = 4'd4;
    localparam S_EW_YELLOW  = 4'd5;
    localparam S_ALLRED_B   = 4'd6;
    localparam S_ALLRED_E   = 4'd7;  // clearance before emergency
    localparam S_EMG_NS     = 4'd8;
    localparam S_EMG_EW     = 4'd9;
    localparam S_ALLRED_R   = 4'd10; // clearance after emergency, before resume

    localparam RED    = 2'b00;
    localparam YELLOW = 2'b01;
    localparam GREEN  = 2'b10;

    reg [4:0] timer_load_value;
    reg       timer_load;
    wire      timer_done;

    timer_unit #(.WIDTH(5)) u_timer (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (timer_load),
        .load_value (timer_load_value),
        .tick       (1'b1),
        .done       (timer_done)
    );

    // resume pointer: which normal phase to return to after an emergency
    reg resume_is_ns;

    function [4:0] clamp_green;
        input [3:0] density;
        reg   [4:0] t;
        begin
            t = MIN_GREEN + density;
            if (t > MAX_GREEN) t = MAX_GREEN;
            clamp_green = t;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_RESET;
            ns_light          <= RED;
            ew_light          <= RED;
            timer_load        <= 1'b1;
            timer_load_value  <= 5'd1;
            ns_clear_density  <= 1'b0;
            ew_clear_density  <= 1'b0;
            emergency_served  <= 1'b0;
            active_green_time <= 5'd0;
            resume_is_ns      <= 1'b1;
        end else begin
            // defaults each cycle
            timer_load       <= 1'b0;
            ns_clear_density <= 1'b0;
            ew_clear_density <= 1'b0;
            emergency_served <= 1'b0;

            case (state)
                S_RESET: begin
                    ns_light <= RED; ew_light <= RED;
                    state <= S_ALLRED_A;
                    timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                end

                // ---------------- NORMAL CYCLE: NS ----------------
                S_NS_GREEN: begin
                    ns_light <= GREEN; ew_light <= RED;
                    if (emergency_active && !serve_ns) begin
                        // an EW emergency arrived: cut NS green short safely
                        state <= S_NS_YELLOW;
                        timer_load <= 1'b1; timer_load_value <= YELLOW_T;
                    end else if (timer_done) begin
                        state <= S_NS_YELLOW;
                        timer_load <= 1'b1; timer_load_value <= YELLOW_T;
                    end
                end

                S_NS_YELLOW: begin
                    ns_light <= YELLOW; ew_light <= RED;
                    if (timer_done) begin
                        ns_clear_density <= 1'b1;
                        if (emergency_active && !serve_ns) begin
                            resume_is_ns <= 1'b0; // was serving NS, keep cycling
                            state <= S_ALLRED_E;
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end else begin
                            state <= S_ALLRED_A;
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end
                    end
                end

                S_ALLRED_A: begin
                    ns_light <= RED; ew_light <= RED;
                    if (timer_done) begin
                        if (emergency_active) begin
                            state <= S_ALLRED_E; // re-check, safe re-entry
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end else begin
                            state <= S_EW_GREEN;
                            timer_load <= 1'b1; timer_load_value <= clamp_green(ew_density);
                            active_green_time <= clamp_green(ew_density);
                        end
                    end
                end

                // ---------------- NORMAL CYCLE: EW ----------------
                S_EW_GREEN: begin
                    ew_light <= GREEN; ns_light <= RED;
                    if (emergency_active && serve_ns) begin
                        state <= S_EW_YELLOW;
                        timer_load <= 1'b1; timer_load_value <= YELLOW_T;
                    end else if (timer_done) begin
                        state <= S_EW_YELLOW;
                        timer_load <= 1'b1; timer_load_value <= YELLOW_T;
                    end
                end

                S_EW_YELLOW: begin
                    ew_light <= YELLOW; ns_light <= RED;
                    if (timer_done) begin
                        ew_clear_density <= 1'b1;
                        if (emergency_active) begin
                            state <= S_ALLRED_E;
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end else begin
                            state <= S_ALLRED_B;
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end
                    end
                end

                S_ALLRED_B: begin
                    ns_light <= RED; ew_light <= RED;
                    if (timer_done) begin
                        if (emergency_active) begin
                            state <= S_ALLRED_E;
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end else begin
                            state <= S_NS_GREEN;
                            timer_load <= 1'b1; timer_load_value <= clamp_green(ns_density);
                            active_green_time <= clamp_green(ns_density);
                        end
                    end
                end

                // ---------------- EMERGENCY PATH ----------------
                S_ALLRED_E: begin
                    ns_light <= RED; ew_light <= RED;
                    if (timer_done) begin
                        if (serve_ns) begin
                            state <= S_EMG_NS;
                            timer_load <= 1'b1; timer_load_value <= EMG_GREEN;
                        end else begin
                            state <= S_EMG_EW;
                            timer_load <= 1'b1; timer_load_value <= EMG_GREEN;
                        end
                    end
                end

                S_EMG_NS: begin
                    ns_light <= GREEN; ew_light <= RED;
                    if (timer_done) begin
                        state <= S_ALLRED_R;
                        timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        emergency_served <= 1'b1;
                    end
                end

                S_EMG_EW: begin
                    ew_light <= GREEN; ns_light <= RED;
                    if (timer_done) begin
                        state <= S_ALLRED_R;
                        timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        emergency_served <= 1'b1;
                    end
                end

                S_ALLRED_R: begin
                    ns_light <= RED; ew_light <= RED;
                    if (timer_done) begin
                        if (emergency_active) begin
                            // another emergency was queued (opposite dir) -
                            // emergency_unit already flipped serve_ns
                            state <= S_ALLRED_E;
                            timer_load <= 1'b1; timer_load_value <= ALLRED_T;
                        end else begin
                            // resume normal operation with a fresh, fair sample
                            state <= S_NS_GREEN;
                            timer_load <= 1'b1; timer_load_value <= clamp_green(ns_density);
                            active_green_time <= clamp_green(ns_density);
                        end
                    end
                end

                default: state <= S_RESET;
            endcase
        end
    end

endmodule
