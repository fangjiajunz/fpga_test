`timescale 1ns / 1ps

module test_top #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input wire sys_clk,
    input wire sys_rst_n,

    // 串口物理接口
    input  wire uart_rxd,
    output wire uart_txd,

    // 板载外设接口
    output wire [3:0] led,
    input  wire [3:0] key,

    // SDRAM 物理芯片接口
    output wire        sdram_clk,    // SDRAM 芯片时钟
    output wire        sdram_cke,    // SDRAM 时钟使能
    output wire        sdram_cs_n,   // SDRAM 片选
    output wire        sdram_ras_n,  // SDRAM 行有效
    output wire        sdram_cas_n,  // SDRAM 列有效
    output wire        sdram_we_n,   // SDRAM 写有效
    output wire [ 1:0] sdram_ba,     // SDRAM Bank 地址
    output wire [12:0] sdram_addr,   // SDRAM 行/列地址
    output wire [ 1:0] sdram_dqm,    // SDRAM 数据掩码
    inout  wire [15:0] sdram_data    // SDRAM 双向数据总线
);

    // ================================================================
    // 1. PLL 时钟与复位同步
    // ================================================================
    wire clk_100m;
    wire clk_100m_shift;
    wire pll_locked;

    pll_100m u_pll_100m (
        .areset(!sys_rst_n),
        .inclk0(sys_clk),
        .c0    (clk_100m),
        .c1    (clk_100m_shift),
        .locked(pll_locked)
    );

    wire rst_n_100m;

    rst_sync u_rst_sync_100m (
        .clk        (clk_100m),
        .async_rst_n(sys_rst_n),
        .ext_en     (pll_locked),
        .sync_rst_n (rst_n_100m)
    );

    // ================================================================
    // 2. SDRAM 控制器例化
    // ================================================================
    wire        sdram_wr_req;
    wire        sdram_rd_req;
    wire [23:0] sdram_wr_addr;
    wire [23:0] sdram_rd_addr;
    wire [ 9:0] sdram_wr_len;
    wire [ 9:0] sdram_rd_len;
    wire [15:0] sdram_wr_data;
    wire        sdram_wr_ack;
    wire        sdram_rd_ack;
    wire [15:0] sdram_rd_data;
    wire        sdram_rw_busy;
    wire        sdram_rw_done;
    wire        sdram_init_done;

    sdram_top #(
        .CLK_FREQ_MHZ(100)
    ) u_sdram_top (
        .ref_clk(clk_100m),
        .out_clk(clk_100m_shift),
        .rst_n  (rst_n_100m),

        .wr_req   (sdram_wr_req),
        .rd_req   (sdram_rd_req),
        .wr_addr  (sdram_wr_addr),
        .rd_addr  (sdram_rd_addr),
        .wr_len   (sdram_wr_len),
        .rd_len   (sdram_rd_len),
        .wr_data  (sdram_wr_data),
        .wr_ack   (sdram_wr_ack),
        .rd_ack   (sdram_rd_ack),
        .rd_data  (sdram_rd_data),
        .rw_busy  (sdram_rw_busy),
        .rw_done  (sdram_rw_done),
        .init_done(sdram_init_done),

        .sdram_clk  (sdram_clk),
        .sdram_cke  (sdram_cke),
        .sdram_cs_n (sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n (sdram_we_n),
        .sdram_ba   (sdram_ba),
        .sdram_addr (sdram_addr),
        .sdram_dqm  (sdram_dqm),
        .sdram_data (sdram_data)
    );

    // ================================================================
    // 3. 用户按键消抖 (跑在 100MHz 消除跨时钟域风险)
    // key[0]: 触发写
    // key[1]: 触发读与校验
    // ================================================================
    wire btn_edge_0;
    wire btn_edge_1;

    ax_debounce #(
        .CLK_FREQ   (100_000_000),
        .DEBOUNCE_MS(20)
    ) u_ax_debounce_0 (
        .sys_clk  (clk_100m),
        .sys_rst_n(rst_n_100m),
        .btn_in   (key[0]),
        .btn_out  (),
        .btn_edge (btn_edge_0)
    );

    ax_debounce #(
        .CLK_FREQ   (100_000_000),
        .DEBOUNCE_MS(20)
    ) u_ax_debounce_1 (
        .sys_clk  (clk_100m),
        .sys_rst_n(rst_n_100m),
        .btn_in   (key[1]),
        .btn_out  (),
        .btn_edge (btn_edge_1)
    );

    // ================================================================
    // 4. 自测控制逻辑与状态机例化 (顶层指定写入与读出比对数据)
    // ================================================================
    reg         do_write_trig;
    reg         do_read_trig;
    reg  [23:0] target_addr;
    wire [ 9:0] target_len = 10'd4;

    // 顶层自定义数据模板配置
    reg  [15:0] test_wr_pattern = 16'h1000;  // 顶层指定：起始写 16'h1111
    reg  [15:0] test_exp_pattern = 16'h1000;  // 顶层指定：期望读 16'h1111

    wire        test_pass;
    wire        test_err;
    wire [15:0] read_back_data;  // 读回的最后有效数据

    sdram_test_self u_sdram_test_self (
        .clk             (clk_100m),
        .rst_n           (rst_n_100m),
        .do_write_trig   (do_write_trig),
        .do_read_trig    (do_read_trig),
        .target_addr     (target_addr),
        .target_len      (target_len),
        .test_wr_pattern (test_wr_pattern),
        .test_exp_pattern(test_exp_pattern),

        .init_done(sdram_init_done),
        .rw_busy  (sdram_rw_busy),
        .rw_done  (sdram_rw_done),
        .wr_ack   (sdram_wr_ack),
        .rd_ack   (sdram_rd_ack),
        .rd_data  (sdram_rd_data),
        .wr_req   (sdram_wr_req),
        .rd_req   (sdram_rd_req),
        .wr_addr  (sdram_wr_addr),
        .rd_addr  (sdram_rd_addr),
        .wr_len   (sdram_wr_len),
        .rd_len   (sdram_rd_len),
        .wr_data  (sdram_wr_data),

        .test_pass   (test_pass),
        .test_err    (test_err),
        .last_rd_data(read_back_data)
    );

    // 触发信号生成与参数配置
    reg is_writing;
    reg is_reading;

    always @(posedge clk_100m or negedge rst_n_100m) begin
        if (!rst_n_100m) begin
            target_addr      <= 24'h000_000;

            test_exp_pattern <= 1'b0;
            test_wr_pattern  <= 1'b0;
            do_write_trig    <= 1'b0;
            do_read_trig     <= 1'b0;
            is_writing       <= 1'b0;
            is_reading       <= 1'b0;
        end else begin
            // 按键 0 触发写 (仅在空闲且已完成初始化时响应)
            if (btn_edge_0 && sdram_init_done && !sdram_rw_busy && !is_writing && !is_reading) begin
                do_write_trig   <= 1'b1;
                is_writing      <= 1'b1;
                test_wr_pattern <= test_wr_pattern + 1;
            end else begin
                do_write_trig <= 1'b0;
            end

            // 按键 1 触发读校验 (仅在空闲且已完成初始化时响应)
            if (btn_edge_1 && sdram_init_done && !sdram_rw_busy && !is_writing && !is_reading) begin
                do_read_trig     <= 1'b1;
                is_reading       <= 1'b1;
                test_exp_pattern <= test_exp_pattern + 1;
            end else begin
                do_read_trig <= 1'b0;
            end

            // 突发完成时复位读写状态
            if (sdram_rw_done) begin
                is_writing <= 1'b0;
                is_reading <= 1'b0;
            end

            // 仅在写操作突发完成后，地址自动递增 (读时不递增，方便多次核对同一块区域)
            if (1'b0) begin  // 禁用自动累加，锁定在基地址 24'h000_000，确保按键写与按键读对齐同一块内存
                if (target_addr + target_len >= 24'h3FFFFF) begin
                    target_addr <= 24'h000_000;
                end else begin
                    target_addr <= target_addr + target_len;
                end
            end
        end
    end

    // ================================================================
    // 5. 串口发送控制逻辑：
    //    在 SDRAM 突发读完成且校验结算时，将读出的 16 位 read_back_data 发送出去
    //    顺序：先发高 8 位 (read_back_data[15:8])，再发低 8 位 (read_back_data[7:0])
    // ================================================================
    reg  [ 1:0] tx_state;
    reg  [15:0] tx_data_latch;
    reg  [ 7:0] uart_tx_data;
    reg         uart_tx_wrreq;
    wire        uart_tx_full;

    localparam UTX_IDLE = 2'd0;
    localparam UTX_SEND_HIGH = 2'd1;
    localparam UTX_SEND_LOW = 2'd2;
    localparam UTX_DONE = 2'd3;

    always @(posedge clk_100m or negedge rst_n_100m) begin
        if (!rst_n_100m) begin
            tx_state      <= UTX_IDLE;
            tx_data_latch <= 16'd0;
            uart_tx_data  <= 8'd0;
            uart_tx_wrreq <= 1'b0;
        end else begin
            case (tx_state)
                UTX_IDLE: begin
                    uart_tx_wrreq <= 1'b0;
                    if (sdram_rw_done && is_reading) begin
                        tx_data_latch <= read_back_data;
                        tx_state      <= UTX_SEND_HIGH;
                    end
                end

                UTX_SEND_HIGH: begin
                    if (!uart_tx_full) begin
                        uart_tx_data  <= tx_data_latch[15:8];
                        uart_tx_wrreq <= 1'b1;
                        tx_state      <= UTX_SEND_LOW;
                    end else begin
                        uart_tx_wrreq <= 1'b0;
                    end
                end

                UTX_SEND_LOW: begin
                    if (!uart_tx_full) begin
                        uart_tx_data  <= tx_data_latch[7:0];
                        uart_tx_wrreq <= 1'b1;
                        tx_state      <= UTX_DONE;
                    end else begin
                        uart_tx_wrreq <= 1'b0;
                    end
                end

                UTX_DONE: begin
                    uart_tx_wrreq <= 1'b0;
                    tx_state      <= UTX_IDLE;
                end

                default: begin
                    uart_tx_wrreq <= 1'b0;
                    tx_state      <= UTX_IDLE;
                end
            endcase
        end
    end

    // ================================================================
    // 6. UART 核心模块例化
    //    运行在 100MHz 内部时钟域，与 SDRAM 测试模块处于同一时钟域
    // ================================================================
    uart_core #(
        .UART_BPS       (UART_BPS),
        .CLK_FREQ       (100_000_000),
        .FIFO_SHOW_AHEAD(1)
    ) u_uart_core (
        .clk  (clk_100m),
        .rst_n(rst_n_100m),

        .rxd(uart_rxd),
        .txd(uart_txd),

        .rx_data         (),
        .rx_valid        (),
        .rx_empty        (),
        .rx_full         (),
        .rx_overflow     (),
        .rx_frame_error  (),
        .rx_overflow_clr (1'b0),
        .rx_frame_err_clr(1'b0),

        .tx_data (uart_tx_data),
        .tx_wrreq(uart_tx_wrreq),
        .tx_full (uart_tx_full)
    );

    // ================================================================
    // 7. 状态指示灯 (高电平点亮：1 为亮，0 为灭)
    // led[0]: PLL 锁相环稳定指示
    // led[1]: SDRAM 上电初始化完成指示
    // led[2]: 突发读写进行中指示
    // led[3]: 数据校验通过指示 (读回256个数据完全匹配时点亮，出错时熄灭)
    // ================================================================
    assign led[0] = pll_locked;
    assign led[1] = sdram_init_done;
    assign led[2] = sdram_rw_busy;
    assign led[3] = test_pass;  // 校验成功时常亮 (高电平点亮：平时与复位时灭，校验通过后亮)

endmodule
