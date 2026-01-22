// Reorder Buffer (重排序缓冲区)
// 功能：乱序执行，顺序提交
// 维护指令的执行顺序，确保异常处理精确性
module rob (
    input wire clk,
    input wire reset,
    input wire stop,           // 系统暂停

    // 来自ID阶段的输入
    input wire [3:0] id_rob_valid,      // 4条指令有效位
    input wire [31:0] id_rob_inst [0:3], // 4条指令
    input wire [63:0] id_rob_pc [0:3],   // 4条PC
    input wire [7:0] id_rob_rd [0:3],    // 4条目标物理寄存器
    input wire [7:0] id_rob_rs1 [0:3],   // 4条源寄存器1
    input wire [7:0] id_rob_rs2 [0:3],   // 4条源寄存器2
    input wire [3:0] id_rob_op [0:3],    // 4条操作码
    input wire id_rob_ready,             // ID准备好写入

    // 输出到保留站
    output reg [3:0] rob_rs_valid,       // 发射给RS的指令数
    output wire [31:0] rob_rs_inst [0:3],
    output wire [63:0] rob_rs_pc [0:3],
    output wire [7:0] rob_rs_rd [0:3],
    output wire [7:0] rob_rs_rs1 [0:3],
    output wire [7:0] rob_rs_rs2 [0:3],
    output wire [3:0] rob_rs_op [0:3],
    output wire [6:0] rob_rs_tag [0:3], // ROB条目标签

    // 来自执行单元的写回
    input wire [3:0] wb_valid,          // 写回有效位
    input wire [7:0] wb_tag [0:3],       // 写回的ROB标签
    input wire [31:0] wb_data [0:3],    // 写回数据

    // 提交相关
    output reg [3:0] commit_valid,       // 提交的指令数
    output wire [7:0] commit_tag [0:3],  // 提交的ROB标签
    output wire [63:0] commit_pc [0:3],  // 提交的PC
    output wire [31:0] commit_inst [0:3],// 提交的指令
    output wire [7:0] commit_rd [0:3],   // 提交的目标寄存器
    output wire [31:0] commit_data [0:3],// 提交的数据

    // 分支预测失败处理
    input wire bp_mispredict,            // 分支预测失败
    input wire [6:0] bp_rob_tag,         // 分支指令的ROB标签
    output wire [63:0] recover_pc,       // 恢复PC
    output wire recover_flush            // 恢复flush信号
);

    // ROB条目结构
    typedef struct packed {
        reg valid;           // 条目有效
        reg done;            // 执行完成
        reg exception;       // 异常标志
        reg [31:0] inst;     // 指令
        reg [63:0] pc;       // PC
        reg [7:0] rd;        // 目标物理寄存器
        reg [7:0] rs1;       // 源寄存器1
        reg [7:0] rs2;       // 源寄存器2
        reg [3:0] op;        // 操作码
        reg [31:0] result;   // 结果
        reg [2:0] exc_code;  // 异常码
    } rob_entry_t;

    // ROB条目数组 (64项)
    rob_entry_t rob_entries [0:63];
    reg [6:0] head_ptr;      // 提交指针
    reg [6:0] tail_ptr;      // 分配指针
    reg [6:0] count;         // 当前条目数

    // 输出寄存器
    reg [31:0] rob_rs_inst_reg [0:3];
    reg [63:0] rob_rs_pc_reg [0:3];
    reg [7:0] rob_rs_rd_reg [0:3];
    reg [7:0] rob_rs_rs1_reg [0:3];
    reg [7:0] rob_rs_rs2_reg [0:3];
    reg [3:0] rob_rs_op_reg [0:3];
    reg [6:0] rob_rs_tag_reg [0:3];

    // 复位
    always @(posedge reset) begin
        integer i;
        head_ptr <= 7'b0;
        tail_ptr <= 7'b0;
        count <= 7'b0;
        rob_rs_valid <= 4'b0;
        commit_valid <= 4'b0;

        for (i = 0; i < 64; i = i + 1) begin
            rob_entries[i].valid <= 1'b0;
            rob_entries[i].done <= 1'b0;
            rob_entries[i].exception <= 1'b0;
            rob_entries[i].inst <= 32'b0;
            rob_entries[i].pc <= 64'b0;
            rob_entries[i].rd <= 8'b0;
            rob_entries[i].rs1 <= 8'b0;
            rob_entries[i].rs2 <= 8'b0;
            rob_entries[i].op <= 4'b0;
            rob_entries[i].result <= 32'b0;
            rob_entries[i].exc_code <= 3'b0;
        end
    end

    // 分配ROB条目
    always @(posedge clk) begin
        integer i;
        reg [6:0] alloc_cnt;
        
        if (!stop) begin
            // 从ID接收指令
            if (id_rob_ready && id_rob_valid != 4'b0) begin
                alloc_cnt = 0;
                for (i = 0; i < 4; i = i + 1) begin
                    if (id_rob_valid[i] && (count + alloc_cnt) < 7'd64) begin
                        rob_entries[(tail_ptr + alloc_cnt) % 64].valid <= 1'b1;
                        rob_entries[(tail_ptr + alloc_cnt) % 64].done <= 1'b0;
                        rob_entries[(tail_ptr + alloc_cnt) % 64].exception <= 1'b0;
                        rob_entries[(tail_ptr + alloc_cnt) % 64].inst <= id_rob_inst[i];
                        rob_entries[(tail_ptr + alloc_cnt) % 64].pc <= id_rob_pc[i];
                        rob_entries[(tail_ptr + alloc_cnt) % 64].rd <= id_rob_rd[i];
                        rob_entries[(tail_ptr + alloc_cnt) % 64].rs1 <= id_rob_rs1[i];
                        rob_entries[(tail_ptr + alloc_cnt) % 64].rs2 <= id_rob_rs2[i];
                        rob_entries[(tail_ptr + alloc_cnt) % 64].op <= id_rob_op[i];
                        rob_entries[(tail_ptr + alloc_cnt) % 64].result <= 32'b0;
                        rob_entries[(tail_ptr + alloc_cnt) % 64].exc_code <= 3'b0;
                        alloc_cnt = alloc_cnt + 1;
                    end
                end
                tail_ptr <= (tail_ptr + alloc_cnt) % 64;
                count <= count + alloc_cnt;
            end

            // 处理写回
            for (i = 0; i < 4; i = i + 1) begin
                if (wb_valid[i]) begin
                    if (rob_entries[wb_tag[i]].valid) begin
                        rob_entries[wb_tag[i]].done <= 1'b1;
                        rob_entries[wb_tag[i]].result <= wb_data[i];
                    end
                end
            end

            // 处理分支预测失败
            if (bp_mispredict) begin
                // flush tail_ptr到bp_rob_tag之间的所有条目
                for (i = 0; i < 64; i = i + 1) begin
                    if ((i > bp_rob_tag) && (i <= tail_ptr) ||
                        (bp_rob_tag < tail_ptr) && ((i > bp_rob_tag) || (i <= tail_ptr))) begin
                        rob_entries[i].valid <= 1'b0;
                    end
                end
                tail_ptr <= (bp_rob_tag + 1) % 64;
                // 重新计算count
            end
        end
    end

    // 发射到保留站 (寻找已完成的指令)
    always @(*) begin
        integer i, j;
        rob_rs_valid = 4'b0;
        j = 0;

        for (i = 0; i < 64 && j < 4; i = i + 1) begin
            reg [6:0] idx;
            idx = (head_ptr + i) % 64;
            if (rob_entries[idx].valid && !rob_entries[idx].done) begin
                rob_rs_inst_reg[j] = rob_entries[idx].inst;
                rob_rs_pc_reg[j] = rob_entries[idx].pc;
                rob_rs_rd_reg[j] = rob_entries[idx].rd;
                rob_rs_rs1_reg[j] = rob_entries[idx].rs1;
                rob_rs_rs2_reg[j] = rob_entries[idx].rs2;
                rob_rs_op_reg[j] = rob_entries[idx].op;
                rob_rs_tag_reg[j] = idx;
                rob_rs_valid[j] = 1'b1;
                j = j + 1;
            end
        end
    end

    // 输出赋值
    integer k;
    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : output_assign
            assign rob_rs_inst[g] = rob_rs_inst_reg[g];
            assign rob_rs_pc[g] = rob_rs_pc_reg[g];
            assign rob_rs_rd[g] = rob_rs_rd_reg[g];
            assign rob_rs_rs1[g] = rob_rs_rs1_reg[g];
            assign rob_rs_rs2[g] = rob_rs_rs2_reg[g];
            assign rob_rs_op[g] = rob_rs_op_reg[g];
            assign rob_rs_tag[g] = rob_rs_tag_reg[g];
        end
    endgenerate

    // 提交逻辑 (从head_ptr开始，连续提交已完成的指令)
    always @(posedge clk) begin
        integer i;
        reg [3:0] commit_cnt;

        if (!stop) begin
            commit_cnt = 0;
            for (i = 0; i < 4 && i < count; i = i + 1) begin
                reg [6:0] idx;
                idx = (head_ptr + i) % 64;
                if (rob_entries[idx].valid && rob_entries[idx].done) begin
                    commit_cnt = commit_cnt + 1;
                end else begin
                    break; // 遇到未完成的指令，停止提交
                end
            end

            commit_valid <= commit_cnt;
            head_ptr <= (head_ptr + commit_cnt) % 64;
            count <= count - commit_cnt;
        end
    end

    // 提交输出
    always @(*) begin
        integer i;
        for (i = 0; i < 4; i = i + 1) begin
            reg [6:0] idx;
            idx = (head_ptr + i) % 64;
            commit_tag[i] = idx;
            commit_pc[i] = rob_entries[idx].pc;
            commit_inst[i] = rob_entries[idx].inst;
            commit_rd[i] = rob_entries[idx].rd;
            commit_data[i] = rob_entries[idx].result;
        end
    end

    // 恢复PC输出
    assign recover_pc = (bp_mispredict && rob_entries[bp_rob_tag].valid) ? 
                        rob_entries[bp_rob_tag].pc : 64'b0;
    assign recover_flush = bp_mispredict;

endmodule
