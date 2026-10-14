# 50 MHz 板载主时钟 (20.000ns)
create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]

# 自动推导 PLL 生成的衍生时钟 (包含 100MHz 的 c0 和 c1 移相时钟)
derive_pll_clocks

# 声明 50MHz 与 100MHz 为异步时钟组 (跨时钟域由 CDC 打拍/握手同步器处理)
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk}] \
    -group [get_clocks {u_pll_100m|altpll_component|auto_generated|pll1|clk[*]}]

# 计算时钟不确定度模型
derive_clock_uncertainty
