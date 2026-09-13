`timescale 1ns / 1ps

// THIS MODEL IS FOR TESTBENCH USE ONLY!
module beh_fifo #(
    parameter DSIZE = 8,
    parameter ASIZE = 4
) (
    output wire [DSIZE-1:0] rdata,
    output wire             wfull,
    output wire             rempty,
    input  wire [DSIZE-1:0] wdata,
    input  wire             winc, wclk, wrst_n,
    input  wire             rinc, rclk, rrst_n
);

    reg [ASIZE:0] wptr, wrptr1, wrptr2, wrptr3;
    reg [ASIZE:0] rptr, rwptr1, rwptr2, rwptr3;

    localparam MEMDEPTH = 1 << ASIZE;
    reg [DSIZE-1:0] ex_mem [0:MEMDEPTH-1];

    // Write Logic
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr <= 0;
        end else if (winc && !wfull) begin
            ex_mem[wptr[ASIZE-1:0]] <= wdata;
            wptr <= wptr + 1;
        end
    end

    // Sync Read Pointer to Write Domain (Behavioral delay match)
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {wrptr3, wrptr2, wrptr1} <= 0;
        else         {wrptr3, wrptr2, wrptr1} <= {wrptr2, wrptr1, rptr};
    end

    // Read Logic
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rptr <= 0;
        else if (rinc && !rempty) rptr <= rptr + 1;
    end

    // Sync Write Pointer to Read Domain (Behavioral delay match)
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {rwptr3, rwptr2, rwptr1} <= 0;
        else         {rwptr3, rwptr2, rwptr1} <= {rwptr2, rwptr1, wptr};
    end

    assign rdata  = ex_mem[rptr[ASIZE-1:0]];
    assign rempty = (rptr == rwptr3);
    
    // Full flag compares MSBs using behavioral logic
    assign wfull  = ((wptr[ASIZE-1:0] == wrptr3[ASIZE-1:0]) && 
                     (wptr[ASIZE]     != wrptr3[ASIZE]));

endmodule