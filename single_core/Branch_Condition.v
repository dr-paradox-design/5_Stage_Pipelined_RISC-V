//=============================================================================
// Branch_Condition.v  -  decides whether a branch is TAKEN
//=============================================================================
//
// WHY THIS MODULE EXISTS AT ALL
//   Before this file, the whole branch decision was one AND gate buried inside
//   main_decoder.v:
//
//        assign PCSrc = branch & zero;
//
//   That is correct for exactly ONE instruction - beq - and silently wrong for
//   the other five. RV32I has six conditional branches, all sharing opcode
//   1100011 and distinguished ONLY by funct3:
//
//        funct3   mnemonic   taken when
//        ------   --------   --------------------------------
//        000      beq        rs1 == rs2
//        001      bne        rs1 != rs2
//        100      blt        rs1 <  rs2   (signed)
//        101      bge        rs1 >= rs2   (signed)
//        110      bltu       rs1 <  rs2   (unsigned)
//        111      bgeu       rs1 >= rs2   (unsigned)
//        010,011             reserved - not encodings of anything
//
//   The old decoder never looked at funct3, so `bne x1, x2, L` was decoded as a
//   branch, given ALUOp=01 (subtract), and then tested with `zero`. It branched
//   when the registers were EQUAL. It executed as beq. No error, no warning,
//   just the opposite behaviour - which is the worst failure mode a processor
//   can have. Fixing that is the entire purpose of this module.
//
//=============================================================================
// THE KEY INSIGHT: THE ALU ALREADY KNEW THE ANSWER
//
//   No new arithmetic happens here. Not one adder, not one comparator. Every
//   one of the six conditions is a function of the four condition flags the ALU
//   ALREADY produces as a side effect of computing rs1 - rs2, and which this
//   design has been throwing away since the day it was written. Look at the
//   port list in ALU.v: Z, N, C, V have always been there. In Single_Cycle_Top
//   three of them were wired to `.N(), .C(), .V()` - literally connected to
//   nothing. This module is what finally uses them.
//
//   That is why widening from one branch to six costs zero extra ALU hardware:
//   a subtractor that sets flags is already a full comparator. Deriving the
//   comparisons is the classic bit of computer arithmetic worth doing once by
//   hand, so here it is in full.
//
//   Throughout, the ALU has been told ALUControl = 001 (subtract), so:
//        {C, sum} = A + ~B + 1        i.e.  sum = A - B  in 33-bit arithmetic
//        Z = (sum == 0)
//        N = sum[31]
//        C = carry-out of that 33-bit add
//        V = signed overflow of the subtraction
//
//   EQUALITY  (beq / bne)
//     A - B == 0  if and only if  A == B. So Z is literally the equality test,
//     and inequality is ~Z. This is the case the old hardware handled, and the
//     only one it handled.
//
//   UNSIGNED COMPARE  (bltu / bgeu)  -> C
//     In two's-complement subtraction the carry-out is the NOT-BORROW flag.
//     Compute A + ~B + 1 over 33 bits: the result is 2^32 + A - B, so bit 32
//     (the carry-out) is 1 exactly when A - B >= 0 as unsigned integers, i.e.
//     when A >= B, and 0 when the subtraction had to borrow. Hence:
//        bgeu  taken when  C == 1
//        bltu  taken when  C == 0
//     Note this is a genuinely different question from the signed one: with
//     A = 0x00000001 and B = 0xFFFFFFFF, unsigned says 1 < 4294967295 (bltu
//     taken), signed says 1 > -1 (blt not taken). Same bits, opposite answers.
//     That is exactly why the ISA has both.
//
//   SIGNED COMPARE  (blt / bge)  ->  N ^ V
//     The naive test "is the result negative?" (just N) is wrong, and wrong in
//     a way that is easy to ship: it fails precisely when the subtraction
//     overflows. Example, with 32-bit values:
//        A = -2147483648 (0x80000000),  B = 1
//        true answer: A < B, so blt should be TAKEN
//        but A - B = 0x7FFFFFFF, whose sign bit is 0, so N = 0 -> "not less".
//     The subtraction overflowed the signed range and the sign bit lies.
//
//     V is set exactly when that happens, so XORing it back in repairs the
//     sign:
//        no overflow (V=0): the sign bit is trustworthy      -> use N
//        overflow    (V=1): the sign bit is inverted from truth -> use ~N
//     which is precisely N ^ V. In the example above N=0, V=1, so N^V = 1 and
//     blt is correctly taken.
//
//        blt   taken when  (N ^ V) == 1
//        bge   taken when  (N ^ V) == 0
//
//     This is worth flagging because the ALU's own `slt` operation does NOT do
//     this - ALU.v computes  slt = {31'b0, sum[31]}, the sign bit alone, with
//     no V correction. So the existing slt instruction is subtly wrong on
//     signed overflow while blt implemented here is right. That inconsistency
//     is real and is noted as a known issue rather than quietly papered over;
//     fixing slt means touching ALU.v's result mux and is a separate change.
//
//=============================================================================
// WHY THE CONDITION IS EVALUATED HERE AND NOT IN THE DECODER
//
//   A decoder should decode. Given an instruction it can say "this is a
//   branch, and here is which comparison it wants" - both are pure functions of
//   the instruction bits. It CANNOT say whether the branch is taken, because
//   that depends on the operand values, which do not exist until the ALU runs.
//
//   In the single-cycle core that distinction was invisible: everything happened
//   in one clock period, so the decoder could reach over and grab the zero flag.
//   In the PIPELINE it is not invisible at all - decode happens in ID and the
//   flags do not exist until EX, one cycle later. The old code papered over this
//   by passing `.zero(1'b1)` into the decoder from Decode_Cycle.v to neutralise
//   the AND gate, then redoing the AND in Execute_Cycle.v.
//
//   Splitting the module this way removes that hack. The decoder now emits a
//   raw "is a branch" bit and nothing else; this module evaluates the condition
//   wherever the flags happen to be available. Both cores instantiate it - the
//   single-cycle core next to its ALU, the pipeline inside Execute_Cycle.v -
//   and both get identical branch semantics from identical logic, which is the
//   property that keeps the two cores from drifting apart.
//
// PURELY COMBINATIONAL, AND DELIBERATELY TINY
//   Six one-bit expressions behind a 3-bit mux. It adds a couple of gate delays
//   to a path that already contains a 32-bit adder, so it is nowhere near the
//   critical path.
//=============================================================================

module Branch_Condition (
    input  wire [2:0] funct3,       // bits [14:12] of the branch instruction
    input  wire       Z,            // ALU flag: result == 0     (rs1 == rs2)
    input  wire       N,            // ALU flag: result[31]      (raw sign bit)
    input  wire       C,            // ALU flag: carry-out = NOT borrow
    input  wire       V,            // ALU flag: signed overflow
    output reg        BranchTaken   // 1 = the condition holds
);

    //-------------------------------------------------------------------------
    // THE CONDITION MUX
    //
    // Reading the funct3 encoding as a pattern rather than a lookup table makes
    // it much easier to remember, and shows the ISA designers were not picking
    // numbers at random:
    //
    //     funct3[2] = 0 -> equality test        (beq, bne)
    //     funct3[2] = 1 -> magnitude test       (blt, bge, bltu, bgeu)
    //     funct3[1] = 0 -> signed  magnitude    (blt, bge)
    //     funct3[1] = 1 -> unsigned magnitude   (bltu, bgeu)
    //     funct3[0] = 0 -> "the interesting one"    (beq, blt, bltu)
    //     funct3[0] = 1 -> its exact negation       (bne, bge, bgeu)
    //
    // That last bit is the useful one: every odd funct3 is the complement of
    // the even one below it. Which is why RV32I has no bgt or ble - you write
    // `blt rs2, rs1` and swap the operands. Two fewer opcodes for free.
    //
    // The logic below is written as an explicit case for readability, but a
    // synthesiser will collapse it into roughly "pick one of {Z, N^V, C} with
    // funct3[2:1], then conditionally invert with funct3[0]".
    //-------------------------------------------------------------------------
    always @(*) begin
        case (funct3)
            3'b000:  BranchTaken =  Z;         // beq   rs1 == rs2
            3'b001:  BranchTaken = ~Z;         // bne   rs1 != rs2
            3'b100:  BranchTaken =  (N ^ V);   // blt   rs1 <  rs2  signed
            3'b101:  BranchTaken = ~(N ^ V);   // bge   rs1 >= rs2  signed
            3'b110:  BranchTaken = ~C;         // bltu  rs1 <  rs2  unsigned
            3'b111:  BranchTaken =  C;         // bgeu  rs1 >= rs2  unsigned

            // funct3 = 010 and 011 are not branch encodings in RV32I. A real
            // implementation raises an illegal-instruction exception here; this
            // core has no exception support yet, so the safe fallback is "do
            // not branch". Never taking an undefined branch at least keeps
            // execution on a predictable path instead of jumping somewhere
            // computed from garbage.
            default: BranchTaken = 1'b0;
        endcase
    end

endmodule
