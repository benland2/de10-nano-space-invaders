create_clock -name clock50_1 -period 20.0 [get_ports clock50_1]
create_clock -name clock50_2 -period 20.0 [get_ports clock50_2]
create_clock -name "i2c_20k_clock" -period 50000.000ns [get_keepers *mI2C_CTRL_CLK]

create_generated_clock -name {clockCPU} -source {clock50_1} -divide_by 6 -multiply_by 1 { clockCPU }
