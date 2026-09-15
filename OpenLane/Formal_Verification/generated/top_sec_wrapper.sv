`timescale 1ns / 1ps

// ============================================================
// GENERIC DELAY MODULE FOR LATENCY ALIGNMENT
// ============================================================
module fec_delay #(
    parameter integer WIDTH = 64,
    parameter integer LATENCY = 0
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] data_in,
    input  wire             valid_in,
    output wire [WIDTH-1:0] data_out,
    output wire             valid_out
);
    generate
        if (LATENCY == 0) begin : gen_comb
            assign data_out = data_in;
            assign valid_out = valid_in;
        end else begin : gen_pipe
            reg [WIDTH-1:0] data_pipe [0:LATENCY-1];
            reg             valid_pipe [0:LATENCY-1];
            
            integer i;
            always @(posedge clk) begin
                if (!rst_n) begin
                    for (i = 0; i < LATENCY; i = i + 1) begin
                        data_pipe[i] <= {WIDTH{1'b0}};
                        valid_pipe[i] <= 1'b0;
                    end
                end else begin
                    data_pipe[0] <= data_in;
                    valid_pipe[0] <= valid_in;
                    for (i = 1; i < LATENCY; i = i + 1) begin
                        data_pipe[i] <= data_pipe[i-1];
                        valid_pipe[i] <= valid_pipe[i-1];
                    end
                end
            end
            assign data_out = data_pipe[LATENCY-1];
            assign valid_out = valid_pipe[LATENCY-1];
        end
    endgenerate
endmodule

// ============================================================
// FORMAL SEC WRAPPER
// ============================================================
module top_sec_wrapper (
    input wire clk_in_0,
    input wire rst_n_in_0,
    input wire clk_in_1,
    input wire rst_n_in_1,
    input wire clk_in_2,
    input wire rst_n_in_2,
    input wire clk_out_0,
    input wire rst_n_out_0,
    input wire clk_out_1,
    input wire rst_n_out_1,
    input wire clk_out_2,
    input wire rst_n_out_2,
    input wire [3:0] p0_data_in,
    input wire p0_valid_in,
    input wire [1:0] p0_dest_in,
    input wire [3:0] p1_data_in,
    input wire p1_valid_in,
    input wire [1:0] p1_dest_in,
    input wire [3:0] p2_data_in,
    input wire p2_valid_in,
    input wire [1:0] p2_dest_in,
    input wire p0_ready_ext,
    input wire p1_ready_ext,
    input wire p2_ready_ext
);

    // ============================================================
    // INTERNAL SIGNALS
    // ============================================================
    wire g_gen_clk_in0_div2;
    wire r_gen_clk_in0_div2;
    wire g_gen_clk_in1_div4;
    wire r_gen_clk_in1_div4;
    wire g_gen_clk_out0_div8;
    wire r_gen_clk_out0_div8;
    wire g_p0_ready_out;
    wire r_p0_ready_out;
    wire g_p1_ready_out;
    wire r_p1_ready_out;
    wire g_p2_ready_out;
    wire r_p2_ready_out;
    wire [3:0] g_p0_data_out;
    wire [3:0] r_p0_data_out;
    wire g_p0_valid_out;
    wire r_p0_valid_out;
    wire [3:0] g_p0_aligned_data;
    wire g_p0_aligned_valid;
    wire [3:0] r_p0_aligned_data;
    wire r_p0_aligned_valid;
    wire [3:0] g_p1_data_out;
    wire [3:0] r_p1_data_out;
    wire g_p1_valid_out;
    wire r_p1_valid_out;
    wire [3:0] g_p1_aligned_data;
    wire g_p1_aligned_valid;
    wire [3:0] r_p1_aligned_data;
    wire r_p1_aligned_valid;
    wire [3:0] g_p2_data_out;
    wire [3:0] r_p2_data_out;
    wire g_p2_valid_out;
    wire r_p2_valid_out;
    wire [3:0] g_p2_aligned_data;
    wire g_p2_aligned_valid;
    wire [3:0] r_p2_aligned_data;
    wire r_p2_aligned_valid;

    // ============================================================
    // FORMAL RESET / INITIALIZATION
    // ============================================================
    reg f_past_valid = 0;
    reg [3:0] f_rst_cnt = 0;
    always @(posedge clk_out_0) begin
        f_past_valid <= 1;
        if (f_rst_cnt < 10) begin
            f_rst_cnt <= f_rst_cnt + 1;
            assume(!rst_n_in_0);
            assume(!rst_n_in_1);
            assume(!rst_n_in_2);
            assume(!rst_n_out_0);
            assume(!rst_n_out_1);
            assume(!rst_n_out_2);
        end
    end

    // ============================================================
    // GOLDEN INSTANCE
    // ============================================================
    gold u_gold (
        .clk_in_0(clk_in_0),
        .rst_n_in_0(rst_n_in_0),
        .clk_in_1(clk_in_1),
        .rst_n_in_1(rst_n_in_1),
        .clk_in_2(clk_in_2),
        .rst_n_in_2(rst_n_in_2),
        .clk_out_0(clk_out_0),
        .rst_n_out_0(rst_n_out_0),
        .clk_out_1(clk_out_1),
        .rst_n_out_1(rst_n_out_1),
        .clk_out_2(clk_out_2),
        .rst_n_out_2(rst_n_out_2),
        .p0_data_in(p0_data_in),
        .p0_valid_in(p0_valid_in),
        .p0_dest_in(p0_dest_in),
        .p1_data_in(p1_data_in),
        .p1_valid_in(p1_valid_in),
        .p1_dest_in(p1_dest_in),
        .p2_data_in(p2_data_in),
        .p2_valid_in(p2_valid_in),
        .p2_dest_in(p2_dest_in),
        .p0_ready_ext(p0_ready_ext),
        .p1_ready_ext(p1_ready_ext),
        .p2_ready_ext(p2_ready_ext),
        .gen_clk_in0_div2(g_gen_clk_in0_div2),
        .gen_clk_in1_div4(g_gen_clk_in1_div4),
        .gen_clk_out0_div8(g_gen_clk_out0_div8),
        .p0_ready_out(g_p0_ready_out),
        .p1_ready_out(g_p1_ready_out),
        .p2_ready_out(g_p2_ready_out),
        .p0_data_out(g_p0_data_out),
        .p0_valid_out(g_p0_valid_out),
        .p1_data_out(g_p1_data_out),
        .p1_valid_out(g_p1_valid_out),
        .p2_data_out(g_p2_data_out),
        .p2_valid_out(g_p2_valid_out)
    );

    // ============================================================
    // REVISED INSTANCE
    // ============================================================
    revised u_revised (
        .clk_in_0(clk_in_0),
        .rst_n_in_0(rst_n_in_0),
        .clk_in_1(clk_in_1),
        .rst_n_in_1(rst_n_in_1),
        .clk_in_2(clk_in_2),
        .rst_n_in_2(rst_n_in_2),
        .clk_out_0(clk_out_0),
        .rst_n_out_0(rst_n_out_0),
        .clk_out_1(clk_out_1),
        .rst_n_out_1(rst_n_out_1),
        .clk_out_2(clk_out_2),
        .rst_n_out_2(rst_n_out_2),
        .p0_data_in(p0_data_in),
        .p0_valid_in(p0_valid_in),
        .p0_dest_in(p0_dest_in),
        .p1_data_in(p1_data_in),
        .p1_valid_in(p1_valid_in),
        .p1_dest_in(p1_dest_in),
        .p2_data_in(p2_data_in),
        .p2_valid_in(p2_valid_in),
        .p2_dest_in(p2_dest_in),
        .p0_ready_ext(p0_ready_ext),
        .p1_ready_ext(p1_ready_ext),
        .p2_ready_ext(p2_ready_ext),
        .gen_clk_in0_div2(r_gen_clk_in0_div2),
        .gen_clk_in1_div4(r_gen_clk_in1_div4),
        .gen_clk_out0_div8(r_gen_clk_out0_div8),
        .p0_ready_out(r_p0_ready_out),
        .p1_ready_out(r_p1_ready_out),
        .p2_ready_out(r_p2_ready_out),
        .p0_data_out(r_p0_data_out),
        .p0_valid_out(r_p0_valid_out),
        .p1_data_out(r_p1_data_out),
        .p1_valid_out(r_p1_valid_out),
        .p2_data_out(r_p2_data_out),
        .p2_valid_out(r_p2_valid_out)
    );

    // ============================================================
    // LATENCY ALIGNMENT
    // ============================================================
    // --------------------------------------------------------
    // Latency Alignment: Interface p0 (diff: 0)
    // --------------------------------------------------------
    assign g_p0_aligned_data = g_p0_data_out;
    assign g_p0_aligned_valid = g_p0_valid_out;
    assign r_p0_aligned_data = r_p0_data_out;
    assign r_p0_aligned_valid = r_p0_valid_out;

    // --------------------------------------------------------
    // Latency Alignment: Interface p1 (diff: 0)
    // --------------------------------------------------------
    assign g_p1_aligned_data = g_p1_data_out;
    assign g_p1_aligned_valid = g_p1_valid_out;
    assign r_p1_aligned_data = r_p1_data_out;
    assign r_p1_aligned_valid = r_p1_valid_out;

    // --------------------------------------------------------
    // Latency Alignment: Interface p2 (diff: 0)
    // --------------------------------------------------------
    assign g_p2_aligned_data = g_p2_data_out;
    assign g_p2_aligned_valid = g_p2_valid_out;
    assign r_p2_aligned_data = r_p2_data_out;
    assign r_p2_aligned_valid = r_p2_valid_out;


    // ============================================================
    // EQUIVALENCE ASSERTIONS
    // ============================================================
    always @(posedge clk_out_0) begin
        if (f_past_valid && rst_n_out_0) begin
            assert(g_p0_aligned_valid == r_p0_aligned_valid);
            if (g_p0_aligned_valid) assert(g_p0_aligned_data == r_p0_aligned_data);
        end
    end

    always @(posedge clk_out_1) begin
        if (f_past_valid && rst_n_out_1) begin
            assert(g_p1_aligned_valid == r_p1_aligned_valid);
            if (g_p1_aligned_valid) assert(g_p1_aligned_data == r_p1_aligned_data);
        end
    end

    always @(posedge clk_out_2) begin
        if (f_past_valid && rst_n_out_2) begin
            assert(g_p2_aligned_valid == r_p2_aligned_valid);
            if (g_p2_aligned_valid) assert(g_p2_aligned_data == r_p2_aligned_data);
        end
    end


endmodule
