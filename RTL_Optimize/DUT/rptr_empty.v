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

    reg  [ADDRSIZE:0]   rbin;
    reg  [ADDRSIZE-1:0] raddr_reg;
    wire [ADDRSIZE:0]   rgraynext, rbinnext;
    wire                rempty_val;

    // Dual n-bit Gray code counter with isolated memory address register
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin      <= {(ADDRSIZE+1){1'b0}};
            rptr      <= {(ADDRSIZE+1){1'b0}};
            raddr_reg <= {ADDRSIZE{1'b0}};
        end 
        else begin
            rbin      <= rbinnext;
            rptr      <= rgraynext;
            raddr_reg <= rbinnext[ADDRSIZE-1:0];
        end
    end

    // Direct register output for memory address to isolate fanout/logic load
    assign raddr = raddr_reg;

    // Conditional binary increment
    assign rbinnext = rbin + (rinc & ~rempty);

    // Combinational Binary-to-Gray conversion
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;

    // FIFO Empty Logic
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