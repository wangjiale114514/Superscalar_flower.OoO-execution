//RAT快照
//内容在ROB中确定内容无误后自动确定内容无异常表单退休
module rat_shot (
    input wire clk.               
    input wire reset,
     
    //RAT存入内容
    output reg [31:0] rat_shot_air;      //现空表内容(4)

    input wire [255:0] rat_shot_in_a,    //RAT输入
    input wire rat_start_a,              //RAT快照写入势能

    input wire [255:0] rat_shot_in_b,    //RAT输入
    input wire rat_start_b,              //RAT快照写入势能
    
    input wire [255:0] rat_shot_in_c,    //RAT输入
    input wire rat_start_c,              //RAT快照写入势能
    
    input wire [255:0] rat_shot_in_d,    //RAT输入
    input wire rat_start_d,              //RAT快照写入势能

    //ROB退休
    input wire [1:0] rob_kill,           //退休(01正常退休，10回溯)
    input wire [7:0] rob_kill_name,      //退休内容

    //回溯地址
    output reg [255:0] rob_kill_adderss, //RAT回溯地址
    output reg rob_kill_start,           //RAT回溯势能
    
);

    reg [255:0] rat_shot_data [7:0];     //RAT内容
    
endmodule