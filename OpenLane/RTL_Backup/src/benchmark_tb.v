`timescale 1ns / 1ps

module tb_xbar_3by3_benchmark;

    // ============================================================
    // 1. PARAMETERS & SIGNALS
    // ============================================================
    parameter DATA_WIDTH = 64;

    // 6 Master Clocks
    reg clk_in_0, clk_in_1, clk_in_2;
    reg clk_out_0, clk_out_1, clk_out_2;

    // 6 Resets
    reg rst_n_in_0, rst_n_in_1, rst_n_in_2;
    reg rst_n_out_0, rst_n_out_1, rst_n_out_2;

    // Generated Clocks (Outputs from DUT)
    wire gen_clk_in0_div2, gen_clk_in1_div4, gen_clk_out0_div8;

    // Input Port Signals
    reg  [DATA_WIDTH-1:0] p0_data_in, p1_data_in, p2_data_in;
    reg                   p0_valid_in, p1_valid_in, p2_valid_in;
    reg  [1:0]            p0_dest_in, p1_dest_in, p2_dest_in;
    wire                  p0_ready_out, p1_ready_out, p2_ready_out;

    // Output Port Signals
    wire [DATA_WIDTH-1:0] p0_data_out, p1_data_out, p2_data_out;
    wire                  p0_valid_out, p1_valid_out, p2_valid_out;
    reg                   p0_ready_ext, p1_ready_ext, p2_ready_ext;

    // ============================================================
    // 2. CLOCK GENERATION (6 Asynchronous Domains)
    // ============================================================
    // Slightly offset frequencies to mimic independent oscillators
    initial begin clk_in_0 = 0;  forever #4.0 clk_in_0  = ~clk_in_0;  end // 125 MHz
    initial begin clk_in_1 = 0;  forever #5.0 clk_in_1  = ~clk_in_1;  end // 100 MHz
    initial begin clk_in_2 = 0;  forever #6.0 clk_in_2  = ~clk_in_2;  end // ~83 MHz
    initial begin clk_out_0 = 0; forever #3.5 clk_out_0 = ~clk_out_0; end // ~142 MHz
    initial begin clk_out_1 = 0; forever #4.5 clk_out_1 = ~clk_out_1; end // ~111 MHz
    initial begin clk_out_2 = 0; forever #5.5 clk_out_2 = ~clk_out_2; end // ~90 MHz

    // ============================================================
    // 3. DUT INSTANTIATION
    // ============================================================
    xbar_3by3_benchmark_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(5) // Depth = 32
    ) DUT (
        .clk_in_0(clk_in_0), .rst_n_in_0(rst_n_in_0),
        .clk_in_1(clk_in_1), .rst_n_in_1(rst_n_in_1),
        .clk_in_2(clk_in_2), .rst_n_in_2(rst_n_in_2),
        .clk_out_0(clk_out_0), .rst_n_out_0(rst_n_out_0),
        .clk_out_1(clk_out_1), .rst_n_out_1(rst_n_out_1),
        .clk_out_2(clk_out_2), .rst_n_out_2(rst_n_out_2),

        .gen_clk_in0_div2(gen_clk_in0_div2),
        .gen_clk_in1_div4(gen_clk_in1_div4),
        .gen_clk_out0_div8(gen_clk_out0_div8),

        .p0_data_in(p0_data_in), .p0_valid_in(p0_valid_in), .p0_dest_in(p0_dest_in), .p0_ready_out(p0_ready_out),
        .p1_data_in(p1_data_in), .p1_valid_in(p1_valid_in), .p1_dest_in(p1_dest_in), .p1_ready_out(p1_ready_out),
        .p2_data_in(p2_data_in), .p2_valid_in(p2_valid_in), .p2_dest_in(p2_dest_in), .p2_ready_out(p2_ready_out),

        .p0_data_out(p0_data_out), .p0_valid_out(p0_valid_out), .p0_ready_ext(p0_ready_ext),
        .p1_data_out(p1_data_out), .p1_valid_out(p1_valid_out), .p1_ready_ext(p1_ready_ext),
        .p2_data_out(p2_data_out), .p2_valid_out(p2_valid_out), .p2_ready_ext(p2_ready_ext)
    );

    // ============================================================
    // 4. SCOREBOARD & HASH LOGIC (Out-Of-Order Tolerant)
    // ============================================================
    // Since the DUT modifies the payload, we must replicate its exact hash
    function [DATA_WIDTH-1:0] expected_hash;
        input [DATA_WIDTH-1:0] raw_data;
        integer step;
        begin
            expected_hash = raw_data;
            for (step = 0; step < 12; step = step + 1) begin
                expected_hash = (expected_hash ^ (expected_hash << 3)) + 64'hA5A5A5A5_5A5A5A5A + (step * 7);
            end
        end
    endfunction

    // Arrays to record what was sent
    reg [DATA_WIDTH-1:0] sent_to_0 [0:255];
    reg [DATA_WIDTH-1:0] sent_to_1 [0:255];
    reg [DATA_WIDTH-1:0] sent_to_2 [0:255];

    // Boolean flags indicating if the packet was successfully received
    reg rcvd_from_0 [0:255];
    reg rcvd_from_1 [0:255];
    reg rcvd_from_2 [0:255];

    integer num_sent_0 = 0, num_sent_1 = 0, num_sent_2 = 0;
    integer global_errors = 0;

    // ============================================================
    // 5. STIMULUS TASKS
    // ============================================================
    task send_p0(input [DATA_WIDTH-1:0] data, input [1:0] dest);
        begin
            @(posedge clk_in_0);
            while (!p0_ready_out) @(posedge clk_in_0); // Wait for backpressure to lift
            p0_data_in = data;
            p0_dest_in = dest;
            p0_valid_in = 1;
            
            // Log it in the scoreboard
            if (dest == 0) begin sent_to_0[num_sent_0] = data; rcvd_from_0[num_sent_0] = 0; num_sent_0 = num_sent_0 + 1; end
            if (dest == 1) begin sent_to_1[num_sent_1] = data; rcvd_from_1[num_sent_1] = 0; num_sent_1 = num_sent_1 + 1; end
            if (dest == 2) begin sent_to_2[num_sent_2] = data; rcvd_from_2[num_sent_2] = 0; num_sent_2 = num_sent_2 + 1; end
            
            @(posedge clk_in_0);
            p0_valid_in = 0;
        end
    endtask

    task send_p1(input [DATA_WIDTH-1:0] data, input [1:0] dest);
        begin
            @(posedge clk_in_1);
            while (!p1_ready_out) @(posedge clk_in_1); 
            p1_data_in = data; p1_dest_in = dest; p1_valid_in = 1;
            if (dest == 0) begin sent_to_0[num_sent_0] = data; rcvd_from_0[num_sent_0] = 0; num_sent_0 = num_sent_0 + 1; end
            if (dest == 1) begin sent_to_1[num_sent_1] = data; rcvd_from_1[num_sent_1] = 0; num_sent_1 = num_sent_1 + 1; end
            if (dest == 2) begin sent_to_2[num_sent_2] = data; rcvd_from_2[num_sent_2] = 0; num_sent_2 = num_sent_2 + 1; end
            @(posedge clk_in_1); p1_valid_in = 0;
        end
    endtask

    task send_p2(input [DATA_WIDTH-1:0] data, input [1:0] dest);
        begin
            @(posedge clk_in_2);
            while (!p2_ready_out) @(posedge clk_in_2); 
            p2_data_in = data; p2_dest_in = dest; p2_valid_in = 1;
            if (dest == 0) begin sent_to_0[num_sent_0] = data; rcvd_from_0[num_sent_0] = 0; num_sent_0 = num_sent_0 + 1; end
            if (dest == 1) begin sent_to_1[num_sent_1] = data; rcvd_from_1[num_sent_1] = 0; num_sent_1 = num_sent_1 + 1; end
            if (dest == 2) begin sent_to_2[num_sent_2] = data; rcvd_from_2[num_sent_2] = 0; num_sent_2 = num_sent_2 + 1; end
            @(posedge clk_in_2); p2_valid_in = 0;
        end
    endtask

    // ============================================================
    // 6. OUTPUT MONITORS (Out-Of-Order Checkers)
    // ============================================================
    integer i0, i1, i2;
    reg found0, found1, found2;

    always @(posedge clk_out_0) begin
        if (rst_n_out_0 && p0_valid_out && p0_ready_ext) begin
            found0 = 0;
            for (i0 = 0; i0 < num_sent_0; i0 = i0 + 1) begin
                if (!rcvd_from_0[i0] && (p0_data_out == expected_hash(sent_to_0[i0]))) begin
                    rcvd_from_0[i0] = 1;
                    found0 = 1;
                end
            end
            if (!found0) begin
                $display("[ERROR] Port 0 received unexpected or corrupted packet: %h", p0_data_out);
                global_errors = global_errors + 1;
            end
        end
    end

    always @(posedge clk_out_1) begin
        if (rst_n_out_1 && p1_valid_out && p1_ready_ext) begin
            found1 = 0;
            for (i1 = 0; i1 < num_sent_1; i1 = i1 + 1) begin
                if (!rcvd_from_1[i1] && (p1_data_out == expected_hash(sent_to_1[i1]))) begin
                    rcvd_from_1[i1] = 1;
                    found1 = 1;
                end
            end
            if (!found1) begin
                $display("[ERROR] Port 1 received unexpected or corrupted packet: %h", p1_data_out);
                global_errors = global_errors + 1;
            end
        end
    end

    always @(posedge clk_out_2) begin
        if (rst_n_out_2 && p2_valid_out && p2_ready_ext) begin
            found2 = 0;
            for (i2 = 0; i2 < num_sent_2; i2 = i2 + 1) begin
                if (!rcvd_from_2[i2] && (p2_data_out == expected_hash(sent_to_2[i2]))) begin
                    rcvd_from_2[i2] = 1;
                    found2 = 1;
                end
            end
            if (!found2) begin
                $display("[ERROR] Port 2 received unexpected or corrupted packet: %h", p2_data_out);
                global_errors = global_errors + 1;
            end
        end
    end

    // ============================================================
    // 7. MAIN TEST SEQUENCE
    // ============================================================
    integer c;
    initial begin
        $dumpfile("xbar_benchmark.vcd");
        $dumpvars(0, tb_xbar_3by3_benchmark);

        // Initialize signals
        p0_valid_in = 0; p1_valid_in = 0; p2_valid_in = 0;
        p0_ready_ext = 1; p1_ready_ext = 1; p2_ready_ext = 1;

        rst_n_in_0 = 0; rst_n_in_1 = 0; rst_n_in_2 = 0;
        rst_n_out_0 = 0; rst_n_out_1 = 0; rst_n_out_2 = 0;
        #100;
        rst_n_in_0 = 1; rst_n_in_1 = 1; rst_n_in_2 = 1;
        rst_n_out_0 = 1; rst_n_out_1 = 1; rst_n_out_2 = 1;
        #100;

        $display("\n==========================================");
        $display("   STARTING XBAR CDC & ROUTING TEST");
        $display("==========================================\n");

        // ----------------------------------------------------
        // CHECKPOINT 1: Basic 1-to-1 Routing
        // ----------------------------------------------------
        $display("[INFO] Running Checkpoint 1: Basic Routing...");
        send_p0(64'hAAAA_0000_1111_0000, 2'd0);
        send_p1(64'hBBBB_0000_2222_0000, 2'd1);
        send_p2(64'hCCCC_0000_3333_0000, 2'd2);
        #500; 

        // ----------------------------------------------------
        // CHECKPOINT 2: Many-to-One Contention (Arbiter Stress)
        // ----------------------------------------------------
        $display("[INFO] Running Checkpoint 2: Cross-Domain Contention...");
        // Force all 3 inputs to target Output Port 0 simultaneously
        fork
            send_p0(64'hAAAA_0000_4444_0000, 2'd0);
            send_p1(64'hBBBB_0000_5555_0000, 2'd0);
            send_p2(64'hCCCC_0000_6666_0000, 2'd0);
        join
        #500;

        // ----------------------------------------------------
        // CHECKPOINT 3: Backpressure & FIFO Full Test
        // ----------------------------------------------------
        $display("[INFO] Running Checkpoint 3: Backpressure / FIFO Capacity...");
        // Turn off the output reader for Port 1 to cause a traffic jam
        p1_ready_ext = 0; 
        
        // Blast 35 packets from Input 1 to Output 1.
        // FIFO depth is 32, so ready_out on Input 1 should assert backpressure
        // and pause the task cleanly until we release p1_ready_ext.
        fork
            begin
                for (c = 0; c < 35; c = c + 1) begin
                    send_p1(64'hBBBB_DEAD_BEEF_0000 + c, 2'd1);
                end
            end
            begin
                #2000;
                $display("[INFO] Releasing Backpressure on Port 1...");
                p1_ready_ext = 1; // Drain the queue
            end
        join

        #2000; // Wait for all queues to drain

        // ----------------------------------------------------
        // FINAL SCOREBOARD CHECK
        // ----------------------------------------------------
        $display("\n==========================================");
        $display("   FINAL SCOREBOARD VERIFICATION");
        $display("==========================================\n");

        for (c = 0; c < num_sent_0; c = c + 1) begin
            if (!rcvd_from_0[c]) begin $display("[FAIL] Port 0 dropped packet: %h", sent_to_0[c]); global_errors = global_errors + 1; end
        end
        for (c = 0; c < num_sent_1; c = c + 1) begin
            if (!rcvd_from_1[c]) begin $display("[FAIL] Port 1 dropped packet: %h", sent_to_1[c]); global_errors = global_errors + 1; end
        end
        for (c = 0; c < num_sent_2; c = c + 1) begin
            if (!rcvd_from_2[c]) begin $display("[FAIL] Port 2 dropped packet: %h", sent_to_2[c]); global_errors = global_errors + 1; end
        end

        if (global_errors == 0) begin
            $display("[SUCCESS] All %0d packets routed, synchronized, and hashed flawlessly!", (num_sent_0 + num_sent_1 + num_sent_2));
        end else begin
            $display("[FAILED] Testbench encountered %0d errors.", global_errors);
        end

        $finish;
    end

    // Safety Timeout
    initial begin
        #50000;
        $display("[FATAL] Simulation Timeout Reached!");
        $finish;
    end

endmodule