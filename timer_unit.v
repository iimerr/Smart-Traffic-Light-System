// ============================================================================
// Module      : timer_unit
// Description : Generic parameterizable down-counter used by the FSM to
//               time every phase (green/yellow/all-red). The FSM loads the
//               required duration on 'load', the counter then ticks down by
//               1 every cycle 'tick' is asserted and raises 'done' for one
//               cycle when it reaches zero.
// ============================================================================
module timer_unit #(
    parameter WIDTH = 5
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] load_value,
    input  wire             tick,
    output reg              done
);

    reg [WIDTH-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {WIDTH{1'b0}};
            done  <= 1'b0;
        end else if (load) begin
            count <= load_value;
            done  <= (load_value == 0);
        end else if (tick && count != 0) begin
            count <= count - 1'b1;
            done  <= (count == 1);
        end else begin
            done <= 1'b0;
        end
    end

endmodule
