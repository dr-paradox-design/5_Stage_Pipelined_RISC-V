//=============================================================================
// Control_Unit_Top.v  -  the complete instruction decoder
//=============================================================================
//
// Wraps the two decode stages that every RISC-V control unit splits into:
//
//   main_decoder  opcode -> "what SHAPE is this instruction?"
//                 Which muxes to flip, which immediate format to use, whether
//                 it writes a register or memory, and a 2-bit ALUOp summarising
//                 what class of ALU work it needs.
//
//   ALU_decoder   ALUOp + funct3 + funct7 -> "which exact ALU operation?"
//                 Only meaningful once main_decoder has said whether funct3 and
//                 funct7 mean anything for this instruction at all.
//
// Splitting it this way is not decoration: op alone cannot tell add from sub
// (identical opcode AND identical funct3 - only funct7 bit 5 differs), and
// funct3 alone is meaningless without knowing the instruction's format. Each
// decoder answers the question the other one cannot.
//
//-----------------------------------------------------------------------------
// CHANGE: THE `zero` INPUT IS GONE, AND `Branch` NOW MEANS WHAT IT SAYS
//
//   This module used to take the ALU's zero flag as an input, hand it down to
//   main_decoder, and emit a `Branch` output that was really PCSrc - "the
//   branch is taken". Two problems, both now fixed:
//
//   1. It only ever implemented beq. funct3 was passed to ALU_decoder but never
//      consulted for branches, so bne/blt/bge/bltu/bgeu all silently executed
//      as beq. Branch_Condition.v now handles that.
//
//   2. Taking a data-dependent flag into a decoder is a layering violation that
//      the pipeline cannot tolerate. Decode runs in ID; the flags do not exist
//      until EX. src/Decode_Cycle.v was working around it by passing
//      `.zero(1'b1)` to neutralise the AND gate. That workaround is now deleted
//      along with the port that caused it.
//
//   `Branch` is therefore now the RAW opcode bit. Both cores AND it with
//   Branch_Condition's verdict at the point where the flags are available:
//     single-cycle : Single_Cycle_Top.v, right beside the ALU
//     pipelined    : Execute_Cycle.v, one stage after this decoder runs
//
//   Historical note: an earlier bug had main_decoder's zero port hardcoded to
//   1'b0, which made PCSrc = branch & 0 = 0, so beq could NEVER be taken.
//   That is documented in docs/RV32I_Single_Cycle_Core.pdf section 6. The port
//   no longer exists, so that class of mistake is now unrepresentable - which
//   is a better outcome than fixing it was.
//=============================================================================

`include "ALU_decoder.v"
`include "main_decoder.v"

module Control_Unit_Top(Op,RegWrite,ImmSrc,ALUSrc,MemWrite,ResultSrc,Branch,funct3,funct7,ALUControl);

    input [6:0]Op,funct7;
    input [2:0]funct3;
    output RegWrite,ALUSrc,MemWrite,ResultSrc,Branch;
    output [1:0]ImmSrc;
    output [3:0]ALUControl;

    wire [1:0]ALUOp;

    main_decoder main_decoder(
        .op(Op),
        .RegWrite(RegWrite),
        .MemWrite(MemWrite),
        .ImmSrc(ImmSrc),
        .ALUSrc(ALUSrc),
        .ResultSrc(ResultSrc),
        .Branch(Branch),      //raw "is a branch opcode" - NOT "branch taken"
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
