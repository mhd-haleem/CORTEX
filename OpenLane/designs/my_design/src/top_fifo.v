`timescale 1ns / 1ps

module top_fifo #(
    parameter DSIZE = 8,  // Data width
    parameter ASIZE = 4   // Address width (Depth = 16)
) (
    // Write Domain
    input  wire             wclk,
    input  wire             wrst_n,
    input  wire             winc,
    input  wire [DSIZE-1:0] wdata,
    output wire             wfull,

    // Read Domain
    input  wire             rclk,
    input  wire             rrst_n,
    input  wire             rinc,
    output wire [DSIZE-1:0] rdata,
    output wire             rempty
);

    // Internal wires for pointer crossings and memory addressing
    wire [ASIZE-1:0] waddr, raddr;
    wire [ASIZE:0]   wptr, rptr, wq2_rptr, rq2_wptr;

    // 1. Dual-Port RAM Instantiation
   
    fifo #(
        .DATASIZE(DSIZE),
        .ADDRSIZE(ASIZE)
    ) fifomem_inst (
        .wclk  (wclk),
        .wclken(winc),
        .wfull (wfull),
        .waddr (waddr),
        .raddr (raddr),
        .wdata (wdata),
        .rdata (rdata)
    );

    // 2. Read-to-Write Synchronizer
    
    sync_r2w #(
        .N(ASIZE + 1)
    ) sync_r2w_inst (
        .wclk    (wclk),
        .wrst_n  (wrst_n),
        .rptr    (rptr),
        .wq2_rptr(wq2_rptr)
    );

    // 3. Write-to-Read Synchronizer
    
    sync_w2r #(
        .N(ASIZE + 1)
    ) sync_w2r_inst (
        .rclk    (rclk),
        .rrst_n  (rrst_n),
        .wptr    (wptr),
        .rq2_wptr(rq2_wptr)
    );

    // 4. Write Pointer & Full Logic
    
    wptr_full #(
        .ADDRSIZE(ASIZE)
    ) wptr_full_inst (
        .wclk    (wclk),
        .wrst_n  (wrst_n),
        .winc    (winc),
        .wq2_rptr(wq2_rptr),
        .wfull   (wfull),
        .waddr   (waddr),
        .wptr    (wptr)
    );

    // 5. Read Pointer & Empty Logic
    
    rptr_empty #(
        .ADDRSIZE(ASIZE)
    ) rptr_empty_inst (
        .rclk    (rclk),
        .rrst_n  (rrst_n),
        .rinc    (rinc),
        .rq2_wptr(rq2_wptr),
        .rempty  (rempty),
        .raddr   (raddr),
        .rptr    (rptr)
    );

endmodule