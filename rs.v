// Reservation Station (保留站)
// 功能：存储等待发射的指令，当操作数就绪时发射到执行单元
module rs (
    input wire clk,
    input wire reset,
    input wire stop,

    // 来自ROB的输入
    input wire [3:0] rob_valid,
    input wire [31:0] rob_inst [0:3],
    input wire [63:0] rob_pc [0:3],
    input wire [7:0] rob_rd [0:3],
    input wire [7:0] rob_rs1 [0:3],
    input wire [7:0] rob_rs2 [0:3],
    input wire [3:0] rob_op [0:3],
    input wire [6:0] rob_tag [0:3],

    // 来自CDB的写回 (操作数广播)
    input wire [3:0] cdb_valid,
    input wire [7:0] cdb_tag [0:3],
    input wire [31:0] cdb_data [0:3],

    // 来自物理寄存器文件的值
    input wire [31:0] prf_data [0:255],
    input wire [255:0] prf_valid,

    // 发射到执行单元
    output reg [1:0] issue_valid,   // 每周期最多发射2条
    output wire [31:0] issue_inst [0:1],
    output wire [63:0] issue_pc [0:1],
    output wire [7:0] issue_rd [0:1],
    output wire [31:0] issue_rs1_val [0:1],
    output wire [31:0] issue_rs2_val [0:1],
    output wire [7:0] issue_rs1_tag [0:1],
    output wire [7:0] issue_rs2_tag [0:1],
    output wire [3:0] issue_op [0:1],
    output wire [6:0] issue_rob_tag [0:1],

    // ROB条目完成反馈
    output reg [1:0] rob_done,
    output wire [6:0] rob_done_tag [0:1]
);

    // RS条目结构
    typedef struct packed {
        reg valid;
        reg [31:0] inst;
        reg [63:0] pc;
        reg [7:0] rd;
        reg [7:0] rs1_tag;
        reg [7:0] rs2_tag;
        reg [31:0] rs1_val;
        reg [31:0] rs2_val;
        reg rs1_ready;
        reg rs2_ready;
        reg [3:0] op;
        reg [6:0] rob_tag;
    } rs_entry_t;

    // 保留站 (16项)
    rs_entry_t rs_entries [0:15];
    reg [3:0] head_ptr;
    reg [3:0] tail_ptr;
    reg [3:0] count;

    // 输出寄存器
    reg [31:0] issue_inst_reg [0:1];
    reg [63:0] issue_pc_reg [0:1];
    reg [7:0] issue_rd_reg [0:1];
    reg [31:0] issue_rs1_val_reg [0:1];
    reg [31:0] issue_rs2_val_reg [0:1];
    reg [7:0] issue_rs1_tag_reg [0:1];
    reg [7:0] issue_rs2_tag_reg [0:1];
    reg [3:0] issue_op_reg [0:1];
    reg [6:0] issue_rob_tag_reg [0:1];

    // 复位
    always @(posedge reset) begin
        integer i;
        head_ptr <= 4'b0;
        tail_ptr <= 4'b0;
        count <= 4'b0;
        issue_valid <= 2'b0;
        rob_done <= 2'b0;

        for (i = 0; i < 16; i = i + 1) begin
            rs_entries[i].valid <= 1'b0;
            rs_entries[i].inst <= 32'b0;
            rs_entries[i].pc <= 64'b0;
            rs_entries[i].rd <= 8'b0;
            rs_entries[i].rs1_tag <= 8'b0;
            rs_entries[i].rs2_tag <= 8'b0;
            rs_entries[i].rs1_val <= 32'b0;
            rs_entries[i].rs2_val <= 32'b0;
            rs_entries[i].rs1_ready <= 1'b0;
            rs_entries[i].rs2_ready <= 1'b0;
            rs_entries[i].op <= 4'b0;
            rs_entries[i].rob_tag <= 7'b0;
        end
    end

    // 分配RS条目
    always @(posedge clk) begin
        integer i;
        reg [3:0] alloc_cnt;

        if (!stop) begin
            // 从ROB接收指令
            alloc_cnt = 0;
            for (i = 0; i < 4; i = i + 1) begin
                if (rob_valid[i] && (count + alloc_cnt) < 4'd16) begin
                    reg [3:0] idx;
                    idx = (tail_ptr + alloc_cnt) % 16;
                    rs_entries[idx].valid <= 1'b1;
                    rs_entries[idx].inst <= rob_inst[i];
                    rs_entries[idx].pc <= rob_pc[i];
                    rs_entries[idx].rd <= rob_rd[i];
                    rs_entries[idx].rs1_tag <= rob_rs1[i];
                    rs_entries[idx].rs2_tag <= rob_rs2[i];
                    rs_entries[idx].op <= rob_op[i];
                    rs_entries[idx].rob_tag <= rob_tag[i];

                    // 读取操作数
                    rs_entries[idx].rs1_ready <= prf_valid[rob_rs1[i]];
                    rs_entries[idx].rs2_ready <= prf_valid[rob_rs2[i]];
                    rs_entries[idx].rs1_val <= prf_data[rob_rs1[i]];
                    rs_entries[idx].rs2_val <= prf_data[rob_rs2[i]];

                    alloc_cnt = alloc_cnt + 1;
                end
            end
            tail_ptr <= (tail_ptr + alloc_cnt) % 16;
            count <= count + alloc_cnt;

            // 更新CDB广播的操作数
            for (i = 0; i < 16; i = i + 1) begin
                if (rs_entries[i].valid) begin
                    // 检查rs1是否匹配CDB
                    if (!rs_entries[i].rs1_ready) begin
                        for (integer j = 0; j < 4; j = j + 1) begin
                            if (cdb_valid[j] && (cdb_tag[j] == rs_entries[i].rs1_tag)) begin
                                rs_entries[i].rs1_ready <= 1'b1;
                                rs_entries[i].rs1_val <= cdb_data[j];
                            end
                        end
                    end

                    // 检查rs2是否匹配CDB
                    if (!rs_entries[i].rs2_ready) begin
                        for (integer j = 0; j < 4; j = j + 1) begin
                            if (cdb_valid[j] && (cdb_tag[j] == rs_entries[i].rs2_tag)) begin
                                rs_entries[i].rs2_ready <= 1'b1;
                                rs_entries[i].rs2_val <= cdb_data[j];
                            end
                        end
                    end
                end
            end
        end
    end

    // 发射逻辑 (从head_ptr开始寻找就绪的指令)
    always @(*) begin
        integer i, j;
        issue_valid = 2'b0;
        j = 0;

        for (i = 0; i < 16 && j < 2; i = i + 1) begin
            reg [3:0] idx;
            idx = (head_ptr + i) % 16;
            if (rs_entries[idx].valid && rs_entries[idx].rs1_ready && rs_entries[idx].rs2_ready) begin
                issue_inst_reg[j] = rs_entries[idx].inst;
                issue_pc_reg[j] = rs_entries[idx].pc;
                issue_rd_reg[j] = rs_entries[idx].rd;
                issue_rs1_val_reg[j] = rs_entries[idx].rs1_val;
                issue_rs2_val_reg[j] = rs_entries[idx].rs2_val;
                issue_rs1_tag_reg[j] = rs_entries[idx].rs1_tag;
                issue_rs2_tag_reg[j] = rs_entries[idx].rs2_tag;
                issue_op_reg[j] = rs_entries[idx].op;
                issue_rob_tag_reg[j] = rs_entries[idx].rob_tag;
                issue_valid[j] = 1'b1;
                j = j + 1;
            end
        end
    end

    // 输出赋值
    genvar g;
    generate
        for (g = 0; g < 2; g = g + 1) begin : output_assign
            assign issue_inst[g] = issue_inst_reg[g];
            assign issue_pc[g] = issue_pc_reg[g];
            assign issue_rd[g] = issue_rd_reg[g];
            assign issue_rs1_val[g] = issue_rs1_val_reg[g];
            assign issue_rs2_val[g] = issue_rs2_val_reg[g];
            assign issue_rs1_tag[g] = issue_rs1_tag_reg[g];
            assign issue_rs2_tag[g] = issue_rs2_tag_reg[g];
            assign issue_op[g] = issue_op_reg[g];
            assign issue_rob_tag[g] = issue_rob_tag_reg[g];
        end
    endgenerate

    // 发射后清除RS条目
    always @(posedge clk) begin
        integer i;
        if (!stop) begin
            for (i = 0; i < 2; i = i + 1) begin
                if (issue_valid[i]) begin
                    reg [3:0] idx;
                    idx = (head_ptr + i) % 16;
                    rs_entries[idx].valid <= 1'b0;
                    rob_done[i] <= 1'b1;
                end else begin
                    rob_done[i] <= 1'b0;
                end
            end
            head_ptr <= (head_ptr + issue_valid[0] + issue_valid[1]) % 16;
            count <= count - (issue_valid[0] + issue_valid[1]);
        end
    end

    // ROB done tag输出
    assign rob_done_tag[0] = (head_ptr) % 16;
    assign rob_done_tag[1] = (head_ptr + 1) % 16;

endmodule
