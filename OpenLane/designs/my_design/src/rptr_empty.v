`timescale 1ns / 1ps

module rptr_empty #(
    parameter ADDRSIZE = 4  // Memory address size (Depth = 16)
) (
    input  wire                rclk,
    input  wire                rrst_n,
    input  wire                rinc,
    input  wire [ADDRSIZE:0]   rq2_wptr, // Synchronized write pointer
    output reg                 rempty,   // Empty flag
    output wire [ADDRSIZE-1:0] raddr,    // Binary memory address
    output reg  [ADDRSIZE:0]   rptr      // Gray code read pointer
);

    reg  [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rgraynext, rbinnext;
    wire              rempty_val;

    
    // Dual n-bit Gray code counter (Style #2)
    
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            {rbin, rptr} <= {(2*(ADDRSIZE+1)){1'b0}};
        end 
        else begin
            {rbin, rptr} <= {rbinnext, rgraynext};
        end
    end

    // Memory read-address pointer (binary is safe to use for memory)
    assign raddr = rbin[ADDRSIZE-1:0];

    // Conditional binary increment
    assign rbinnext = rbin + (rinc & ~rempty);

    // Combinational Binary-to-Gray conversion
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;

    
    // FIFO Empty Logic
    
    // FIFO is empty when the next read pointer equals the synchronized write pointer
    assign rempty_val = (rgraynext == rq2_wptr);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1'b1; // FIFO is empty upon reset
        end 
        else begin
            rempty <= rempty_val;
        end
    end

endmodule