module output_port_3by3 #
(
  parameter DATA_WIDTH = 64
)
(
  input wire clk_out,
  input wire rst_n,
  input wire empty_0,
  input wire empty_1,
  input wire empty_2,
  input wire [DATA_WIDTH-1:0] rdata_0,
  input wire [DATA_WIDTH-1:0] rdata_1,
  input wire [DATA_WIDTH-1:0] rdata_2,
  output reg rinc_0,
  output reg rinc_1,
  output reg rinc_2,
  output reg [DATA_WIDTH-1:0] data_out,
  output reg valid_out,
  input wire ready_ext
);

  reg [1:0] ptr;
  reg [2:0] grant;
  wire [2:0] req;
  
  assign req = { !empty_2, !empty_1, !empty_0 };

  always @(*) begin
    grant = 3'b000;
    rinc_0 = 1'b0;
    rinc_1 = 1'b0;
    rinc_2 = 1'b0;
    if(ready_ext) begin
      case(ptr)
        2'd0: begin
          if(req[0]) grant = 3'b001; 
          else if(req[1]) grant = 3'b010; 
          else if(req[2]) grant = 3'b100; 
        end
        2'd1: begin
          if(req[1]) grant = 3'b010; 
          else if(req[2]) grant = 3'b100; 
          else if(req[0]) grant = 3'b001; 
        end
        2'd2: begin
          if(req[2]) grant = 3'b100; 
          else if(req[0]) grant = 3'b001; 
          else if(req[1]) grant = 3'b010; 
        end
        default: grant = 3'b000;
      endcase
    end 
    rinc_0 = grant[0];
    rinc_1 = grant[1];
    rinc_2 = grant[2];
  end

  wire [DATA_WIDTH-1:0] selected_data;
  assign selected_data = (grant[0])? rdata_0 : 
                         (grant[1])? rdata_1 : 
                         (grant[2])? rdata_2 : { DATA_WIDTH{ 1'b0 } };

  // ---------------------------------------------------------
  // FIXED: Explicitly declare the pipeline stage registers
  // ---------------------------------------------------------
  reg [DATA_WIDTH-1:0] stage1;
  reg [DATA_WIDTH-1:0] stage2;
  reg [DATA_WIDTH-1:0] stage3;
  reg [DATA_WIDTH-1:0] stage4;
  reg [DATA_WIDTH-1:0] stage5;
  reg [DATA_WIDTH-1:0] stage6;
  reg [DATA_WIDTH-1:0] stage7;
  reg [DATA_WIDTH-1:0] stage8;
  reg [DATA_WIDTH-1:0] stage9;
  reg [DATA_WIDTH-1:0] stage10;
  reg [DATA_WIDTH-1:0] stage11;
  reg [DATA_WIDTH-1:0] processed_comb;

  // FIXED: 12-stage shift register to preserve data/valid alignment
  reg [11:0] valid_pipe;

  always @(posedge clk_out or negedge rst_n) begin
    if(!rst_n) begin
      stage1 <= 64'h0;
      stage2 <= 64'h0;
      stage3 <= 64'h0;
      stage4 <= 64'h0;
      stage5 <= 64'h0;
      stage6 <= 64'h0;
      stage7 <= 64'h0;
      stage8 <= 64'h0;
      stage9 <= 64'h0;
      stage10 <= 64'h0;
      stage11 <= 64'h0;
      processed_comb <= 64'h0;
      valid_pipe <= 12'b0;
    end else begin
      stage1 <= (selected_data ^ (selected_data << 3)) + 64'hA5A5A5A5_5A5A5A5A;
      stage2 <= (stage1 ^ (stage1 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd7);
      stage3 <= (stage2 ^ (stage2 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd14);
      stage4 <= (stage3 ^ (stage3 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd21);
      stage5 <= (stage4 ^ (stage4 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd28);
      stage6 <= (stage5 ^ (stage5 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd35);
      stage7 <= (stage6 ^ (stage6 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd42);
      stage8 <= (stage7 ^ (stage7 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd49);
      stage9 <= (stage8 ^ (stage8 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd56);
      stage10 <= (stage9 ^ (stage9 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd63);
      stage11 <= (stage10 ^ (stage10 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd70);
      processed_comb <= (stage11 ^ (stage11 << 3)) + (64'hA5A5A5A5_5A5A5A5A + 64'd77);
      
      // Shift in the current grant state to track validity through the 12 pipeline stages
      valid_pipe <= {valid_pipe[10:0], |grant};
    end
  end

  always @(posedge clk_out or negedge rst_n) begin
    if(!rst_n) begin
      data_out <= { DATA_WIDTH{ 1'b0 } };
      valid_out <= 1'b0;
      ptr <= 2'd0;
    end else begin
      // FIXED: Output the valid signal only after 12 cycles
      valid_out <= valid_pipe[11];
      
      // FIXED: Output the data synchronously with the delayed valid signal
      if(valid_pipe[11]) begin
        data_out <= processed_comb;
      end
      
      // FIXED: Arbitration pointer must update IMMEDIATELY, decoupled from the data pipeline delay
      if(|grant) begin
        if(grant[0]) ptr <= 2'd1; 
        else if(grant[1]) ptr <= 2'd2; 
        else if(grant[2]) ptr <= 2'd0; 
      end 
    end
  end

endmodule