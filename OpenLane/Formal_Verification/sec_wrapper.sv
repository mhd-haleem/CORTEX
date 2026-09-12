module sec_wrapper (
  input clk_out,
  input rst_n,
  input empty_0, empty_1, empty_2,
  input [63:0] rdata_0, rdata_1, rdata_2,
  input ready_ext
);

  // ----------------------------------------------------
  // Formal Reset Sequence Handling
  // ----------------------------------------------------
  reg f_past_valid = 0;
  always @(posedge clk_out) begin
    f_past_valid <= 1;
    // Force the solver to assert reset on the very first cycle
    if (!f_past_valid) begin
      assume(!rst_n);
    end
  end

  // ----------------------------------------------------
  // Golden Outputs (Combinational)
  // ----------------------------------------------------
  wire g_rinc_0, g_rinc_1, g_rinc_2;
  wire [63:0] g_data_out;
  wire g_valid_out;

  gold u_gold (
    .clk_out(clk_out), .rst_n(rst_n),
    .empty_0(empty_0), .empty_1(empty_1), .empty_2(empty_2),
    .rdata_0(rdata_0), .rdata_1(rdata_1), .rdata_2(rdata_2),
    .ready_ext(ready_ext),
    .rinc_0(g_rinc_0), .rinc_1(g_rinc_1), .rinc_2(g_rinc_2),
    .data_out(g_data_out), .valid_out(g_valid_out)
  );

  // ----------------------------------------------------
  // Revised Outputs (12-Stage Pipelined)
  // ----------------------------------------------------
  wire r_rinc_0, r_rinc_1, r_rinc_2;
  wire [63:0] r_data_out;
  wire r_valid_out;

  revised u_revised (
    .clk_out(clk_out), .rst_n(rst_n),
    .empty_0(empty_0), .empty_1(empty_1), .empty_2(empty_2),
    .rdata_0(rdata_0), .rdata_1(rdata_1), .rdata_2(rdata_2),
    .ready_ext(ready_ext),
    .rinc_0(r_rinc_0), .rinc_1(r_rinc_1), .rinc_2(r_rinc_2),
    .data_out(r_data_out), .valid_out(r_valid_out)
  );

  // ----------------------------------------------------
  // The Latency Compensator (12-cycle delay for Golden)
  // ----------------------------------------------------
  reg [63:0] g_data_out_pipe [0:11];
  reg g_valid_out_pipe [0:11];
  
  integer i;
  always @(posedge clk_out) begin
    if (!rst_n) begin
      for (i = 0; i < 12; i = i + 1) begin
        g_data_out_pipe[i] <= 64'b0;
        g_valid_out_pipe[i] <= 1'b0;
      end
    end else begin
      g_data_out_pipe[0] <= g_data_out;
      g_valid_out_pipe[0] <= g_valid_out;
      for (i = 1; i < 12; i = i + 1) begin
        g_data_out_pipe[i] <= g_data_out_pipe[i-1];
        g_valid_out_pipe[i] <= g_valid_out_pipe[i-1];
      end
    end
  end

  // ----------------------------------------------------
  // Formal Assertions
  // ----------------------------------------------------
  always @(posedge clk_out) begin
    // Only check assertions AFTER the reset cycle has passed
    if (f_past_valid && rst_n) begin
      
      // 1. Control signals (rinc) update immediately, so they must match exactly
      assert(g_rinc_0 == r_rinc_0);
      assert(g_rinc_1 == r_rinc_1);
      assert(g_rinc_2 == r_rinc_2);

      // 2. The valid signal must match after a 12-cycle delay
      assert(g_valid_out_pipe[11] == r_valid_out);
      
      // 3. When valid goes high, the data payload MUST match the delayed golden payload
      if (r_valid_out) begin
        assert(g_data_out_pipe[11] == r_data_out);
      end
    end
  end

endmodule