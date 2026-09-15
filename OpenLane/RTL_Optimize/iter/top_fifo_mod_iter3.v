// ==========================================
// BOTTLENECK LEAF MODULE
// Original File: /home/basith/CORTEX/OpenLane/designs/my_design/src/top_fifo.v
// ==========================================

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

// Helper Submodules for Standalone Compilation
module fifo #(
    parameter DATASIZE = 8,
    parameter ADDRSIZE = 4
) (
    input  wire                wclk,
    input  wire                wclken,
    input  wire                wfull,
    input  wire [ADDRSIZE-1:0] waddr,
    input  wire [ADDRSIZE-1:0] raddr,
    input  wire [DATASIZE-1:0] wdata,
    output wire [DATASIZE-1:0] rdata
);
    reg [DATASIZE-1:0] mem [0:(1<<ADDRSIZE)-1];
    assign rdata = mem[raddr];
    always @(posedge wclk) begin
        if (wclken && !wfull)
            mem[waddr] <= wdata;
    end
endmodule

module sync_r2w #(
    parameter N = 5
) (
    input  wire         wclk,
    input  wire         wrst_n,
    input  wire [N-1:0] rptr,
    output reg  [N-1:0] wq2_rptr
);
    reg [N-1:0] wq1_rptr;
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wq1_rptr <= {N{1'b0}};
            wq2_rptr <= {N{1'b0}};
        end else begin
            wq1_rptr <= rptr;
            wq2_rptr <= wq1_rptr;
        end
    end
endmodule

module sync_w2r #(
    parameter N = 5
) (
    input  wire         rclk,
    input  wire         rrst_n,
    input  wire [N-1:0] wptr,
    output reg  [N-1:0] rq2_wptr
);
    reg [N-1:0] rq1_wptr;
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rq1_wptr <= {N{1'b0}};
            rq2_wptr <= {N{1'b0}};
        end else begin
            rq1_wptr <= wptr;
            rq2_wptr <= rq1_wptr;
        end
    end
endmodule

module wptr_full #(
    parameter ADDRSIZE = 4
) (
    input  wire                wclk,
    input  wire                wrst_n,
    input  wire                winc,
    input  wire [ADDRSIZE:0]   wq2_rptr,
    output reg                 wfull,
    output wire [ADDRSIZE-1:0] waddr,
    output reg  [ADDRSIZE:0]   wptr
);
    reg [ADDRSIZE:0] wbin;
    wire [ADDRSIZE:0] wbinnext = wbin + (winc & !wfull);
    wire [ADDRSIZE:0] wgraynext = (wbinnext >> 1) ^ wbinnext;
    wire wfull_val = (wgraynext == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1], wq2_rptr[ADDRSIZE-2:0]});

    assign waddr = wbin[ADDRSIZE-1:0];

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= 0;
            wptr  <= 0;
            wfull <= 1'b0;
        end else begin
            wbin  <= wbinnext;
            wptr  <= wgraynext;
            wfull <= wfull_val;
        end
    end
endmodule

module rptr_empty #(
    parameter ADDRSIZE = 4
) (
    input  wire                rclk,
    input  wire                rrst_n,
    input  wire                rinc,
    input  wire [ADDRSIZE:0]   rq2_wptr,
    output reg                 rempty,
    output wire [ADDRSIZE-1:0] raddr,
    output reg  [ADDRSIZE:0]   rptr
);
    reg [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rbinnext = rbin + (rinc & !rempty);
    wire [ADDRSIZE:0] rgraynext = (rbinnext >> 1) ^ rbinnext;
    wire rempty_val = (rgraynext == rq2_wptr);

    assign raddr = rbin[ADDRSIZE-1:0];

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= 0;
            rptr   <= 0;
            rempty <= 1'b1;
        end else begin
            rbin   <= rbinnext;
            rptr   <= rgraynext;
            rempty <= rempty_val;
        end
    end
endmodule