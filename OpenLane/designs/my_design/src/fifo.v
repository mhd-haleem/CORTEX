`timescale 1ns / 1ps

module fifo #(
    parameter DATASIZE = 8,   // Memory data word width
    parameter ADDRSIZE = 4    // Number of mem address bits (Depth = 16)
) (
    input  wire                wclk,
    input  wire                wclken, // Write enable (tied to winc at top level)
    input  wire                wfull,  // Full flag to prevent overwriting
    input  wire [ADDRSIZE-1:0] waddr,  // Binary write address
    input  wire [ADDRSIZE-1:0] raddr,  // Binary read address
    input  wire [DATASIZE-1:0] wdata,  // Data to be written
    output wire [DATASIZE-1:0] rdata   // Data to be read
);

    // Calculate memory depth based on address size
    localparam DEPTH = 1 << ADDRSIZE;

    // Verilog memory array declaration
    reg [DATASIZE-1:0] mem [0:DEPTH-1];

    
    // Continuous Read Operation
    
    // The read data is driven continuously from the array based on the 
    // current read address. This provides "First-Word Fall-Through" behavior.
    assign rdata = mem[raddr];

    
    // Synchronous Write Operation
    
    always @(posedge wclk) begin
        if (wclken && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

endmodule