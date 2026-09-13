`timescale 1ns / 1ps

module sync_w2r #(
    parameter N = 5  
) (
    input  wire         rclk,     // Read clock domain
    input  wire         rrst_n,   // Read domain active-low asynchronous reset
    input  wire [N-1:0] wptr,     // Gray code pointer coming FROM write domain
    output reg  [N-1:0] rq2_wptr  // Synchronized pointer going TO read domain logic
);

    reg [N-1:0] rq1_wptr; // First stage of the 2-flop synchronizer

 
    // 2-Flop Shift Register using concatenation

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            {rq2_wptr, rq1_wptr} <= {2*N{1'b0}};
        end
        else begin
            // Shift wptr into stage 1, and stage 1 into stage 2
            {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};
        end
    end

endmodule