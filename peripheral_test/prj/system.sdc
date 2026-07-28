# 50 MHz board clock.
create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]

# Let TimeQuest calculate a default clock uncertainty model.
derive_clock_uncertainty

# Adjust the clock period here if the external clock changes.
