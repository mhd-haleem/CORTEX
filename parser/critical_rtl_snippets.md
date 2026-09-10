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

### Location: `/openlane/designs/my_design/src/top_fifo.v:81-89`
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

### Location: `/openlane/designs/my_design/src/output_port_3by3.v:80-95`
```verilog
        stage4 <= 64'h0;
        stage5 <= 64'h0;
        stage6 <= 64'h0;
        stage7 <= 64'h0;
        stage8 <= 64'h0;
        stage9 <= 64'h0;
        stage10 <= 64'h0;
        stage11 <= 64'h0;
        processed_comb <= 64'h0;
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
```

---

