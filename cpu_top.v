// CPU顶层模块
// RV32I 乱序超标量处理器
module cpu_top (
    input wire clk,
    input wire reset,

    // 指令存储器接口
    output wire [31:0] inst_addr,
    input wire [31:0] inst_rdata,

    // 数据存储器接口
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    output reg [3:0] data_we,
    input wire [31:0] data_rdata,

    // 调试输出
    output wire [63:0] debug_pc,
    output wire [31:0] debug_inst,
    output wire debug_halt
);

    // IF-ID信号
    wire [511:0] if_id_data;
    wire [511:0] if_id_addr;
    wire [7:0] if_id_en;
    wire id_full;

    // ID-ROB信号
    wire [3:0] id_rob_valid;
    wire [31:0] id_rob_inst [0:3];
    wire [63:0] id_rob_pc [0:3];
    wire [7:0] id_rob_rd [0:3];
    wire [7:0] id_rob_rs1 [0:3];
    wire [7:0] id_rob_rs2 [0:3];
    wire [3:0] id_rob_op [0:3];

    // ROB-RS信号
    wire [3:0] rob_rs_valid;
    wire [31:0] rob_rs_inst [0:3];
    wire [63:0] rob_rs_pc [0:3];
    wire [7:0] rob_rs_rd [0:3];
    wire [7:0] rob_rs_rs1 [0:3];
    wire [7:0] rob_rs_rs2 [0:3];
    wire [3:0] rob_rs_op [0:3];
    wire [6:0] rob_rs_tag [0:3];

    // RS-ALU信号
    wire [1:0] rs_alu_valid;
    wire [31:0] rs_alu_inst [0:1];
    wire [63:0] rs_alu_pc [0:1];
    wire [7:0] rs_alu_rd [0:1];
    wire [31:0] rs_alu_rs1_val [0:1];
    wire [31:0] rs_alu_rs2_val [0:1];
    wire [7:0] rs_alu_rs1_tag [0:1];
    wire [7:0] rs_alu_rs2_tag [0:1];
    wire [3:0] rs_alu_op [0:1];
    wire [6:0] rs_alu_rob_tag [0:1];

    // ALU-CDB信号
    wire [1:0] alu_cdb_valid;
    wire [7:0] alu_cdb_tag [0:1];
    wire [31:0] alu_cdb_data [0:1];
    wire [6:0] alu_cdb_rob_tag [0:1];

    // CDB信号
    wire [3:0] cdb_valid;
    wire [7:0] cdb_tag [0:3];
    wire [31:0] cdb_data [0:3];
    wire [6:0] cdb_rob_tag [0:3];

    // PRF信号
    wire [31:0] prf_rs1_data [0:1];
    wire [31:0] prf_rs2_data [0:1];
    wire [255:0] prf_valid;

    // 分支预测信号
    wire [63:0] bp_next_pc;
    wire [7:0] bp_inst_seg;
    wire [7:0] bp_if;

    // ROB提交信号
    wire [3:0] commit_valid;
    wire [7:0] commit_tag [0:3];
    wire [63:0] commit_pc [0:3];
    wire [31:0] commit_inst [0:3];
    wire [7:0] commit_rd [0:3];
    wire [31:0] commit_data [0:3];

    // 分支预测失败
    wire bp_mispredict;
    wire [6:0] bp_rob_tag;
    wire [63:0] recover_pc;
    wire recover_flush;

    // IF阶段实例化
    if if_stage (
        .clk(clk),
        .reset(reset),
        .stop(1'b0),
        .i_cache_adderss_read(),
        .i_cache_data_read(256'b0),
        .i_cache_tag_read(256'b0),
        .i_cache_hit_read(4'b1111),
        .i_cache_adderss_write(),
        .i_cache_data_write(),
        .i_cache_tag_write(),
        .i_cache_start(),
        .cache_adderss_read(),
        .cache_data_read(),
        .cache_hit_read(),
        .cache_adderss_write(),
        .cache_data_write(),
        .cache_start(),
        .write_stop(),
        .mem_adderss_read(),
        .mem_data_read(),
        .id_fifo_data(if_id_data),
        .id_fifo_en(if_id_en),
        .id_fifo_stop(id_full),
        .inst_bp(bp_if),
        .id_fifo_adderss(if_id_addr),
        .bp_adderss(),
        .bp_data(),
        .bp_next_pc(bp_next_pc),
        .bp_inst_seg(bp_inst_seg),
        .bp_if(),
        .jump_start(1'b0),
        .jump_adderss(64'b0)
    );

    // ID阶段实例化
    id id_stage (
        .clk(clk),
        .reset(reset),
        .stop(1'b0),
        .bp_reset(recover_flush),
        .if_data_flat(if_id_data),
        .if_adderss_flat(if_id_addr),
        .bp_in(bp_if),
        .if_in_en(if_id_en),
        .if_out_full(id_full),
        .rat_file(),
        .rat_now_null(),
        .rat_wire(),
        .rat_wire_en()
    );

    // ROB实例化
    rob reorder_buffer (
        .clk(clk),
        .reset(reset),
        .stop(1'b0),
        .id_rob_valid(id_rob_valid),
        .id_rob_inst(id_rob_inst),
        .id_rob_pc(id_rob_pc),
        .id_rob_rd(id_rob_rd),
        .id_rob_rs1(id_rob_rs1),
        .id_rob_rs2(id_rob_rs2),
        .id_rob_op(id_rob_op),
        .id_rob_ready(1'b0),
        .rob_rs_valid(rob_rs_valid),
        .rob_rs_inst(rob_rs_inst),
        .rob_rs_pc(rob_rs_pc),
        .rob_rs_rd(rob_rs_rd),
        .rob_rs_rs1(rob_rs_rs1),
        .rob_rs_rs2(rob_rs_rs2),
        .rob_rs_op(rob_rs_op),
        .rob_rs_tag(rob_rs_tag),
        .wb_valid(cdb_valid),
        .wb_tag(cdb_tag),
        .wb_data(cdb_data),
        .commit_valid(commit_valid),
        .commit_tag(commit_tag),
        .commit_pc(commit_pc),
        .commit_inst(commit_inst),
        .commit_rd(commit_rd),
        .commit_data(commit_data),
        .bp_mispredict(bp_mispredict),
        .bp_rob_tag(bp_rob_tag),
        .recover_pc(recover_pc),
        .recover_flush(recover_flush)
    );

    // 保留站实例化
    rs reservation_station (
        .clk(clk),
        .reset(reset),
        .stop(1'b0),
        .rob_valid(rob_rs_valid),
        .rob_inst(rob_rs_inst),
        .rob_pc(rob_rs_pc),
        .rob_rd(rob_rs_rd),
        .rob_rs1(rob_rs_rs1),
        .rob_rs2(rob_rs_rs2),
        .rob_op(rob_rs_op),
        .rob_tag(rob_rs_tag),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        .prf_data(),
        .prf_valid(prf_valid),
        .issue_valid(rs_alu_valid),
        .issue_inst(rs_alu_inst),
        .issue_pc(rs_alu_pc),
        .issue_rd(rs_alu_rd),
        .issue_rs1_val(rs_alu_rs1_val),
        .issue_rs2_val(rs_alu_rs2_val),
        .issue_rs1_tag(rs_alu_rs1_tag),
        .issue_rs2_tag(rs_alu_rs2_tag),
        .issue_op(rs_alu_op),
        .issue_rob_tag(rs_alu_rob_tag),
        .rob_done(),
        .rob_done_tag()
    );

    // ALU实例化
    alu alu_unit (
        .clk(clk),
        .reset(reset),
        .issue_valid(rs_alu_valid),
        .issue_inst(rs_alu_inst),
        .issue_pc(rs_alu_pc),
        .issue_rd(rs_alu_rd),
        .issue_rs1_val(rs_alu_rs1_val),
        .issue_rs2_val(rs_alu_rs2_val),
        .issue_rs1_tag(rs_alu_rs1_tag),
        .issue_rs2_tag(rs_alu_rs2_tag),
        .issue_op(rs_alu_op),
        .issue_rob_tag(rs_alu_rob_tag),
        .cdb_valid(alu_cdb_valid),
        .cdb_tag(alu_cdb_tag),
        .cdb_data(alu_cdb_data),
        .cdb_rob_tag(alu_cdb_rob_tag),
        .branch_valid(),
        .branch_pc(),
        .branch_taken(),
        .branch_rob_tag()
    );

    // PRF实例化
    prf physical_regfile (
        .clk(clk),
        .reset(reset),
        .rs1_tag(rs_alu_rs1_tag),
        .rs2_tag(rs_alu_rs2_tag),
        .rs1_data(prf_rs1_data),
        .rs2_data(prf_rs2_data),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        .prf_valid(prf_valid)
    );

    // CDB实例化
    cdb common_data_bus (
        .clk(clk),
        .reset(reset),
        .alu_valid(alu_cdb_valid),
        .alu_tag(alu_cdb_tag),
        .alu_data(alu_cdb_data),
        .alu_rob_tag(alu_cdb_rob_tag),
        .lsu_valid(1'b0),
        .lsu_tag(8'b0),
        .lsu_data(32'b0),
        .lsu_rob_tag(7'b0),
        .branch_valid(2'b00),
        .branch_tag(),
        .branch_data(),
        .branch_rob_tag(),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        .cdb_rob_tag(cdb_rob_tag)
    );

    // 调试输出
    assign debug_pc = commit_pc[0];
    assign debug_inst = commit_inst[0];
    assign debug_halt = 1'b0;

    // 指令存储器接口
    assign inst_addr = 32'b0;

    // 数据存储器接口
    assign data_addr = 32'b0;
    assign data_wdata = 32'b0;
    assign data_we = 4'b0;

endmodule
