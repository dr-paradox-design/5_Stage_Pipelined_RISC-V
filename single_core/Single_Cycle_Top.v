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

        //FIX: PCTarget and PC_Next_Top are new wires, and Zero_Top below is new too.
        //Previously PC_Module's PC_NEXT was driven directly by PCPlus4 with no way to
        //ever redirect the PC on a taken branch.
        wire [31:0] PC_Top, RD_Instr, RD1_Top, RD2_Top, Imm_Ext_Top, SrcB_Top, ALU_Result_Top, Read_Data_Top, PCPlus4, PCTarget, PC_Next_Top;
        wire [2:0] ALU_Control_Top;
        wire RegWrite, ALUSrc, MemWrite, ResultSrc, Branch, Zero_Top;
        wire [1:0] ImmSrc;
        wire [31:0] WriteData;

        assign SrcB_Top = ALUSrc ? Imm_Ext_Top : RD2_Top;
        assign WriteData = ResultSrc ? Read_Data_Top : ALU_Result_Top;

        //FIX: new PC-source mux. Branch is Control_Unit_Top's PCSrc output
        //(branch opcode & ALU zero flag) - selects the branch target on a taken
        //branch, otherwise PC+4. This is what actually makes beq redirect fetch.
        assign PC_Next_Top = Branch ? PCTarget : PCPlus4;

    PC_Module PC_Module(
        .clk(clk),
        .rst(rst),
        .PC(PC_Top),
        .PC_NEXT(PC_Next_Top) //FIX: was PCPlus4 directly, now the muxed PC_Next_Top
    );

    PC_Adder PC_Adder(
        .a(PC_Top),
        .b(32'h00000004),
        .c(PCPlus4)
    );

    //FIX: new instance. Reuses PC_Adder as a generic adder to compute the branch
    //target (PC + sign-extended branch immediate) for the PC-source mux above.
    PC_Adder Branch_Adder(
        .a(PC_Top),
        .b(Imm_Ext_Top),
        .c(PCTarget)
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
        .Z(Zero_Top), //FIX: was .Z() (left unconnected) — now feeds Control_Unit_Top
        .N(),
        .C(),
        .V()
    );

    Control_Unit_Top Control_Unit(
        .Op(RD_Instr[6:0]),
        .zero(Zero_Top), //FIX: new connection, see Control_Unit_Top.v for why it matters
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