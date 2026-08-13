// ============================================================================
// Module      : sensor_unit
// Description : Models an inductive-loop / IR vehicle detector for one
//               approach of the junction. Every time a vehicle passes over
//               the detector it produces a single-cycle pulse on
//               vehicle_pulse. The module accumulates the number of pulses
//               seen inside one "sample window" (sample_en high) into a
//               saturating 4-bit density register that the FSM/timer use to
//               decide how long to extend the green phase.
// ============================================================================
module sensor_unit #(
    parameter DENSITY_MAX = 4'd15
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       vehicle_pulse,   // raw detector pulse, 1 clk wide
    input  wire       sample_en,       // sampling window open (counting active)
    input  wire       clear_density,   // pulses used by FSM, clear for next cycle
    output reg  [3:0] density          // number of vehicles counted (0-15)
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            density <= 4'd0;
        end else if (clear_density) begin
            density <= 4'd0;
        end else if (sample_en && vehicle_pulse && density < DENSITY_MAX) begin
            density <= density + 4'd1;
        end
    end

endmodule
