// ============================================================================
// Module      : emergency_unit
// Description : Detects emergency-vehicle requests coming from the two
//               approach groups (NS and EW) and arbitrates which one is
//               served when a request is active. If both groups request
//               service in the SAME cycle (the "simultaneous arrival at
//               different junctions/approaches" case, see additional task),
//               a round-robin/last-served flag (last_served) is used so the
//               approach that was NOT served last time wins -> no direction
//               is starved and requests are never silently dropped. The
//               loser is latched (pending) and served immediately after the
//               winner's emergency phase completes.
// ============================================================================
module emergency_unit (
    input  wire clk,
    input  wire rst_n,
    input  wire ns_emergency_in,   // raw request, level or pulse, from NS approach
    input  wire ew_emergency_in,   // raw request, level or pulse, from EW approach
    input  wire emergency_served,  // pulse from FSM: current emergency phase finished
    output reg  emergency_active,  // a preemption is in progress / pending
    output reg  serve_ns,          // 1 = serve NS emergency, 0 = serve EW emergency
    output reg  ns_pending,
    output reg  ew_pending
);

    reg last_served_ns; // fairness memory: 1 if NS was granted last time

    // Latch incoming requests so short pulses are not lost while busy
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ns_pending <= 1'b0;
            ew_pending <= 1'b0;
        end else begin
            if (ns_emergency_in) ns_pending <= 1'b1;
            if (ew_emergency_in) ew_pending <= 1'b1;
            if (emergency_active && serve_ns && emergency_served)  ns_pending <= 1'b0;
            if (emergency_active && !serve_ns && emergency_served) ew_pending <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            emergency_active <= 1'b0;
            serve_ns         <= 1'b0;
            last_served_ns   <= 1'b0;
        end else begin
            if (!emergency_active) begin
                if (ns_pending && ew_pending) begin
                    // simultaneous request from both approaches: alternate
                    // fairly instead of always favouring one direction
                    emergency_active <= 1'b1;
                    serve_ns         <= ~last_served_ns;
                    last_served_ns   <= ~last_served_ns;
                end else if (ns_pending) begin
                    emergency_active <= 1'b1;
                    serve_ns         <= 1'b1;
                    last_served_ns   <= 1'b1;
                end else if (ew_pending) begin
                    emergency_active <= 1'b1;
                    serve_ns         <= 1'b0;
                    last_served_ns   <= 1'b0;
                end
            end else if (emergency_served) begin
                // Serve the other pending direction immediately if it was
                // queued while we were busy, otherwise go idle.
                if (serve_ns && ew_pending) begin
                    serve_ns       <= 1'b0;
                    last_served_ns <= 1'b0;
                    // stays active, now servicing EW
                end else if (!serve_ns && ns_pending) begin
                    serve_ns       <= 1'b1;
                    last_served_ns <= 1'b1;
                    // stays active, now servicing NS
                end else begin
                    emergency_active <= 1'b0;
                end
            end
        end
    end

endmodule
