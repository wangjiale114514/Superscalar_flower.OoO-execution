// Physical Register File (物理寄存器文件)
// 功能：存储物理寄存器的值，支持多端口读写
module prf (
    input wire clk,
    input wire reset,

    // 读取端口 (来自保留站)
    input wire [7:0] rs1_tag [0:1],
    input wire [7:0] rs2_tag [0:1],
    output reg [31:0] rs1_data [0:1],
    output reg [31:0] rs2_data [0:1],

    // 写入端口 (来自CDB)
    input wire [3:0] cdb_valid,
    input wire [7:0] cdb_tag [0:3],
    input wire [31:0] cdb_data [0:3],

    // 有效位输出
    output reg [255:0] prf_valid
);

    // 物理寄存器数组 (256个)
    reg [31:0] reg_data [0:255];
    reg [255:0] valid;

    // 复位
    always @(posedge reset) begin
        integer i;
        for (i = 0; i < 256; i = i + 1) begin
            reg_data[i] <= 32'b0;
            valid[i] <= 1'b0;
        end
    end

    // 读取逻辑 (异步读取)
    always @(*) begin
        integer i;
        for (i = 0; i < 2; i = i + 1) begin
            if (rs1_tag[i] != 8'b0 && valid[rs1_tag[i]]) begin
                rs1_data[i] = reg_data[rs1_tag[i]];
            end else begin
                rs1_data[i] = 32'b0;
            end

            if (rs2_tag[i] != 8'b0 && valid[rs2_tag[i]]) begin
                rs2_data[i] = reg_data[rs2_tag[i]];
            end else begin
                rs2_data[i] = 32'b0;
            end
        end
    end

    // 输出有效位
    assign prf_valid = valid;

    // 写入逻辑
    always @(posedge clk) begin
        integer i;
        for (i = 0; i < 4; i = i + 1) begin
            if (cdb_valid[i]) begin
                reg_data[cdb_tag[i]] <= cdb_data[i];
                valid[cdb_tag[i]] <= 1'b1;
            end
        end
    end

endmodule
