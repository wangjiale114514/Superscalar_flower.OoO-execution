// Common Data Bus (公共数据总线)
// 功能：广播执行结果到保留站和ROB
module cdb (
    input wire clk,
    input wire reset,

    // 来自ALU的输入
    input wire [1:0] alu_valid,
    input wire [7:0] alu_tag [0:1],
    input wire [31:0] alu_data [0:1],
    input wire [6:0] alu_rob_tag [0:1],

    // 来自LSU的输入
    input wire lsu_valid,
    input wire [7:0] lsu_tag,
    input wire [31:0] lsu_data,
    input wire [6:0] lsu_rob_tag,

    // 来自分支单元的输入
    input wire [1:0] branch_valid,
    input wire [7:0] branch_tag [0:1],
    input wire [31:0] branch_data [0:1],
    input wire [6:0] branch_rob_tag [0:1],

    // 输出 (最多4个结果)
    output reg [3:0] cdb_valid,
    output reg [7:0] cdb_tag [0:3],
    output reg [31:0] cdb_data [0:3],
    output reg [6:0] cdb_rob_tag [0:3]
);

    // 复位
    always @(posedge reset) begin
        cdb_valid <= 4'b0;
    end

    // 仲裁逻辑 (简单轮询)
    always @(*) begin
        cdb_valid = 4'b0;
        cdb_tag = '{8'b0, 8'b0, 8'b0, 8'b0};
        cdb_data = '{32'b0, 32'b0, 32'b0, 32'b0};
        cdb_rob_tag = '{7'b0, 7'b0, 7'b0, 7'b0};

        // ALU优先级最高
        if (alu_valid[0]) begin
            cdb_valid[0] = 1'b1;
            cdb_tag[0] = alu_tag[0];
            cdb_data[0] = alu_data[0];
            cdb_rob_tag[0] = alu_rob_tag[0];
        end

        if (alu_valid[1]) begin
            cdb_valid[1] = 1'b1;
            cdb_tag[1] = alu_tag[1];
            cdb_data[1] = alu_data[1];
            cdb_rob_tag[1] = alu_rob_tag[1];
        end

        // LSU次优先
        if (lsu_valid && cdb_valid[1] == 1'b0) begin
            cdb_valid[2] = 1'b1;
            cdb_tag[2] = lsu_tag;
            cdb_data[2] = lsu_data;
            cdb_rob_tag[2] = lsu_rob_tag;
        end

        // 分支单元最后
        if (branch_valid[0] && cdb_valid[2] == 1'b0) begin
            cdb_valid[3] = 1'b1;
            cdb_tag[3] = branch_tag[0];
            cdb_data[3] = branch_data[0];
            cdb_rob_tag[3] = branch_rob_tag[0];
        end
    end

endmodule
