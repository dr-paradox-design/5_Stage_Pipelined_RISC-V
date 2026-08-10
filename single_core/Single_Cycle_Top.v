`include "PC.v"
`include "Instruction_Memory.v"
`include "Reg_File.v"
`include "Sign_Extend.v"
`include "ALU.v"
`include "Control_Unit_Top.v"
`include "Data_Memory.v"
`include "PC_Adder.v"

module Single_Cycle_Top(clk,rst);  

    input clk,rst;

    wire [31:0] PC_Top,RD_Instr,RD1_Top, Imm_Ext_Top , ALU_Control_Top, ALU_Result_Top,Read_Data_Top, PCPlus4;
    wire RegWrite;

    PC_Module PC(
        .clk(clk),
        .rst(rst),
        .PC(PC_Top),
        .PC_NEXT(PCPlus4)        
    );

    PC_Adder PC_Adder(
        .a(PC_Top),
        .b(32'h00000004),
        .c(PCPlus4)
    );

    Instruction_Memory Instruction_Memory(
        .rst(rst),
        .A(PC_Top),
        .RD(),
    );
    Register_file Register_File(
        .clk(clk),
        .rst(rst),
        .WE3(RegWrite),
        .WD3(Read_Data_Top),
        .A1(RD_Instr[19:15]),
        .A2(),
        .A3(RD_Instr[11:7]),
        .RD1(RD1_Top),
        .RD2()
    );


    Sign_Extend Sign_Extend(
        .In(RD_Instr[31:20]),
        .Imm_Ext(Imm_Ext_Top)
    );

    ALU ALU(
        .A(RD1_Top),
        .B(Imm_Ext_Top),
        .ALU_Control(ALU_Control_Top),
        .ALU_Result(ALU_Result_Top),
        .Z(),
        .N(),
        .C(),
        .V()
    );

    Control_Unit_Top Control_Unit(
        .Op(RD_Instr[6:0]),
        .RegWrite(),
        .ImmSrc(),
        .ALUSrc(),
        .MemWrite(),
        .ResultSrc(),
        .Branch(),
        .funct3(RD_Instr[14:12]),
        .funct7(),
        .ALUControl(ALU_Control_Top)
    );

    Data_Memory Data_Memory(
        .clk(clk),
        .rst(rst),
        .WE(),
        .A(ALU_Result_Top),
        .WD(),
        .RD(Read_Data_Top)
    );





endmodule