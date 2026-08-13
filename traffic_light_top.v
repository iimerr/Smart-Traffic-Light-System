// ============================================================================
// Module      : traffic_light_top
// Description : Top-level smart traffic light controller. Integrates the
//               two vehicle sensors (NS, EW), the emergency-vehicle
//               arbitration unit and the core FSM (which itself owns the
//               phase timer). This is the block that would be instantiated
//               on the FPGA / synthesised to a netlist.
// ============================================================================
module traffic_light_top (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       ns_vehicle_pulse,
    input  wire       ew_vehicle_pulse,
    input  wire       ns_emergency_in,
    input  wire       ew_emergency_in,

    output wire [1:0] ns_light,
    output wire [1:0] ew_light,
    output wire [3:0] state,
    output wire [4:0] active_green_time
);

    wire [3:0] ns_density, ew_density;
    wire       ns_clear_density, ew_clear_density;
    wire       emergency_active, serve_ns, emergency_served;

    sensor_unit u_sensor_ns (
        .clk           (clk),
        .rst_n         (rst_n),
        .vehicle_pulse (ns_vehicle_pulse),
        .sample_en     (1'b1),
        .clear_density (ns_clear_density),
        .density       (ns_density)
    );

    sensor_unit u_sensor_ew (
        .clk           (clk),
        .rst_n         (rst_n),
        .vehicle_pulse (ew_vehicle_pulse),
        .sample_en     (1'b1),
        .clear_density (ew_clear_density),
        .density       (ew_density)
    );

    emergency_unit u_emergency (
        .clk               (clk),
        .rst_n             (rst_n),
        .ns_emergency_in   (ns_emergency_in),
        .ew_emergency_in   (ew_emergency_in),
        .emergency_served  (emergency_served),
        .emergency_active  (emergency_active),
        .serve_ns          (serve_ns),
        .ns_pending        (),
        .ew_pending        ()
    );

    traffic_fsm u_fsm (
        .clk               (clk),
        .rst_n             (rst_n),
        .ns_density        (ns_density),
        .ew_density        (ew_density),
        .ns_clear_density  (ns_clear_density),
        .ew_clear_density  (ew_clear_density),
        .emergency_active  (emergency_active),
        .serve_ns          (serve_ns),
        .emergency_served  (emergency_served),
        .ns_light          (ns_light),
        .ew_light          (ew_light),
        .state             (state),
        .active_green_time (active_green_time)
    );

endmodule
