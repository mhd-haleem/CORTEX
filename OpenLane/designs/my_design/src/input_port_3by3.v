`timescale 1ns / 1ps

module input_port_3by3 #(
    parameter DATA_WIDTH = 4
)(
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  valid_in,
    input  wire [1:0]            dest_in,   // 2'b00: Out0, 2'b01: Out1, 2'b10: Out2
    output wire                  ready_out, // Backpressure to source

    // Crosspoint FIFO Write Interfaces
    output reg                   winc_0,
    output reg                   winc_1,
    output reg                   winc_2,
    output wire [DATA_WIDTH-1:0] wdata,
    input  wire                  wfull_0,
    input  wire                  wfull_1,
    input  wire                  wfull_2
);
    assign wdata = data_in;

    always @(*) begin
        winc_0 = 1'b0;
        winc_1 = 1'b0;
        winc_2 = 1'b0;
        if (valid_in) begin
            case (dest_in)
                2'b00:   winc_0 = !wfull_0;
                2'b01:   winc_1 = !wfull_1;
                2'b10:   winc_2 = !wfull_2;
                default: ;
            endcase
        end
    end

    // Backpressure if the selected target queue is full
    assign ready_out = (dest_in == 2'b00) ? !wfull_0 :
                       (dest_in == 2'b01) ? !wfull_1 :
                       (dest_in == 2'b10) ? !wfull_2 : 1'b0;

endmodule