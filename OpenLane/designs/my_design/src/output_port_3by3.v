`timescale 1ns / 1ps

module output_port_3by3 #(
    parameter DATA_WIDTH = 4
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

    // --- CRITICAL PATH INJECTION BLOCK ---
    // Deep multi-stage cascaded combinational arithmetic chain.
    reg [DATA_WIDTH-1:0] processed_comb;
    integer step;
    always @(*) begin
        processed_comb = selected_data;
        for (step = 0; step < 25; step = step + 1) begin
            // Data-dependent branching prevents synthesis from collapsing the loop.
            // Using unsized integers prevents width mismatch warnings if DATA_WIDTH scales up.
            if (processed_comb[3:0] > 4'd7)
                processed_comb = processed_comb - 5;
            else
                processed_comb = processed_comb + 3;
        end
    end

    // Output Registers
    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
            ptr       <= 2'd0;
        end else begin
            valid_out <= |grant;
            if (|grant) begin
                data_out <= processed_comb;
                // Move Round-Robin Pointer
                if      (grant[0]) ptr <= 2'd1;
                else if (grant[1]) ptr <= 2'd2;
                else if (grant[2]) ptr <= 2'd0;
            end else if (ptr > 2'd2) begin
                // SEU / Invalid State Recovery
                ptr <= 2'd0;
            end
        end
    end
endmodule
