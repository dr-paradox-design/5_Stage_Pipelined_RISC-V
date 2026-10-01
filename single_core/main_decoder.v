//=============================================================================
// main_decoder.v  -  opcode -> control signals
//=============================================================================
//
// Pure combinational decode of the 7-bit opcode field into the control bits
// that steer the datapath muxes. One instruction in, a fistful of one-bit
// answers out.
//
//-----------------------------------------------------------------------------
// CHANGE: THIS MODULE NO LONGER DECIDES WHETHER A BRANCH IS TAKEN
//
//   It used to. The port list had a `zero` input and a `PCSrc` output, and the
//   last line was:
//
//        assign PCSrc = branch & zero;
//
//   Two things were wrong with that, one cosmetic and one a real bug.
//
//   THE REAL BUG: `zero` alone only implements beq. RV32I has six conditional
//   branches sharing opcode 1100011, told apart by funct3 - a field this module
//   never even looked at. So `bne` decoded as a branch, got ALUOp=01
//   (subtract), and was then tested against `zero`... which made it branch when
//   the operands were EQUAL. It silently executed as beq. Same for blt/bge/
//   bltu/bgeu, all of which behaved as beq. Five of the six branch instructions
//   in the ISA were quietly wrong. That decision now lives in
//   Branch_Condition.v, which does read funct3 - see that file for the full
//   derivation of all six conditions from the ALU flags.
//
//   THE COSMETIC ONE: a decoder that needs an ALU flag as an INPUT is not
//   really a decoder. Its whole job is "given the instruction bits, what should
//   the datapath do?" - a pure function of the instruction. `zero` is a
//   function of the operand VALUES, which is a different question asked at a
//   different time. In the single-cycle core you could get away with blurring
//   them because everything happened in one clock period. In the pipeline you
//   cannot: decode happens in ID, the flags do not exist until EX. That forced
//   src/Decode_Cycle.v to pass `.zero(1'b1)` purely to neutralise the AND gate
//   so it could redo the AND later in the right stage. Removing the input
//   removes the need for that hack.
//
//   So this module now emits `Branch`, meaning only "the opcode is 1100011".
//   Whoever holds the ALU flags does the rest: Single_Cycle_Top.v next to its
//   ALU, Execute_Cycle.v inside the pipeline's EX stage.
//
//-----------------------------------------------------------------------------
// OPCODES THIS CORE UNDERSTANDS
//   0110011  R-type    add sub and or xor slt sltu sll srl sra
//   0010011  I-type    addi andi ori xori slti sltiu slli srli srai
//   0000011  I-type    lw
//   0100011  S-type    sw
//   1100011  B-type    beq bne blt bge bltu bgeu
//
//   Anything else decodes to all-zeros: no register write, no memory write, no
//   branch. Architecturally inert rather than actively destructive. This core
//   has no illegal-instruction exception, so "do nothing" is the best available
//   answer - though note it is still a SILENT one, which is why unsupported
//   instructions must be tracked in the docs rather than discovered by running
//   them.
//=============================================================================

module main_decoder(op,RegWrite,MemWrite,ImmSrc,ALUSrc,ResultSrc,Branch,ALUOp);
    //input and output declaration
    input [6:0] op;
    output RegWrite,MemWrite,ALUSrc,Branch,ResultSrc ;
    output [1:0] ImmSrc,ALUOp;

    //if op is 0110011 or 0000011 or 0010011 then RegWrite=1 else RegWrite=0
    assign RegWrite = (op == 7'b0110011) | (op == 7'b0000011) | (op == 7'b0010011) ? 1'b1 : 1'b0;
    assign MemWrite = (op == 7'b0100011) ? 1'b1 : 1'b0;
    assign ALUSrc = (op == 7'b0000011) | (op == 7'b0010011) | (op == 7'b0100011) ? 1'b1 : 1'b0;
    assign ResultSrc = (op == 7'b0000011) ? 1'b1 : 1'b0; //if op is 0000011 then ResultSrc=1 else ResultSrc=0

    //RAW branch-opcode bit ONLY - "this is one of the six B-type branches".
    //Whether it is TAKEN is decided by Branch_Condition.v from funct3 + the ALU
    //flags, in whichever stage those flags exist. See the header above.
    assign Branch = (op == 7'b1100011) ? 1'b1 : 1'b0;

    assign ImmSrc = (op == 7'b0100011) ? 2'b01 :( op == 7'b1100011) ? 2'b10 : 2'b0;

    //ALUOp tells ALU_decoder what KIND of instruction this is, so it knows
    //whether funct3/funct7 are meaningful:
    //  00 = "just add"  (lw, sw address arithmetic)
    //  01 = "subtract"  (all six branches - a subtract is what sets the flags
    //                    that Branch_Condition.v then interprets. Note this is
    //                    the same for bltu as for beq: one subtraction produces
    //                    every comparison at once.)
    //  10 = "look at funct3/funct7"  (R-type AND I-type ALU ops)
    //
    //FIX: OP-IMM (0010011) used to get 00, so andi/ori/slti all executed as
    //addi. It now shares 10 with R-type, since funct3 means the same thing in
    //both. The one trap is add vs sub: an I-type has no funct7, and instr[30]
    //is just an immediate bit (set for any negative imm, e.g. addi x1,x1,-2).
    //ALU_decoder only picks sub when {op5,funct7} == 11, and op5 is 0 for
    //OP-IMM, so addi can never turn into sub. That is exactly why op5 is wired
    //into ALU_decoder in the first place.
    assign ALUOp = ((op == 7'b0110011) | (op == 7'b0010011)) ? 2'b10 :
                   (op == 7'b1100011) ? 2'b01 : 2'b00;

endmodule
