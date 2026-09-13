module axi_full_slave #(
    parameter integer C_S_AXI_ID_WIDTH    = 4,
    parameter integer C_S_AXI_DATA_WIDTH  = 32,
    parameter integer C_S_AXI_ADDR_WIDTH  = 32
)(
    // System Signals
    input  wire                            S_AXI_ACLK,
    input  wire                            S_AXI_ARESETN,

    // Write Address Channel
    input  wire [C_S_AXI_ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [7:0]                      S_AXI_AWLEN,
    input  wire [2:0]                      S_AXI_AWSIZE,
    input  wire [1:0]                      S_AXI_AWBURST,
    input  wire                            S_AXI_AWLOCK,
    input  wire [3:0]                      S_AXI_AWCACHE,
    input  wire [2:0]                      S_AXI_AWPROT,
    input  wire [3:0]                      S_AXI_AWQOS,
    input  wire                            S_AXI_AWVALID,
    output reg                             S_AXI_AWREADY,

    // Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                            S_AXI_WLAST,
    input  wire                            S_AXI_WVALID,
    output reg                             S_AXI_WREADY,

    // Write Response Channel
    output reg  [C_S_AXI_ID_WIDTH-1:0]     S_AXI_BID,
    output reg  [1:0]                      S_AXI_BRESP,
    output reg                             S_AXI_BVALID,
    input  wire                            S_AXI_BREADY,

    // Read Address Channel
    input  wire [C_S_AXI_ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [7:0]                      S_AXI_ARLEN,
    input  wire [2:0]                      S_AXI_ARSIZE,
    input  wire [1:0]                      S_AXI_ARBURST,
    input  wire                            S_AXI_ARLOCK,
    input  wire [3:0]                      S_AXI_ARCACHE,
    input  wire [2:0]                      S_AXI_ARPROT,
    input  wire [3:0]                      S_AXI_ARQOS,
    input  wire                            S_AXI_ARVALID,
    output reg                             S_AXI_ARREADY,

    // Read Data Channel
    output reg  [C_S_AXI_ID_WIDTH-1:0]     S_AXI_RID,
    output reg  [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output reg  [1:0]                      S_AXI_RRESP,
    output reg                             S_AXI_RLAST,
    output reg                             S_AXI_RVALID,
    input  wire                            S_AXI_RREADY
);

    // Address LSBs for word alignment (32-bit data width = 4 bytes per word -> 2 LSBs)
    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer MEM_ADDR_BITS = 8; // 256 depth RAM

    // Internal Memory (256 x 32-bit words)
    reg [C_S_AXI_DATA_WIDTH-1:0] mem [0:(1<<MEM_ADDR_BITS)-1];

    // Internal Control Registers
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg [1:0]                    axi_awburst;
    reg                          axi_awv_arr_flag;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg [1:0]                    axi_arburst;
    reg [7:0]                    axi_arlen;
    reg [7:0]                    axi_arlen_cntr;
    reg                          axi_arv_arr_flag;

    integer byte_index;

    //------------------------------------------------
    // Write Address Channel Logic
    //------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY    <= 1'b0;
            axi_awv_arr_flag <= 1'b0;
            axi_awaddr       <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            axi_awburst      <= 2'b0;
            S_AXI_BID        <= {C_S_AXI_ID_WIDTH{1'b0}};
        end else begin
            if (!S_AXI_AWREADY && S_AXI_AWVALID && !axi_awv_arr_flag && !axi_arv_arr_flag) begin
                S_AXI_AWREADY    <= 1'b1;
                axi_awv_arr_flag <= 1'b1;
                axi_awaddr       <= S_AXI_AWADDR;
                axi_awburst      <= S_AXI_AWBURST;
                S_AXI_BID        <= S_AXI_AWID;
            end else begin
                S_AXI_AWREADY <= 1'b0;
                if (S_AXI_WVALID && S_AXI_WREADY && S_AXI_WLAST) begin
                    axi_awv_arr_flag <= 1'b0;
                end
            end
        end
    end

    //------------------------------------------------
    // Write Data & Strobes Logic
    //------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_WREADY <= 1'b0;
        end else begin
            if (!S_AXI_WREADY && S_AXI_WVALID && axi_awv_arr_flag) begin
                S_AXI_WREADY <= 1'b1;
            end else begin
                S_AXI_WREADY <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_WREADY && S_AXI_WVALID) begin
            for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1) begin
                if (S_AXI_WSTRB[byte_index]) begin
                    mem[axi_awaddr[MEM_ADDR_BITS+ADDR_LSB-1:ADDR_LSB]][(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                end
            end

            // Address Incrementing
            case (axi_awburst)
                2'b00: axi_awaddr <= axi_awaddr; // FIXED burst
                2'b01: axi_awaddr <= axi_awaddr + (1 << ADDR_LSB); // INCR burst
                default: axi_awaddr <= axi_awaddr + (1 << ADDR_LSB);
            endcase
        end
    end

    //------------------------------------------------
    // Write Response Channel Logic
    //------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_BVALID <= 1'b0;
            S_AXI_BRESP  <= 2'b00; // OKAY
        end else begin
            if (axi_awv_arr_flag && S_AXI_WVALID && S_AXI_WREADY && S_AXI_WLAST && !S_AXI_BVALID) begin
                S_AXI_BVALID <= 1'b1;
                S_AXI_BRESP  <= 2'b00;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    //------------------------------------------------
    // Read Address Channel Logic
    //------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY    <= 1'b0;
            axi_arv_arr_flag <= 1'b0;
            axi_araddr       <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            axi_arlen        <= 8'b0;
            axi_arburst      <= 2'b0;
            S_AXI_RID        <= {C_S_AXI_ID_WIDTH{1'b0}};
        end else begin
            if (!S_AXI_ARREADY && S_AXI_ARVALID && !axi_arv_arr_flag && !axi_awv_arr_flag) begin
                S_AXI_ARREADY    <= 1'b1;
                axi_arv_arr_flag <= 1'b1;
                axi_araddr       <= S_AXI_ARADDR;
                axi_arlen        <= S_AXI_ARLEN;
                axi_arburst      <= S_AXI_ARBURST;
                S_AXI_RID        <= S_AXI_ARID;
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end
        end
    end

    //------------------------------------------------
    // Read Data & Response Generation Logic
    //------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID   <= 1'b0;
            S_AXI_RLAST    <= 1'b0;
            S_AXI_RRESP    <= 2'b00;
            S_AXI_RDATA    <= {C_S_AXI_DATA_WIDTH{1'b0}};
            axi_arlen_cntr <= 8'b0;
        end else begin
            if (axi_arv_arr_flag && !S_AXI_RVALID) begin
                S_AXI_RVALID   <= 1'b1;
                S_AXI_RDATA    <= mem[axi_araddr[MEM_ADDR_BITS+ADDR_LSB-1:ADDR_LSB]];
                S_AXI_RRESP    <= 2'b00; // OKAY
                S_AXI_RLAST    <= (axi_arlen_cntr == axi_arlen);
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                if (axi_arlen_cntr == axi_arlen) begin
                    S_AXI_RVALID     <= 1'b0;
                    S_AXI_RLAST      <= 1'b0;
                    axi_arv_arr_flag <= 1'b0;
                    axi_arlen_cntr   <= 8'b0;
                end else begin
                    axi_arlen_cntr <= axi_arlen_cntr + 1'b1;
                    S_AXI_RLAST    <= ((axi_arlen_cntr + 1'b1) == axi_arlen);
                    
                    case (axi_arburst)
                        2'b00: begin
                            axi_araddr  <= axi_araddr;
                            S_AXI_RDATA <= mem[axi_araddr[MEM_ADDR_BITS+ADDR_LSB-1:ADDR_LSB]];
                        end
                        2'b01: begin
                            axi_araddr  <= axi_araddr + (1 << ADDR_LSB);
                            S_AXI_RDATA <= mem[(axi_araddr + (1 << ADDR_LSB)) >> ADDR_LSB];
                        end
                        default: begin
                            axi_araddr  <= axi_araddr + (1 << ADDR_LSB);
                            S_AXI_RDATA <= mem[(axi_araddr + (1 << ADDR_LSB)) >> ADDR_LSB];
                        end
                    endcase
                end
            end
        end
    end

endmodule