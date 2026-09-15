// ==========================================
// BOTTLENECK LEAF MODULE - OPTIMIZED
// Original File: /home/basith/CORTEX/OpenLane/designs/my_design/src/output_port_3by3.v
// ==========================================

module output_port_3by3 #(
    parameter DATA_WIDTH = 64
)(
    input  wire                  clk_out,
    input  wire                  rst_n,

    // FIFO Read Interfaces
    input  wire                  empty_0,
    input  wire                  empty_1,
    input  wire                  empty_2,
    input  wire [DATA_WIDTH-1:0] rdata_0,
    input  wire [DATA_WIDTH-1:0] rdata_1,
    input  wire [DATA_WIDTH-1:0] rdata_2,
    output reg                   rinc_0,
    output reg                   rinc_1,
    output reg                   rinc_2,

    // External Interface
    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   valid_out,
    input  wire                  ready_ext
);
    // 3-way Round Robin Arbiter
    reg [1:0] ptr;
    reg [2:0] grant;
    wire [2:0] req = {!empty_2, !empty_1, !empty_0};

    always @(*) begin
        grant  = 3'b000;
        rinc_0 = 1'b0;
        rinc_1 = 1'b0;
        rinc_2 = 1'b0;

        if (ready_ext) begin
            case (ptr)
                2'd0: begin
                    if      (req[0]) grant = 3'b001;
                    else if (req[1]) grant = 3'b010;
                    else if (req[2]) grant = 3'b100;
                end
                2'd1: begin
                    if      (req[1]) grant = 3'b010;
                    else if (req[2]) grant = 3'b100;
                    else if (req[0]) grant = 3'b001;
                end
                2'd2: begin
                    if      (req[2]) grant = 3'b100;
                    else if (req[0]) grant = 3'b001;
                    else if (req[1]) grant = 3'b010;
                end
                default: grant = 3'b000;
            endcase
        end

        rinc_0 = grant[0];
        rinc_1 = grant[1];
        rinc_2 = grant[2];
    end

    // Selected payload
    wire [DATA_WIDTH-1:0] selected_data = grant[0] ? rdata_0 :
                                          grant[1] ? rdata_1 :
                                          grant[2] ? rdata_2 : {DATA_WIDTH{1'b0}};

    // --- PIPELINED CRITICAL PATH BLOCK ---
    // Deep multi-stage cascaded combinational arithmetic chain split into 3 pipeline stages
    // to eliminate critical path timing violations.
    reg [DATA_WIDTH-1:0] p1_data;
    reg                  p1_valid;
    reg [DATA_WIDTH-1:0] p2_data;
    reg                  p2_valid;

    // Stage 1 combinational logic (steps 0 to 3)
    reg [DATA_WIDTH-1:0] stage1_comb;
    integer s1;
    always @(*) begin
        stage1_comb = selected_data;
        for (s1 = 0; s1 < 4; s1 = s1 + 1) begin
            stage1_comb = (stage1_comb ^ (stage1_comb << 3)) + 64'hA5A5A5A5_5A5A5A5A + (s1 * 7);
        end
    end

    // Stage 2 combinational logic (steps 4 to 7)
    reg [DATA_WIDTH-1:0] stage2_comb;
    integer s2;
    always @(*) begin
        stage2_comb = p1_data;
        for (s2 = 4; s2 < 8; s2 = s2 + 1) begin
            stage2_comb = (stage2_comb ^ (stage2_comb << 3)) + 64'hA5A5A5A5_5A5A5A5A + (s2 * 7);
        end
    end

    // Stage 3 combinational logic (steps 8 to 11)
    reg [DATA_WIDTH-1:0] stage3_comb;
    integer s3;
    always @(*) begin
        stage3_comb = p2_data;
        for (s3 = 8; s3 < 12; s3 = s3 + 1) begin
            stage3_comb = (stage3_comb ^ (stage3_comb << 3)) + 64'hA5A5A5A5_5A5A5A5A + (s3 * 7);
        end
    end

    // Pipeline Registers & Output Registering
    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            p1_data   <= {DATA_WIDTH{1'b0}};
            p1_valid  <= 1'b0;
            p2_data   <= {DATA_WIDTH{1'b0}};
            p2_valid  <= 1'b0;
            data_out  <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
            ptr       <= 2'd0;
        end else begin
            // Stage 1
            p1_valid <= |grant;
            if (|grant) begin
                p1_data <= stage1_comb;
                // Move Round-Robin Pointer
                if      (grant[0]) ptr <= 2'd1;
                else if (grant[1]) ptr <= 2'd2;
                else if (grant[2]) ptr <= 2'd0;
            end

            // Stage 2
            p2_valid <= p1_valid;
            if (p1_valid) begin
                p2_data <= stage2_comb;
            end

            // Stage 3 (Output Stage)
            valid_out <= p2_valid;
            if (p2_valid) begin
                data_out <= stage3_comb;
            end
        end
    end
endmodule