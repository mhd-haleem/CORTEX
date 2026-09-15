`timescale 1ns / 1ps

module top_sec_wrapper (
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

    // Input Port 0
    input  wire [63:0]           p0_data_in,
    input  wire                  p0_valid_in,
    input  wire [1:0]            p0_dest_in,

    // Input Port 1
    input  wire [63:0]           p1_data_in,
    input  wire                  p1_valid_in,
    input  wire [1:0]            p1_dest_in,

    // Input Port 2
    input  wire [63:0]           p2_data_in,
    input  wire                  p2_valid_in,
    input  wire [1:0]            p2_dest_in,

    // External Readys
    input  wire                  p0_ready_ext,
    input  wire                  p1_ready_ext,
    input  wire                  p2_ready_ext
);

    // ============================================================
    // 1. Formal Reset Sequence
    // ============================================================
    reg f_past_valid = 0;
    always @(posedge clk_out_0) begin
        f_past_valid <= 1;
        if (!f_past_valid) begin
            assume(!rst_n_in_0);
            assume(!rst_n_in_1);
            assume(!rst_n_in_2);
            assume(!rst_n_out_0);
            assume(!rst_n_out_1);
            assume(!rst_n_out_2);
        end
    end

    // ============================================================
    // 2. Instantiate Golden Top Level (No modifications)
    // ============================================================
    wire        g_p0_ready_out, g_p1_ready_out, g_p2_ready_out;
    wire [63:0] g_p0_data_out,  g_p1_data_out,  g_p2_data_out;
    wire        g_p0_valid_out, g_p1_valid_out, g_p2_valid_out;

    gold u_gold (
        .clk_in_0(clk_in_0), .rst_n_in_0(rst_n_in_0),
        .clk_in_1(clk_in_1), .rst_n_in_1(rst_n_in_1),
        .clk_in_2(clk_in_2), .rst_n_in_2(rst_n_in_2),
        .clk_out_0(clk_out_0), .rst_n_out_0(rst_n_out_0),
        .clk_out_1(clk_out_1), .rst_n_out_1(rst_n_out_1),
        .clk_out_2(clk_out_2), .rst_n_out_2(rst_n_out_2),

        .p0_data_in(p0_data_in), .p0_valid_in(p0_valid_in), .p0_dest_in(p0_dest_in), .p0_ready_out(g_p0_ready_out),
        .p1_data_in(p1_data_in), .p1_valid_in(p1_valid_in), .p1_dest_in(p1_dest_in), .p1_ready_out(g_p1_ready_out),
        .p2_data_in(p2_data_in), .p2_valid_in(p2_valid_in), .p2_dest_in(p2_dest_in), .p2_ready_out(g_p2_ready_out),

        .p0_data_out(g_p0_data_out), .p0_valid_out(g_p0_valid_out), .p0_ready_ext(p0_ready_ext),
        .p1_data_out(g_p1_data_out), .p1_valid_out(g_p1_valid_out), .p1_ready_ext(p1_ready_ext),
        .p2_data_out(g_p2_data_out), .p2_valid_out(g_p2_valid_out), .p2_ready_ext(p2_ready_ext)
    );

    // ============================================================
    // 3. Instantiate Revised Top Level (Contains AI modified sub-module)
    // ============================================================
    wire        r_p0_ready_out, r_p1_ready_out, r_p2_ready_out;
    wire [63:0] r_p0_data_out,  r_p1_data_out,  r_p2_data_out;
    wire        r_p0_valid_out, r_p1_valid_out, r_p2_valid_out;

    revised u_revised (
        .clk_in_0(clk_in_0), .rst_n_in_0(rst_n_in_0),
        .clk_in_1(clk_in_1), .rst_n_in_1(rst_n_in_1),
        .clk_in_2(clk_in_2), .rst_n_in_2(rst_n_in_2),
        .clk_out_0(clk_out_0), .rst_n_out_0(rst_n_out_0),
        .clk_out_1(clk_out_1), .rst_n_out_1(rst_n_out_1),
        .clk_out_2(clk_out_2), .rst_n_out_2(rst_n_out_2),

        .p0_data_in(p0_data_in), .p0_valid_in(p0_valid_in), .p0_dest_in(p0_dest_in), .p0_ready_out(r_p0_ready_out),
        .p1_data_in(p1_data_in), .p1_valid_in(p1_valid_in), .p1_dest_in(p1_dest_in), .p1_ready_out(r_p1_ready_out),
        .p2_data_in(p2_data_in), .p2_valid_in(p2_valid_in), .p2_dest_in(p2_dest_in), .p2_ready_out(r_p2_ready_out),

        .p0_data_out(r_p0_data_out), .p0_valid_out(r_p0_valid_out), .p0_ready_ext(p0_ready_ext),
        .p1_data_out(r_p1_data_out), .p1_valid_out(r_p1_valid_out), .p1_ready_ext(p1_ready_ext),
        .p2_data_out(r_p2_data_out), .p2_valid_out(r_p2_valid_out), .p2_ready_ext(p2_ready_ext)
    );

// ============================================================
// 4. The 12-Cycle Delay Line (Flat Shift Registers)
// ============================================================
// By using flat vectors instead of arrays, we bypass Yosys buffer bugs.
// 12 cycles * 64 bits = 768 bits.

reg [767:0] g_p0_data_pipe;
reg [11:0]  g_p0_valid_pipe;
always @(posedge clk_out_0) begin
    if (!rst_n_out_0) begin
        g_p0_data_pipe  <= 768'b0;
        g_p0_valid_pipe <= 12'b0;
    end else begin
        g_p0_data_pipe  <= {g_p0_data_pipe[703:0], g_p0_data_out};
        g_p0_valid_pipe <= {g_p0_valid_pipe[10:0], g_p0_valid_out};
    end
end

reg [767:0] g_p1_data_pipe;
reg [11:0]  g_p1_valid_pipe;
always @(posedge clk_out_1) begin
    if (!rst_n_out_1) begin
        g_p1_data_pipe  <= 768'b0;
        g_p1_valid_pipe <= 12'b0;
    end else begin
        g_p1_data_pipe  <= {g_p1_data_pipe[703:0], g_p1_data_out};
        g_p1_valid_pipe <= {g_p1_valid_pipe[10:0], g_p1_valid_out};
    end
end

reg [767:0] g_p2_data_pipe;
reg [11:0]  g_p2_valid_pipe;
always @(posedge clk_out_2) begin
    if (!rst_n_out_2) begin
        g_p2_data_pipe  <= 768'b0;
        g_p2_valid_pipe <= 12'b0;
    end else begin
        g_p2_data_pipe  <= {g_p2_data_pipe[703:0], g_p2_data_out};
        g_p2_valid_pipe <= {g_p2_valid_pipe[10:0], g_p2_valid_out};
    end
end

// ============================================================
// 5. Formal Assertions
// ============================================================

//always @(posedge clk_in_0) if (f_past_valid && rst_n_in_0) assert(g_p0_ready_out == r_p0_ready_out);
//always @(posedge clk_in_1) if (f_past_valid && rst_n_in_1) assert(g_p1_ready_out == r_p1_ready_out);
//always @(posedge clk_in_2) if (f_past_valid && rst_n_in_2) assert(g_p2_ready_out == r_p2_ready_out);

// The oldest data is now at the top bits of the flat register
always @(posedge clk_out_0) begin
    if (f_past_valid && rst_n_out_0) begin
        assert(g_p0_valid_pipe[11] == r_p0_valid_out);
        if (r_p0_valid_out) assert(g_p0_data_pipe[767:704] == r_p0_data_out);
    end
end

always @(posedge clk_out_1) begin
    if (f_past_valid && rst_n_out_1) begin
        assert(g_p1_valid_pipe[11] == r_p1_valid_out);
        if (r_p1_valid_out) assert(g_p1_data_pipe[767:704] == r_p1_data_out);
    end
end

always @(posedge clk_out_2) begin
    if (f_past_valid && rst_n_out_2) begin
        assert(g_p2_valid_pipe[11] == r_p2_valid_out);
        if (r_p2_valid_out) assert(g_p2_data_pipe[767:704] == r_p2_data_out);
    end
end

endmodule