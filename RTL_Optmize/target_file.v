// ==========================================
// FULL SOURCE CODE FOR BOTTLENECK FILE 1 OF 3
// File Path: designs/my_design/src/xbar_3by3_bencmark_top.v
// ==========================================

`timescale 1ns / 1ps

module xbar_3by3_benchmark_top #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 5   // Depth = 32
)(
    // 6 Master Asynchronous Clock Domains
    input  wire                  clk_in_0,
    input  wire                  rst_n_in_0,
    input  wire                  clk_in_1,
    input  wire                  rst_n_in_1,
    input  wire                  clk_in_2,
    input  wire                  rst_n_in_2,

    input  wire                  clk_out_0,
    input  wire                  rst_n_out_0,
    input  wire                  clk_out_1,
    input  wire                  rst_n_out_1,
    input  wire                  clk_out_2,
    input  wire                  rst_n_out_2,

    // Generated Clocks (Divided)
    output wire                  gen_clk_in0_div2,
    output wire                  gen_clk_in1_div4,
    output wire                  gen_clk_out0_div8,

    // Input Port 0
    input  wire [DATA_WIDTH-1:0] p0_data_in,
    input  wire                  p0_valid_in,
    input  wire [1:0]            p0_dest_in,
    output wire                  p0_ready_out,

    // Input Port 1
    input  wire [DATA_WIDTH-1:0] p1_data_in,
    input  wire                  p1_valid_in,
    input  wire [1:0]            p1_dest_in,
    output wire                  p1_ready_out,

    // Input Port 2
    input  wire [DATA_WIDTH-1:0] p2_data_in,
    input  wire                  p2_valid_in,
    input  wire [1:0]            p2_dest_in,
    output wire                  p2_ready_out,

    // Output Port 0
    output wire [DATA_WIDTH-1:0] p0_data_out,
    output wire                  p0_valid_out,
    input  wire                  p0_ready_ext,

    // Output Port 1
    output wire [DATA_WIDTH-1:0] p1_data_out,
    output wire                  p1_valid_out,
    input  wire                  p1_ready_ext,

    // Output Port 2
    output wire [DATA_WIDTH-1:0] p2_data_out,
    output wire                  p2_valid_out,
    input  wire                  p2_ready_ext
);

    // ============================================================
    // 1. CLOCK DIVIDER MODULES (Generated Clocks)
    // ============================================================
    clk_divider DIV_IN0  (.clk_in(clk_in_0),  .rst_n(rst_n_in_0),  .clk_div2(gen_clk_in0_div2), .clk_div4(), .clk_div8());
    clk_divider DIV_IN1  (.clk_in(clk_in_1),  .rst_n(rst_n_in_1),  .clk_div2(), .clk_div4(gen_clk_in1_div4), .clk_div8());
    clk_divider DIV_OUT0 (.clk_in(clk_out_0), .rst_n(rst_n_out_0), .clk_div2(), .clk_div4(), .clk_div8(gen_clk_out0_div8));

    // ============================================================
    // 2. INTERNAL INTERCONNECT WIRES
    // ============================================================
    // Write Increments & Fulls
    wire winc[2:0][2:0];
    wire wfull[2:0][2:0];
    wire [DATA_WIDTH-1:0] wdata_bus[2:0];

    // Read Increments, Empties, & Data
    wire rinc[2:0][2:0];
    wire rempty[2:0][2:0];
    wire [DATA_WIDTH-1:0] rdata_bus[2:0][2:0];

    // ============================================================
    // 3. INPUT DEMUX PORTS
    // ============================================================
    input_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) IN_PORT_0 (
        .data_in(p0_data_in), .valid_in(p0_valid_in), .dest_in(p0_dest_in), .ready_out(p0_ready_out),
        .winc_0(winc[0][0]), .winc_1(winc[0][1]), .winc_2(winc[0][2]),
        .wdata(wdata_bus[0]),
        .wfull_0(wfull[0][0]), .wfull_1(wfull[0][1]), .wfull_2(wfull[0][2])
    );

    input_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) IN_PORT_1 (
        .data_in(p1_data_in), .valid_in(p1_valid_in), .dest_in(p1_dest_in), .ready_out(p1_ready_out),
        .winc_0(winc[1][0]), .winc_1(winc[1][1]), .winc_2(winc[1][2]),
        .wdata(wdata_bus[1]),
        .wfull_0(wfull[1][0]), .wfull_1(wfull[1][1]), .wfull_2(wfull[1][2])
    );

    input_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) IN_PORT_2 (
        .data_in(p2_data_in), .valid_in(p2_valid_in), .dest_in(p2_dest_in), .ready_out(p2_ready_out),
        .winc_0(winc[2][0]), .winc_1(winc[2][1]), .winc_2(winc[2][2]),
        .wdata(wdata_bus[2]),
        .wfull_0(wfull[2][0]), .wfull_1(wfull[2][1]), .wfull_2(wfull[2][2])
    );

    // ============================================================
    // 4. CROSSPOINT 9 ASYNC FIFOs (The CDC Fabric)
    // ============================================================
    genvar in_idx, out_idx;
    generate
        for (in_idx = 0; in_idx < 3; in_idx = in_idx + 1) begin : GEN_IN
            for (out_idx = 0; out_idx < 3; out_idx = out_idx + 1) begin : GEN_OUT

                // Clock and reset multiplexing per domain
                wire fifo_wclk = (in_idx == 0) ? clk_in_0 : (in_idx == 1) ? clk_in_1 : clk_in_2;
                wire fifo_wrst = (in_idx == 0) ? rst_n_in_0 : (in_idx == 1) ? rst_n_in_1 : rst_n_in_2;

                wire fifo_rclk = (out_idx == 0) ? clk_out_0 : (out_idx == 1) ? clk_out_1 : clk_out_2;
                wire fifo_rrst = (out_idx == 0) ? rst_n_out_0 : (out_idx == 1) ? rst_n_out_1 : rst_n_out_2;

                // Instantiating the verified top_fifo
                top_fifo #(
                    .DSIZE(DATA_WIDTH),
                    .ASIZE(ADDR_WIDTH)
                ) FIFO_CROSSPOINT (
                    .wclk   (fifo_wclk),
                    .wrst_n (fifo_wrst),
                    .winc   (winc[in_idx][out_idx]),
                    .wdata  (wdata_bus[in_idx]),
                    .wfull  (wfull[in_idx][out_idx]),

                    .rclk   (fifo_rclk),
                    .rrst_n (fifo_rrst),
                    .rinc   (rinc[out_idx][in_idx]),
                    .rdata  (rdata_bus[out_idx][in_idx]),
                    .rempty (rempty[out_idx][in_idx])
                );
            end
        end
    endgenerate

    // ============================================================
    // 5. OUTPUT PORTS & ARBITERS
    // ============================================================
    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_0 (
        .clk_out(clk_out_0), .rst_n(rst_n_out_0),
        .empty_0(rempty[0][0]), .empty_1(rempty[0][1]), .empty_2(rempty[0][2]),
        .rdata_0(rdata_bus[0][0]), .rdata_1(rdata_bus[0][1]), .rdata_2(rdata_bus[0][2]),
        .rinc_0(rinc[0][0]), .rinc_1(rinc[0][1]), .rinc_2(rinc[0][2]),
        .data_out(p0_data_out), .valid_out(p0_valid_out), .ready_ext(p0_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_1 (
        .clk_out(clk_out_1), .rst_n(rst_n_out_1),
        .empty_0(rempty[1][0]), .empty_1(rempty[1][1]), .empty_2(rempty[1][2]),
        .rdata_0(rdata_bus[1][0]), .rdata_1(rdata_bus[1][1]), .rdata_2(rdata_bus[1][2]),
        .rinc_0(rinc[1][0]), .rinc_1(rinc[1][1]), .rinc_2(rinc[1][2]),
        .data_out(p1_data_out), .valid_out(p1_valid_out), .ready_ext(p1_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_2 (
        .clk_out(clk_out_2), .rst_n(rst_n_out_2),
        .empty_0(rempty[2][0]), .empty_1(rempty[2][1]), .empty_2(rempty[2][2]),
        .rdata_0(rdata_bus[2][0]), .rdata_1(rdata_bus[2][1]), .rdata_2(rdata_bus[2][2]),
        .rinc_0(rinc[2][0]), .rinc_1(rinc[2][1]), .rinc_2(rinc[2][2]),
        .data_out(p2_data_out), .valid_out(p2_valid_out), .ready_ext(p2_ready_ext)
    );

endmodule


// ==========================================
// FULL SOURCE CODE FOR BOTTLENECK FILE 2 OF 3
// File Path: designs/my_design/src/rptr_empty.v
// ==========================================

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


// ==========================================
// FULL SOURCE CODE FOR BOTTLENECK FILE 3 OF 3
// File Path: designs/my_design/src/top_fifo.v
// ==========================================

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


