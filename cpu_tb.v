// CPU测试平台
// 用于测试CPU的基本功能
`timescale 1ns/1ps

module cpu_tb;

    // 输入
    reg clk;
    reg reset;

    // 指令存储器接口
    wire [31:0] inst_addr;
    reg [31:0] inst_rdata;

    // 数据存储器接口
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0] data_we;
    reg [31:0] data_rdata;

    // 调试输出
    wire [63:0] debug_pc;
    wire [31:0] debug_inst;
    wire debug_halt;

    // CPU实例化
    cpu_top cpu (
        .clk(clk),
        .reset(reset),
        .inst_addr(inst_addr),
        .inst_rdata(inst_rdata),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_we(data_we),
        .data_rdata(data_rdata),
        .debug_pc(debug_pc),
        .debug_inst(debug_inst),
        .debug_halt(debug_halt)
    );

    // 时钟生成 (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 指令存储器 (模拟)
    always @(posedge clk) begin
        case (inst_addr)
            32'h00000000: inst_rdata = 32'h00300293;  // addi x5, x0, 3  (x5 = 3)
            32'h00000004: inst_rdata = 32'h00310313;  // addi x6, x2, 3  (x6 = 3)
            32'h00000008: inst_rdata = 32'h006282b3;  // add  x5, x5, x6 (x5 = 6)
            32'h0000000C: inst_rdata = 32'h00300193;  // addi x3, x0, 3  (x3 = 3)
            32'h00000010: inst_rdata = 32'h00028463;  // beq x5, x3, 4  (不跳转)
            32'h00000014: inst_rdata = 32'h00300393;  // addi x7, x0, 3  (x7 = 3)
            32'h00000018: inst_rdata = 32'h0000006F;  // jal  x1, 0     (跳转到0x18, x1 = 0x1C)
            default:       inst_rdata = 32'h00000000;
        endcase
    end

    // 数据存储器 (模拟)
    always @(posedge clk) begin
        if (data_we != 4'b0) begin
            $display("[%0t] Write MEM[0x%h] = 0x%h", $time, data_addr, data_wdata);
        end
    end

    // 测试流程
    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0, cpu_tb);

        $display("========== CPU Test Start ==========");

        // 复位
        reset = 1;
        #20;
        reset = 0;
        $display("[%0t] Reset released", $time);

        // 运行一段时间
        #1000;

        $display("[%0t] PC = 0x%h, Inst = 0x%h", $time, debug_pc, debug_inst);
        $display("========== CPU Test End ==========");

        $finish;
    end

    // 监控PC变化
    always @(posedge clk) begin
        if (!reset && debug_pc != 64'b0) begin
            $display("[%0t] PC = 0x%h, Inst = 0x%h", $time, debug_pc, debug_inst);
        end
    end

endmodule
