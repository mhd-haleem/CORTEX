`timescale 1ns / 1ps

module wptr_full #(
    parameter ADDRSIZE = 4  // Memory address size (Depth = 16)
) (
    input  wire                wclk,
    input  wire                wrst_n,
    input  wire                winc,
    input  wire [ADDRSIZE:0]   wq2_rptr, // Synchronized read pointer
    output reg                 wfull,    // Full flag
    output wire [ADDRSIZE-1:0] waddr,    // Binary memory address
    output reg  [ADDRSIZE:0]   wptr      // Gray code write pointer
);

    reg  [ADDRSIZE:0] wbin;
    wire [ADDRSIZE:0] wgraynext, wbinnext;
    wire              wfull_val;

    
    // Dual n-bit Gray code counter (Style #2)
    
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            {wbin, wptr} <= {(2*(ADDRSIZE+1)){1'b0}};
        end 
        else begin
            {wbin, wptr} <= {wbinnext, wgraynext};
        end
    end

    // Memory write-address pointer (binary is safe to use for memory)
    assign waddr = wbin[ADDRSIZE-1:0];

    // Conditional binary increment
    assign wbinnext = wbin + (winc & ~wfull);

    // Combinational Binary-to-Gray conversion
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;

   
    // FIFO Full Logic
    
    // FIFO is full when:
    // 1. MSBs are not equal
    // 2. 2nd MSBs are not equal
    // 3. All other LSBs are equal
    // This is cleanly handled using a concatenation check.
    assign wfull_val = (wgraynext == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1], wq2_rptr[ADDRSIZE-2:0]});

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wfull <= 1'b0; // FIFO is not full upon reset
        end 
        else begin
            wfull <= wfull_val;
        end
    end

endmodule