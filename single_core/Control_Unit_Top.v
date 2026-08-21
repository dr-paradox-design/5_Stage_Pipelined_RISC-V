
`include "ALU_decoder.v"
`include "main_decoder.v"

module Control_Unit_Top(Op,zero,RegWrite,ImmSrc,ALUSrc,MemWrite,ResultSrc,Branch,funct3,funct7,ALUControl);

    input [6:0]Op,funct7;
    input [2:0]funct3;
    //FIX: added this input. Previously main_decoder's zero port was hardcoded to 1'b0
    //below, so PCSrc (Branch) = branch-opcode & zero was always 0 and beq could never
    //take a branch. Now driven by the ALU's real zero flag from Single_Cycle_Top.
    input zero;
    output RegWrite,ALUSrc,MemWrite,ResultSrc,Branch;
    output [1:0]ImmSrc;
    output [2:0]ALUControl;

    wire [1:0]ALUOp;

    main_decoder main_decoder(
        .op(Op),
        .zero(zero), //FIX: was hardcoded .zero(1'b0) — see comment on the `zero` input above
        .RegWrite(RegWrite),
        .MemWrite(MemWrite),
        .ImmSrc(ImmSrc),
        .ALUSrc(ALUSrc),
        .ResultSrc(ResultSrc),
        .PCSrc(Branch),
        .ALUOp(ALUOp)
    );

    ALU_decoder ALU_decoder(
                            .ALUOp(ALUOp),
                            .funct3(funct3),
                            .funct7(funct7[5]),
                            .op5(Op[5]),
                            .ALUControl(ALUControl)
    );


endmodule