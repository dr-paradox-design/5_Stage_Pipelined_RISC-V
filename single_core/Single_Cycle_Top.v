`include "PC.v"
`include "instruction_Memory.v"
`include "Register_file.v"
`include "Sign_Extend.v"
`include "ALU.v"
`include "Control_Unit_Top.v"
`include "Data_Mem.v"
`include "PC_Adder.v"

module Single_Cycle_Top(clk,rst);  

    input clk,rst;

        wire [31:0] PC_Top, RD_Instr, RD1_Top, RD2_Top, Imm_Ext_Top, SrcB_Top, ALU_Result_Top, Read_Data_Top, PCPlus4;
        wire [2:0] ALU_Control_Top;
        wire RegWrite, ALUSrc, MemWrite, ResultSrc, Branch;
        wire [1:0] ImmSrc;
        wire [31:0] WriteData;

        assign SrcB_Top = ALUSrc ? Imm_Ext_Top : RD2_Top;
        assign WriteData = ResultSrc ? Read_Data_Top : ALU_Result_Top;

    PC_Module PC_Module(
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

    instruction_Memory instruction_Memory(
        .rst(rst),
        .A(PC_Top),
        .RD(RD_Instr)
    );
    Register_file Register_file(
        .clk(clk),
        .rst(rst),
        .WE3(RegWrite),
        .WD3(WriteData),
        .A1(RD_Instr[19:15]),
        .A2(RD_Instr[24:20]),
        .A3(RD_Instr[11:7]),
        .RD1(RD1_Top),
        .RD2(RD2_Top)
    );
    
    Sign_Extend Sign_Extend(
        .In(RD_Instr),
        .ImmSrc(ImmSrc),
        .Imm_Ext(Imm_Ext_Top)
    );

    ALU ALU(
        .A(RD1_Top),
        .B(SrcB_Top),
        .ALUControl(ALU_Control_Top),
        .Result(ALU_Result_Top),
        .Z(),
        .N(),
        .C(),
        .V()
    );

    Control_Unit_Top Control_Unit(
        .Op(RD_Instr[6:0]),
        .RegWrite(RegWrite),
        .ImmSrc(ImmSrc),
        .ALUSrc(ALUSrc),
        .MemWrite(MemWrite),
        .ResultSrc(ResultSrc),
        .Branch(Branch),
        .funct3(RD_Instr[14:12]),
        .funct7(RD_Instr[31:25]),
        .ALUControl(ALU_Control_Top)
    );

    Data_Memory Data_Memory(
        .clk(clk),
        .rst(rst),
        .WE(MemWrite),
        .A(ALU_Result_Top),
        .WD(RD2_Top),
        .RD(Read_Data_Top)
    );





endmodule