`include "PC.v"
`include "instruction_Memory.v"
`include "Register_file.v"
`include "Sign_Extend.v"
`include "ALU.v"
`include "Control_Unit_Top.v"
`include "Data_Mem.v"
`include "PC_Adder.v"
`include "Branch_Condition.v"

module Single_Cycle_Top(clk,rst);  

    input clk,rst;

        //FIX: PCTarget and PC_Next_Top are new wires, and Zero_Top below is new too.
        //Previously PC_Module's PC_NEXT was driven directly by PCPlus4 with no way to
        //ever redirect the PC on a taken branch.
        wire [31:0] PC_Top, RD_Instr, RD1_Top, RD2_Top, Imm_Ext_Top, SrcB_Top, ALU_Result_Top, Read_Data_Top, PCPlus4, PCTarget, PC_Next_Top;
        wire [3:0] ALU_Control_Top;
        wire RegWrite, ALUSrc, MemWrite, ResultSrc, Branch;
        wire [2:0] ImmSrc;
        wire [1:0] ALUSrcA;
        wire [31:0] SrcA_Top;
        wire [31:0] WriteData;

        //ALU condition flags. Zero_Top was already used; N/C/V are NEW here -
        //the ALU has always produced them but Single_Cycle_Top used to wire
        //them to nothing (.N(), .C(), .V()). They are what let Branch_Condition
        //implement blt/bge/bltu/bgeu without a single extra gate of arithmetic.
        wire Zero_Top, N_Top, C_Top, V_Top;

        //Verdict from Branch_Condition: "the comparison this funct3 asks for is
        //true". Says nothing about whether this is even a branch instruction.
        wire BranchTaken;

        //The two ANDed together: "redirect the PC this cycle".
        wire PCSrc;

        assign SrcB_Top = ALUSrc ? Imm_Ext_Top : RD2_Top;
        //Operand A: rs1 normally, PC for auipc, 0 for lui (both are A + U-imm).
        assign SrcA_Top = (ALUSrcA == 2'b01) ? PC_Top :
                          (ALUSrcA == 2'b10) ? 32'h00000000 : RD1_Top;
        assign WriteData = ResultSrc ? Read_Data_Top : ALU_Result_Top;

        //=====================================================================
        // PC-SOURCE DECISION
        //
        // This AND gate used to live inside main_decoder as `branch & zero`.
        // It has moved out here, and its right-hand side has been upgraded from
        // "the ALU result was zero" to "the comparison named by funct3 holds":
        //
        //     Branch      : from the decoder - the opcode is 1100011.
        //                   Gating on this is what stops an ordinary
        //                   `sub x4, x1, x1` (which sets Z=1) from hijacking
        //                   the PC just because its flags happen to look like a
        //                   satisfied branch condition.
        //     BranchTaken : from Branch_Condition - the actual comparison.
        //
        // Splitting the two halves is what took this core from ONE working
        // branch instruction to all six.
        //=====================================================================
        assign PCSrc = Branch & BranchTaken;
        assign PC_Next_Top = PCSrc ? PCTarget : PCPlus4;

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
        .A(SrcA_Top),
        .B(SrcB_Top),
        .ALUControl(ALU_Control_Top),
        .Result(ALU_Result_Top),
        //All four flags are now consumed. Z was already feeding the branch
        //decision; N, C and V used to be dangling and are what make signed and
        //unsigned magnitude comparisons possible. See Branch_Condition.v for
        //why N^V (not N alone) is the correct signed less-than.
        .Z(Zero_Top),
        .N(N_Top),
        .C(C_Top),
        .V(V_Top)
    );

    //=========================================================================
    // BRANCH CONDITION EVALUATOR
    //
    // Placed here, beside the ALU, because it consumes ALU flags - and in the
    // single-cycle core those are valid in the same clock period as everything
    // else. The pipelined core instantiates this exact same module inside
    // Execute_Cycle.v instead, because that is where its flags live. Same
    // module, same semantics, two different placements: the branch behaviour of
    // the two cores cannot drift apart, because it is literally the same file.
    //=========================================================================
    Branch_Condition Branch_Condition(
        .funct3(RD_Instr[14:12]),
        .Z(Zero_Top),
        .N(N_Top),
        .C(C_Top),
        .V(V_Top),
        .BranchTaken(BranchTaken)
    );

    Control_Unit_Top Control_Unit(
        .Op(RD_Instr[6:0]),
        .RegWrite(RegWrite),
        .ImmSrc(ImmSrc),
        .ALUSrc(ALUSrc),
        .ALUSrcA(ALUSrcA),
        .MemWrite(MemWrite),
        .ResultSrc(ResultSrc),
        .Branch(Branch),   //raw opcode bit now, ANDed with BranchTaken above
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