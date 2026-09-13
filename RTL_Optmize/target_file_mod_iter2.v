module xbar_3by3_benchmark_top #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 5
)(
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

    output wire                  gen_clk_in0_div2,
    output wire                  gen_clk_in1_div4,
    output wire                  gen_clk_out0_div8,

    input  wire [DATA_WIDTH-1:0] p0_data_in,
    input  wire                  p0_valid_in,
    input  wire [1:0]            p0_dest_in,
    output wire                  p0_ready_out,

    input  wire [DATA_WIDTH-1:0] p1_data_in,
    input  wire                  p1_valid_in,
    input  wire [1:0]            p1_dest_in,
    output wire                  p1_ready_out,

    input  wire [DATA_WIDTH-1:0] p2_data_in,
    input  wire                  p2_valid_in,
    input  wire [1:0]            p2_dest_in,
    output wire                  p2_ready_out,

    output wire [DATA_WIDTH-1:0] p0_data_out,
    output wire                  p0_valid_out,
    input  wire                  p0_ready_ext,

    output wire [DATA_WIDTH-1:0] p1_data_out,
    output wire                  p1_valid_out,
    input  wire                  p1_ready_ext,

    output wire [DATA_WIDTH-1:0] p2_data_out,
    output wire                  p2_valid_out,
    input  wire                  p2_ready_ext
);

    clk_divider DIV_IN0  (.clk_in(clk_in_0),  .rst_n(rst_n_in_0),  .clk_div2(gen_clk_in0_div2), .clk_div4(), .clk_div8());
    clk_divider DIV_IN1  (.clk_in(clk_in_1),  .rst_n(rst_n_in_1),  .clk_div2(), .clk_div4(gen_clk_in1_div4), .clk_div8());
    clk_divider DIV_OUT0 (.clk_in(clk_out_0), .rst_n(rst_n_out_0), .clk_div2(), .clk_div4(), .clk_div8(gen_clk_out0_div8));

    wire winc_0_0, winc_0_1, winc_0_2;
    wire winc_1_0, winc_1_1, winc_1_2;
    wire winc_2_0, winc_2_1, winc_2_2;

    wire wfull_0_0, wfull_0_1, wfull_0_2;
    wire wfull_1_0, wfull_1_1, wfull_1_2;
    wire wfull_2_0, wfull_2_1, wfull_2_2;

    wire [DATA_WIDTH-1:0] wdata_0;
    wire [DATA_WIDTH-1:0] wdata_1;
    wire [DATA_WIDTH-1:0] wdata_2;

    wire rinc_0_0, rinc_0_1, rinc_0_2;
    wire rinc_1_0, rinc_1_1, rinc_1_2;
    wire rinc_2_0, rinc_2_1, rinc_2_2;

    wire rempty_0_0, rempty_0_1, rempty_0_2;
    wire rempty_1_0, rempty_1_1, rempty_1_2;
    wire rempty_2_0, rempty_2_1, rempty_2_2;

    wire [DATA_WIDTH-1:0] rdata_0_0, rdata_0_1, rdata_0_2;
    wire [DATA_WIDTH-1:0] rdata_1_0, rdata_1_1, rdata_1_2;
    wire [DATA_WIDTH-1:0] rdata_2_0, rdata_2_1, rdata_2_2;

    input_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) IN_PORT_0 (
        .data_in(p0_data_in), .valid_in(p0_valid_in), .dest_in(p0_dest_in), .ready_out(p0_ready_out),
        .winc_0(winc_0_0), .winc_1(winc_0_1), .winc_2(winc_0_2),
        .wdata(wdata_0),
        .wfull_0(wfull_0_0), .wfull_1(wfull_0_1), .wfull_2(wfull_0_2)
    );

    input_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) IN_PORT_1 (
        .data_in(p1_data_in), .valid_in(p1_valid_in), .dest_in(p1_dest_in), .ready_out(p1_ready_out),
        .winc_0(winc_1_0), .winc_1(winc_1_1), .winc_2(winc_1_2),
        .wdata(wdata_1),
        .wfull_0(wfull_1_0), .wfull_1(wfull_1_1), .wfull_2(wfull_1_2)
    );

    input_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) IN_PORT_2 (
        .data_in(p2_data_in), .valid_in(p2_valid_in), .dest_in(p2_dest_in), .ready_out(p2_ready_out),
        .winc_0(winc_2_0), .winc_1(winc_2_1), .winc_2(winc_2_2),
        .wdata(wdata_2),
        .wfull_0(wfull_2_0), .wfull_1(wfull_2_1), .wfull_2(wfull_2_2)
    );

    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_0_0 (
        .wclk(clk_in_0), .wrst_n(rst_n_in_0), .winc(winc_0_0), .wdata(wdata_0), .wfull(wfull_0_0),
        .rclk(clk_out_0), .rrst_n(rst_n_out_0), .rinc(rinc_0_0), .rdata(rdata_0_0), .rempty(rempty_0_0)
    );
    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_0_1 (
        .wclk(clk_in_0), .wrst_n(rst_n_in_0), .winc(winc_0_1), .wdata(wdata_0), .wfull(wfull_0_1),
        .rclk(clk_out_1), .rrst_n(rst_n_out_1), .rinc(rinc_1_0), .rdata(rdata_1_0), .rempty(rempty_1_0)
    );
    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_0_2 (
        .wclk(clk_in_0), .wrst_n(rst_n_in_0), .winc(winc_0_2), .wdata(wdata_0), .wfull(wfull_0_2),
        .rclk(clk_out_2), .rrst_n(rst_n_out_2), .rinc(rinc_2_0), .rdata(rdata_2_0), .rempty(rempty_2_0)
    );

    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_1_0 (
        .wclk(clk_in_1), .wrst_n(rst_n_in_1), .winc(winc_1_0), .wdata(wdata_1), .wfull(wfull_1_0),
        .rclk(clk_out_0), .rrst_n(rst_n_out_0), .rinc(rinc_0_1), .rdata(rdata_0_1), .rempty(rempty_0_1)
    );
    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_1_1 (
        .wclk(clk_in_1), .wrst_n(rst_n_in_1), .winc(winc_1_1), .wdata(wdata_1), .wfull(wfull_1_1),
        .rclk(clk_out_1), .rrst_n(rst_n_out_1), .rinc(rinc_1_1), .rdata(rdata_1_1), .rempty(rempty_1_1)
    );
    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_1_2 (
        .wclk(clk_in_1), .wrst_n(rst_n_in_1), .winc(winc_1_2), .wdata(wdata_1), .wfull(wfull_1_2),
        .rclk(clk_out_2), .rrst_n(rst_n_out_2), .rinc(rinc_2_1), .rdata(rdata_2_1), .rempty(rempty_2_1)
    );

    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_2_0 (
        .wclk(clk_in_2), .wrst_n(rst_n_in_2), .winc(winc_2_0), .wdata(wdata_2), .wfull(wfull_2_0),
        .rclk(clk_out_0), .rrst_n(rst_n_out_0), .rinc(rinc_0_2), .rdata(rdata_0_2), .rempty(rempty_0_2)
    );
    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_2_1 (
        .wclk(clk_in_2), .wrst_n(rst_n_in_2), .winc(winc_2_1), .wdata(wdata_2), .wfull(wfull_2_1),
        .rclk(clk_out_1), .rrst_n(rst_n_out_1), .rinc(rinc_1_2), .rdata(rdata_1_2), .rempty(rempty_1_2)
    );
    top_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(ADDR_WIDTH)) FIFO_2_2 (
        .wclk(clk_in_2), .wrst_n(rst_n_in_2), .winc(winc_2_2), .wdata(wdata_2), .wfull(wfull_2_2),
        .rclk(clk_out_2), .rrst_n(rst_n_out_2), .rinc(rinc_2_2), .rdata(rdata_2_2), .rempty(rempty_2_2)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_0 (
        .clk_out(clk_out_0), .rst_n(rst_n_out_0),
        .empty_0(rempty_0_0), .empty_1(rempty_0_1), .empty_2(rempty_0_2),
        .rdata_0(rdata_0_0), .rdata_1(rdata_0_1), .rdata_2(rdata_0_2),
        .rinc_0(rinc_0_0), .rinc_1(rinc_0_1), .rinc_2(rinc_0_2),
        .data_out(p0_data_out), .valid_out(p0_valid_out), .ready_ext(p0_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_1 (
        .clk_out(clk_out_1), .rst_n(rst_n_out_1),
        .empty_0(rempty_1_0), .empty_1(rempty_1_1), .empty_2(rempty_1_2),
        .rdata_0(rdata_1_0), .rdata_1(rdata_1_1), .rdata_2(rdata_1_2),
        .rinc_0(rinc_1_0), .rinc_1(rinc_1_1), .rinc_2(rinc_1_2),
        .data_out(p1_data_out), .valid_out(p1_valid_out), .ready_ext(p1_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_2 (
        .clk_out(clk_out_2), .rst_n(rst_n_out_2),
        .empty_0(rempty_2_0), .empty_1(rempty_2_1), .empty_2(rempty_2_2),
        .rdata_0(rdata_2_0), .rdata_1(rdata_2_1), .rdata_2(rdata_2_2),
        .rinc_0(rinc_2_0), .rinc_1(rinc_2_1), .rinc_2(rinc_2_2),
        .data_out(p2_data_out), .valid_out(p2_valid_out), .ready_ext(p2_ready_ext)
    );

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

    reg  [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rgraynext;
    wire [ADDRSIZE:0] rbinnext;
    wire              rempty_val;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin <= {ADDRSIZE+1{1'b0}};
            rptr <= {ADDRSIZE+1{1'b0}};
        end 
        else begin
            rbin <= rbinnext;
            rptr <= rgraynext;
        end
    end

    assign raddr = rbin[ADDRSIZE-1:0];
    assign rbinnext = rbin + (rinc & ~rempty);
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;
    assign rempty_val = (rgraynext == rq2_wptr);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1'b1;
        end 
        else begin
            rempty <= rempty_val;
        end
    end

endmodule

module top_fifo #(
    parameter DSIZE = 8,
    parameter ASIZE = 4
) (
    input  wire             wclk,
    input  wire             wrst_n,
    input  wire             winc,
    input  wire [DSIZE-1:0] wdata,
    output wire             wfull,

    input  wire             rclk,
    input  wire             rrst_n,
    input  wire             rinc,
    output wire [DSIZE-1:0] rdata,
    output wire             rempty
);

    wire [ASIZE-1:0] waddr, raddr;
    wire [ASIZE:0]   wptr, rptr, wq2_rptr, rq2_wptr;

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

    sync_r2w #(
        .N(ASIZE + 1)
    ) sync_r2w_inst (
        .wclk    (wclk),
        .wrst_n  (wrst_n),
        .rptr    (rptr),
        .wq2_rptr(wq2_rptr)
    );

    sync_w2r #(
        .N(ASIZE + 1)
    ) sync_w2r_inst (
        .rclk    (rclk),
        .rrst_n  (rrst_n),
        .wptr    (wptr),
        .rq2_wptr(rq2_wptr)
    );

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