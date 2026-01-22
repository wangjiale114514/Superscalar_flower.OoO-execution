// ALU (算术逻辑单元)
// 功能：执行整数算术和逻辑运算
module alu (
    input wire clk,
    input wire reset,

    // 来自保留站的输入
    input wire [1:0] issue_valid,
    input wire [31:0] issue_inst [0:1],
    input wire [63:0] issue_pc [0:1],
    input wire [7:0] issue_rd [0:1],
    input wire [31:0] issue_rs1_val [0:1],
    input wire [31:0] issue_rs2_val [0:1],
    input wire [7:0] issue_rs1_tag [0:1],
    input wire [7:0] issue_rs2_tag [0:1],
    input wire [3:0] issue_op [0:1],
    input wire [6:0] issue_rob_tag [0:1],

    // 写回到CDB
    output reg [1:0] cdb_valid,
    output reg [7:0] cdb_tag [0:1],
    output reg [31:0] cdb_data [0:1],
    output reg [6:0] cdb_rob_tag [0:1],

    // 分支结果输出
    output reg [1:0] branch_valid,
    output reg [63:0] branch_pc [0:1],
    output reg [1:0] branch_taken [0:1],
    output reg [6:0] branch_rob_tag [0:1]
);

    // 执行状态机
    reg [1:0] busy [0:1];
    reg [31:0] result [0:1];
    reg [6:0] rob_tag_reg [0:1];
    reg [7:0] rd_reg [0:1];
    reg [3:0] op_reg [0:1];
    reg [31:0] rs1_reg [0:1];
    reg [31:0] rs2_reg [0:1];
    reg [63:0] pc_reg [0:1];

    // 复位
    always @(posedge reset) begin
        integer i;
        for (i = 0; i < 2; i = i + 1) begin
            busy[i] <= 1'b0;
            cdb_valid[i] <= 1'b0;
            branch_valid[i] <= 1'b0;
        end
    end

    // 接收指令
    always @(posedge clk) begin
        integer i;
        for (i = 0; i < 2; i = i + 1) begin
            if (issue_valid[i] && !busy[i]) begin
                busy[i] <= 1'b1;
                op_reg[i] <= issue_op[i];
                rs1_reg[i] <= issue_rs1_val[i];
                rs2_reg[i] <= issue_rs2_val[i];
                pc_reg[i] <= issue_pc[i];
                rob_tag_reg[i] <= issue_rob_tag[i];
                rd_reg[i] <= issue_rd[i];
            end
        end
    end

    // 执行逻辑 (组合逻辑，单周期完成)
    always @(*) begin
        integer i;
        for (i = 0; i < 2; i = i + 1) begin
            if (busy[i]) begin
                case (op_reg[i])
                    // 算术运算
                    4'b0000: result[i] = rs1_reg[i] + rs2_reg[i];       // ADD
                    4'b0001: result[i] = rs1_reg[i] - rs2_reg[i];       // SUB
                    4'b0010: result[i] = rs1_reg[i] << rs2_reg[i][4:0]; // SLL
                    4'b0011: result[i] = rs1_reg[i] >> rs2_reg[i][4:0]; // SRL
                    4'b0100: result[i] = $signed(rs1_reg[i]) >>> rs2_reg[i][4:0]; // SRA
                    4'b0101: result[i] = rs1_reg[i] < rs2_reg[i] ? 32'b1 : 32'b0;  // SLT
                    4'b0110: result[i] = $signed(rs1_reg[i]) < $signed(rs2_reg[i]) ? 32'b1 : 32'b0; // SLTU

                    // 逻辑运算
                    4'b0111: result[i] = rs1_reg[i] & rs2_reg[i];        // AND
                    4'b1000: result[i] = rs1_reg[i] | rs2_reg[i];        // OR
                    4'b1001: result[i] = rs1_reg[i] ^ rs2_reg[i];        // XOR

                    // 分支指令
                    4'b1010: begin  // BEQ
                        result[i] = rs1_reg[i] == rs2_reg[i] ? 32'b1 : 32'b0;
                    end
                    4'b1011: begin  // BNE
                        result[i] = rs1_reg[i] != rs2_reg[i] ? 32'b1 : 32'b0;
                    end
                    4'b1100: begin  // BLT
                        result[i] = $signed(rs1_reg[i]) < $signed(rs2_reg[i]) ? 32'b1 : 32'b0;
                    end
                    4'b1101: begin  // BGE
                        result[i] = $signed(rs1_reg[i]) >= $signed(rs2_reg[i]) ? 32'b1 : 32'b0;
                    end
                    4'b1110: begin  // BLTU
                        result[i] = rs1_reg[i] < rs2_reg[i] ? 32'b1 : 32'b0;
                    end
                    4'b1111: begin  // BGEU
                        result[i] = rs1_reg[i] >= rs2_reg[i] ? 32'b1 : 32'b0;
                    end

                    default: result[i] = 32'b0;
                endcase
            end else begin
                result[i] = 32'b0;
            end
        end
    end

    // 写回和分支结果输出
    always @(posedge clk) begin
        integer i;
        for (i = 0; i < 2; i = i + 1) begin
            if (busy[i]) begin
                // 检查是否是分支指令
                if (op_reg[i] >= 4'b1010 && op_reg[i] <= 4'b1111) begin
                    // 分支指令
                    branch_valid[i] <= 1'b1;
                    branch_pc[i] <= pc_reg[i];
                    branch_taken[i] <= result[i][0];
                    branch_rob_tag[i] <= rob_tag_reg[i];
                    cdb_valid[i] <= 1'b0;
                end else begin
                    // ALU指令
                    cdb_valid[i] <= 1'b1;
                    cdb_tag[i] <= rd_reg[i];
                    cdb_data[i] <= result[i];
                    cdb_rob_tag[i] <= rob_tag_reg[i];
                    branch_valid[i] <= 1'b0;
                end
                busy[i] <= 1'b0;
            end else begin
                cdb_valid[i] <= 1'b0;
                branch_valid[i] <= 1'b0;
            end
        end
    end

endmodule
