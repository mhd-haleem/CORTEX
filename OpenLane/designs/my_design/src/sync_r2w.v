`timescale 1ns / 1ps

module sync_r2w #(
    parameter N = 5  // N-bit pointer (size is N, not N-1, because we pass the MSB)
) (
    input  wire         wclk,     // Write clock domain
    input  wire         wrst_n,   // Write domain active-low asynchronous reset
    input  wire [N-1:0] rptr,     // Gray code pointer coming FROM read domain
    output reg  [N-1:0] wq2_rptr  // Synchronized pointer going TO write domain logic
);

    reg [N-1:0] wq1_rptr; // First stage of the 2-flop synchronizer

    // 2-Flop Shift Register using concatenation
    
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            {wq2_rptr, wq1_rptr} <= {2*N{1'b0}}; 
        end
        else begin
            // Shift rptr into stage 1, and stage 1 into stage 2
            {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr}; 
        end
    end

endmodule