module flash_test_app #(
    parameter CLK_FREQ = 50_000_000,
    parameter AUTO_START_DELAY = 50_000_000 / 2 // 上电默认 0.5s 后自动触发自检 (仿真可加速)
) (
    input  wire        clk,
    input  wire        rst_n,

    // 外部触发脉冲 (例如按键消抖脉冲)
    input  wire        btn_trigger,

    // 连接 w25q16_ctrl 控制器接口
    output reg         flash_start,
    output reg  [2:0]  flash_operation,
    output reg  [23:0] flash_address,
    output reg  [31:0] flash_wr_data,
    input  wire [31:0] flash_rd_data,
    input  wire [23:0] flash_id,
    input  wire        flash_busy,
    input  wire        flash_done,
    input  wire        flash_error,

    // 串口发送接口 (去往 TX 仲裁 / uart_core TX FIFO)
    output reg  [7:0]  tx_data,
    output reg         tx_wrreq,
    input  wire        tx_full,

    // 最终测试状态指示
    output reg         test_done,
    output reg         test_pass
);

    // w25q16_ctrl 操作编码定义
    localparam [2:0] OP_READ_ID      = 3'd0;
    localparam [2:0] OP_SECTOR_ERASE = 3'd1;
    localparam [2:0] OP_PAGE_PROG_4B = 3'd2;
    localparam [2:0] OP_READ_DATA_4B = 3'd3;

    // 测试用的 Flash 地址与特征数据
    localparam [23:0] TEST_ADDR      = 24'h000000;
    localparam [31:0] TEST_WR_DATA   = 32'h12345678;
    localparam [31:0] BLANK_DATA     = 32'hFFFFFFFF;
    localparam [23:0] EXPECTED_ID    = 24'hEF4015;

    // ================================================================
    // 自检状态机定义 (标准三段式状态机)
    // ================================================================
    localparam [3:0] ST_POWER_WAIT = 4'd0;
    localparam [3:0] ST_IDLE       = 4'd1;
    localparam [3:0] ST_READ_ID    = 4'd2;
    localparam [3:0] ST_ERASE      = 4'd3;
    localparam [3:0] ST_CHK_BLANK  = 4'd4;
    localparam [3:0] ST_PROGRAM    = 4'd5;
    localparam [3:0] ST_VERIFY     = 4'd6;
    localparam [3:0] ST_SEND_PASS  = 4'd7;
    localparam [3:0] ST_SEND_FAIL  = 4'd8;

    reg [3:0] current_state;
    reg [3:0] next_state;

    // 上电延时计数器
    reg [31:0] power_delay_cnt;
    wire power_delay_done = (power_delay_cnt >= AUTO_START_DELAY - 1);

    // 错误原因记录 (1: ID 错, 2: 擦除未清空, 3: 回读校验不匹配, 4: 控制器异常)
    reg [2:0] fail_reason;
    reg       step_issued;

    // 串口字符串发送控制
    reg [6:0] tx_idx;
    reg [6:0] tx_len;
    reg [7:0] tx_rom_char;

    // ================================================================
    // 【第一段】现态时序锁存
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ST_POWER_WAIT;
        end else begin
            current_state <= next_state;
        end
    end

    // ================================================================
    // 【第二段】次态组合逻辑决策
    // ================================================================
    always @(*) begin
        next_state = current_state;

        case (current_state)
            // 上电延时等待稳态
            ST_POWER_WAIT: begin
                if (power_delay_done)
                    next_state = ST_READ_ID;
            end

            // 空闲状态：等待按键触发
            ST_IDLE: begin
                if (btn_trigger && !flash_busy)
                    next_state = ST_READ_ID;
            end

            // 步骤 1：读 JEDEC ID (期望 0xEF4015)
            ST_READ_ID: begin
                if (step_issued && flash_done) begin
                    if (flash_error || (flash_id != EXPECTED_ID))
                        next_state = ST_SEND_FAIL;
                    else
                        next_state = ST_ERASE;
                end
            end

            // 步骤 2：4KB 扇区擦除
            ST_ERASE: begin
                if (step_issued && flash_done) begin
                    if (flash_error)
                        next_state = ST_SEND_FAIL;
                    else
                        next_state = ST_CHK_BLANK;
                end
            end

            // 步骤 3：读空检查 (期望 0xFFFFFFFF)
            ST_CHK_BLANK: begin
                if (step_issued && flash_done) begin
                    if (flash_error || (flash_rd_data != BLANK_DATA))
                        next_state = ST_SEND_FAIL;
                    else
                        next_state = ST_PROGRAM;
                end
            end

            // 步骤 4：写入 4 字节数据 (0x12345678)
            ST_PROGRAM: begin
                if (step_issued && flash_done) begin
                    if (flash_error)
                        next_state = ST_SEND_FAIL;
                    else
                        next_state = ST_VERIFY;
                end
            end

            // 步骤 5：回读比对 (期望 0x12345678)
            ST_VERIFY: begin
                if (step_issued && flash_done) begin
                    if (flash_error || (flash_rd_data != TEST_WR_DATA))
                        next_state = ST_SEND_FAIL;
                    else
                        next_state = ST_SEND_PASS;
                end
            end

            // 成功上报：字符串发送完毕后回到 IDLE
            ST_SEND_PASS: begin
                if (tx_idx >= 7'd60)
                    next_state = ST_IDLE;
            end

            // 失败上报：字符串发送完毕后回到 IDLE
            ST_SEND_FAIL: begin
                if (tx_idx >= 7'd30)
                    next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // ================================================================
    // 【第三段】数据通路与时序控制
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_delay_cnt <= 32'd0;
            flash_start     <= 1'b0;
            flash_operation <= 3'd0;
            flash_address   <= 24'd0;
            flash_wr_data   <= 32'd0;
            fail_reason     <= 3'd0;

            tx_data         <= 8'd0;
            tx_wrreq        <= 1'b0;
            tx_idx          <= 7'd0;
            tx_len          <= 7'd0;

            test_done       <= 1'b0;
            test_pass       <= 1'b0;
            step_issued     <= 1'b0;
        end else begin
            flash_start <= 1'b0;
            tx_wrreq    <= 1'b0;

            if (current_state != next_state) begin
                step_issued <= 1'b0;
            end

            case (current_state)
                ST_POWER_WAIT: begin
                    if (!power_delay_done) begin
                        power_delay_cnt <= power_delay_cnt + 1'b1;
                    end
                end

                ST_IDLE: begin
                    tx_idx    <= 7'd0;
                    test_done <= 1'b0;
                end

                ST_READ_ID: begin
                    if (!step_issued && !flash_busy) begin
                        flash_operation <= OP_READ_ID;
                        flash_start     <= 1'b1;
                        step_issued     <= 1'b1;
                    end

                    if (step_issued && flash_done && (flash_error || (flash_id != EXPECTED_ID))) begin
                        fail_reason <= 3'd1; // ID 校验失败
                    end
                end

                ST_ERASE: begin
                    if (!step_issued && !flash_busy) begin
                        flash_operation <= OP_SECTOR_ERASE;
                        flash_address   <= TEST_ADDR;
                        flash_start     <= 1'b1;
                        step_issued     <= 1'b1;
                    end

                    if (step_issued && flash_done && flash_error) begin
                        fail_reason <= 3'd2; // 擦除操作失败
                    end
                end

                ST_CHK_BLANK: begin
                    if (!step_issued && !flash_busy) begin
                        flash_operation <= OP_READ_DATA_4B;
                        flash_address   <= TEST_ADDR;
                        flash_start     <= 1'b1;
                        step_issued     <= 1'b1;
                    end

                    if (step_issued && flash_done && (flash_error || (flash_rd_data != BLANK_DATA))) begin
                        fail_reason <= 3'd3; // 擦除后非全 0xFF
                    end
                end

                ST_PROGRAM: begin
                    if (!step_issued && !flash_busy) begin
                        flash_operation <= OP_PAGE_PROG_4B;
                        flash_address   <= TEST_ADDR;
                        flash_wr_data   <= TEST_WR_DATA;
                        flash_start     <= 1'b1;
                        step_issued     <= 1'b1;
                    end

                    if (step_issued && flash_done && flash_error) begin
                        fail_reason <= 3'd4; // 写入操作失败
                    end
                end

                ST_VERIFY: begin
                    if (!step_issued && !flash_busy) begin
                        flash_operation <= OP_READ_DATA_4B;
                        flash_address   <= TEST_ADDR;
                        flash_start     <= 1'b1;
                        step_issued     <= 1'b1;
                    end

                    if (step_issued && flash_done && (flash_error || (flash_rd_data != TEST_WR_DATA))) begin
                        fail_reason <= 3'd5; // 回读数据不一致
                    end
                end

                // ----------------------------------------------------
                // 成功结果发送 (共 60 字节)
                // "\r\n[W25Q16] ID=EF4015, ERASE=OK, WRITE=OK, READ=OK -> PASS!\r\n"
                // ----------------------------------------------------
                ST_SEND_PASS: begin
                    test_done <= 1'b1;
                    test_pass <= 1'b1;
                    tx_len    <= 7'd60;

                    if (!tx_full && (tx_idx < 7'd60)) begin
                        tx_data  <= tx_rom_char;
                        tx_wrreq <= 1'b1;
                        tx_idx   <= tx_idx + 1'b1;
                    end
                end

                // ----------------------------------------------------
                // 失败结果发送 (共 30 字节)
                // "\r\n[W25Q16] TEST FAILED (E:X)!\r\n"
                // ----------------------------------------------------
                ST_SEND_FAIL: begin
                    test_done <= 1'b1;
                    test_pass <= 1'b0;
                    tx_len    <= 7'd30;

                    if (!tx_full && (tx_idx < 7'd30)) begin
                        tx_data  <= tx_rom_char;
                        tx_wrreq <= 1'b1;
                        tx_idx   <= tx_idx + 1'b1;
                    end
                end

                default: ;
            endcase
        end
    end

    // ================================================================
    // ASCII 字符串查表逻辑 (纯组合逻辑 ROM)
    // ================================================================
    always @(*) begin
        tx_rom_char = 8'h20; // 默认空格

        if (current_state == ST_SEND_PASS) begin
            // 文本: "\r\n[W25Q16] ID=EF4015, ERASE=OK, WRITE=OK, READ=OK -> PASS!\r\n"
            case (tx_idx)
                7'd0:  tx_rom_char = 8'h0D; // \r
                7'd1:  tx_rom_char = 8'h0A; // \n
                7'd2:  tx_rom_char = "[";
                7'd3:  tx_rom_char = "W";
                7'd4:  tx_rom_char = "2";
                7'd5:  tx_rom_char = "5";
                7'd6:  tx_rom_char = "Q";
                7'd7:  tx_rom_char = "1";
                7'd8:  tx_rom_char = "6";
                7'd9:  tx_rom_char = "]";
                7'd10: tx_rom_char = " ";
                7'd11: tx_rom_char = "I";
                7'd12: tx_rom_char = "D";
                7'd13: tx_rom_char = "=";
                7'd14: tx_rom_char = "E";
                7'd15: tx_rom_char = "F";
                7'd16: tx_rom_char = "4";
                7'd17: tx_rom_char = "0";
                7'd18: tx_rom_char = "1";
                7'd19: tx_rom_char = "5";
                7'd20: tx_rom_char = ",";
                7'd21: tx_rom_char = " ";
                7'd22: tx_rom_char = "E";
                7'd23: tx_rom_char = "R";
                7'd24: tx_rom_char = "A";
                7'd25: tx_rom_char = "S";
                7'd26: tx_rom_char = "E";
                7'd27: tx_rom_char = "=";
                7'd28: tx_rom_char = "O";
                7'd29: tx_rom_char = "K";
                7'd30: tx_rom_char = ",";
                7'd31: tx_rom_char = " ";
                7'd32: tx_rom_char = "W";
                7'd33: tx_rom_char = "R";
                7'd34: tx_rom_char = "I";
                7'd35: tx_rom_char = "T";
                7'd36: tx_rom_char = "E";
                7'd37: tx_rom_char = "=";
                7'd38: tx_rom_char = "O";
                7'd39: tx_rom_char = "K";
                7'd40: tx_rom_char = ",";
                7'd41: tx_rom_char = " ";
                7'd42: tx_rom_char = "R";
                7'd43: tx_rom_char = "E";
                7'd44: tx_rom_char = "A";
                7'd45: tx_rom_char = "D";
                7'd46: tx_rom_char = "=";
                7'd47: tx_rom_char = "O";
                7'd48: tx_rom_char = "K";
                7'd49: tx_rom_char = " ";
                7'd50: tx_rom_char = "-";
                7'd51: tx_rom_char = ">";
                7'd52: tx_rom_char = " ";
                7'd53: tx_rom_char = "P";
                7'd54: tx_rom_char = "A";
                7'd55: tx_rom_char = "S";
                7'd56: tx_rom_char = "S";
                7'd57: tx_rom_char = "!";
                7'd58: tx_rom_char = 8'h0D; // \r
                7'd59: tx_rom_char = 8'h0A; // \n
                default: tx_rom_char = 8'h20;
            endcase
        end else if (current_state == ST_SEND_FAIL) begin
            // 文本: "\r\n[W25Q16] TEST FAILED (E:X)!\r\n"
            case (tx_idx)
                7'd0:  tx_rom_char = 8'h0D; // \r
                7'd1:  tx_rom_char = 8'h0A; // \n
                7'd2:  tx_rom_char = "[";
                7'd3:  tx_rom_char = "W";
                7'd4:  tx_rom_char = "2";
                7'd5:  tx_rom_char = "5";
                7'd6:  tx_rom_char = "Q";
                7'd7:  tx_rom_char = "1";
                7'd8:  tx_rom_char = "6";
                7'd9:  tx_rom_char = "]";
                7'd10: tx_rom_char = " ";
                7'd11: tx_rom_char = "T";
                7'd12: tx_rom_char = "E";
                7'd13: tx_rom_char = "S";
                7'd14: tx_rom_char = "T";
                7'd15: tx_rom_char = " ";
                7'd16: tx_rom_char = "F";
                7'd17: tx_rom_char = "A";
                7'd18: tx_rom_char = "I";
                7'd19: tx_rom_char = "L";
                7'd20: tx_rom_char = "E";
                7'd21: tx_rom_char = "D";
                7'd22: tx_rom_char = " ";
                7'd23: tx_rom_char = "(";
                7'd24: tx_rom_char = "E";
                7'd25: tx_rom_char = ":";
                7'd26: tx_rom_char = {5'b01100, fail_reason}; // 转化为 ASCII '0'~'5'
                7'd27: tx_rom_char = ")";
                7'd28: tx_rom_char = 8'h0D; // \r
                7'd29: tx_rom_char = 8'h0A; // \n
                default: tx_rom_char = 8'h20;
            endcase
        end
    end

endmodule
