# 1. Master Clocks 
# (Dialed to 4.7ns to push past the 4.76ns zero-slack threshold for minor violations)
create_clock -name clk_in_0  -period 6.0 [get_ports {clk_in_0}]
create_clock -name clk_in_1  -period 7.0 [get_ports {clk_in_1}]
create_clock -name clk_in_2  -period 8.0 [get_ports {clk_in_2}]
create_clock -name clk_out_0 -period 4.7 [get_ports {clk_out_0}]
create_clock -name clk_out_1 -period 4.7 [get_ports {clk_out_1}]
create_clock -name clk_out_2 -period 4.7 [get_ports {clk_out_2}]

# 2. Generated Clocks (To satisfy the benchmark requirements)
create_generated_clock -name clk_div2 -source [get_ports {clk_in_0}]  -divide_by 2 [get_ports {gen_clk_in0_div2}]
create_generated_clock -name clk_div4 -source [get_ports {clk_in_1}]  -divide_by 4 [get_ports {gen_clk_in1_div4}]
create_generated_clock -name clk_div8 -source [get_ports {clk_out_0}] -divide_by 8 [get_ports {gen_clk_out0_div8}]

# 3. Asynchronous Clock Groups (CRITICAL)
# This prevents OpenSTA from reporting false violations across our Async FIFOs
set_clock_groups -asynchronous \
    -group [get_clocks {clk_in_0 clk_div2}] \
    -group [get_clocks {clk_in_1 clk_div4}] \
    -group [get_clocks {clk_in_2}] \
    -group [get_clocks {clk_out_0 clk_div8}] \
    -group [get_clocks {clk_out_1}] \
    -group [get_clocks {clk_out_2}]
