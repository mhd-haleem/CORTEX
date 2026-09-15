# Critical RTL Snippets

> *Note: Exact behavioral blocks extracted from timing bottleneck paths.*

### Location: `/openlane/designs/my_design/src/xbar_3by3_bencmark_top.v:124-136`
```verilog
                top_fifo #(
                    .DSIZE(DATA_WIDTH),
                    .ASIZE(ADDR_WIDTH)
                ) FIFO_CROSSPOINT (
                    .wclk   (fifo_wclk),
                    .wrst_n (fifo_wrst),
                    .winc   (winc[in_idx][out_idx]),
                    .wdata  (wdata_bus[in_idx]),
                    .wfull  (wfull[in_idx][out_idx]),

                    .rclk   (fifo_rclk),
                    .rrst_n (fifo_rrst),
                    .rinc   (rinc[out_idx][in_idx]),
                    .rdata  (rdata_bus[out_idx][in_idx]),
                    .rempty (rempty[out_idx][in_idx])
                );
            end
        end
    endgenerate
```

---

### Location: `/openlane/designs/my_design/src/rptr_empty.v:22-29`
```verilog
    
    // Dual n-bit Gray code counter (Style #2)
    
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            {rbin, rptr} <= {(2*(ADDRSIZE+1)){1'b0}};
        end 
        else begin
            {rbin, rptr} <= {rbinnext, rgraynext};
        end
    end

    // Memory read-address pointer (binary is safe to use for memory)
    assign raddr = rbin[ADDRSIZE-1:0];
```

---

### Location: `/openlane/designs/my_design/src/top_fifo.v:86-94`
```verilog
    
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

endmodule```

---

### Location: `/openlane/designs/my_design/src/xbar_3by3_bencmark_top.v:160-166`
```verilog
        .data_out(p1_data_out), .valid_out(p1_valid_out), .ready_ext(p1_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_2 (
        .clk_out(clk_out_2), .rst_n(rst_n_out_2),
        .empty_0(rempty[2][0]), .empty_1(rempty[2][1]), .empty_2(rempty[2][2]),
        .rdata_0(rdata_bus[2][0]), .rdata_1(rdata_bus[2][1]), .rdata_2(rdata_bus[2][2]),
        .rinc_0(rinc[2][0]), .rinc_1(rinc[2][1]), .rinc_2(rinc[2][2]),
        .data_out(p2_data_out), .valid_out(p2_valid_out), .ready_ext(p2_ready_ext)
    );

endmodule```

---

### Location: `/openlane/designs/my_design/src/output_port_3by3.v:83-101`
```verilog
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
endmodule```

---

### Location: `/openlane/designs/my_design/src/xbar_3by3_bencmark_top.v:144-150`
```verilog
    // ============================================================
    // 5. OUTPUT PORTS & ARBITERS
    // ============================================================
    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_0 (
        .clk_out(clk_out_0), .rst_n(rst_n_out_0),
        .empty_0(rempty[0][0]), .empty_1(rempty[0][1]), .empty_2(rempty[0][2]),
        .rdata_0(rdata_bus[0][0]), .rdata_1(rdata_bus[0][1]), .rdata_2(rdata_bus[0][2]),
        .rinc_0(rinc[0][0]), .rinc_1(rinc[0][1]), .rinc_2(rinc[0][2]),
        .data_out(p0_data_out), .valid_out(p0_valid_out), .ready_ext(p0_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_1 (
        .clk_out(clk_out_1), .rst_n(rst_n_out_1),
```

---

### Location: `/openlane/designs/my_design/src/xbar_3by3_bencmark_top.v:152-158`
```verilog
        .data_out(p0_data_out), .valid_out(p0_valid_out), .ready_ext(p0_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_1 (
        .clk_out(clk_out_1), .rst_n(rst_n_out_1),
        .empty_0(rempty[1][0]), .empty_1(rempty[1][1]), .empty_2(rempty[1][2]),
        .rdata_0(rdata_bus[1][0]), .rdata_1(rdata_bus[1][1]), .rdata_2(rdata_bus[1][2]),
        .rinc_0(rinc[1][0]), .rinc_1(rinc[1][1]), .rinc_2(rinc[1][2]),
        .data_out(p1_data_out), .valid_out(p1_valid_out), .ready_ext(p1_ready_ext)
    );

    output_port_3by3 #(.DATA_WIDTH(DATA_WIDTH)) OUT_PORT_2 (
        .clk_out(clk_out_2), .rst_n(rst_n_out_2),
```

---

