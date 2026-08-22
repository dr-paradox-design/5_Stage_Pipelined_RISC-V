//=============================================================================
// Execute_Cycle.v  -  STAGE 3 of 5  (EX)
//=============================================================================
//
// WHAT THIS STAGE DOES
//   Two independent calculations happen here, in parallel:
//     1. The ALU does the instruction's actual arithmetic/logic work.
//     2. A dedicated adder computes the branch target address PC + immediate.
//   It also makes the ONE decision in this whole core that reaches backwards:
//   whether a branch is taken.
//
// WHY THE BRANCH ADDER LIVES HERE AND NOT IN FETCH
//   In the single-cycle core, Branch_Adder sat next to the PC because
//   everything happened at once. In a pipeline it cannot: the branch target is
//   PC + immediate, and the immediate does not exist until Sign_Extend runs in
//   DECODE. So the adder had to move at least as far down as ID. It is placed
//   in EX rather than ID for a practical reason - EX is where the branch
//   condition is resolved, so keeping the target and the decision in the same
//   stage means only ONE backward bundle (PCSrcE + PCTargetE) has to be routed
//   up to fetch instead of two signals from two different stages.
//
// THE BRANCH DECISION - THE OTHER HALF OF A SPLIT AND GATE
//   Decode_Cycle.v produced BranchE = "this instruction is a branch opcode",
//   deliberately WITHOUT the condition test (read the .zero(1'b1) comment in
//   that file - it explains why). The missing half is completed here:
//
//        PCSrcE = BranchE & ZeroE
//
//   ZeroE is the ALU's zero flag from THIS cycle, testing rs1 - rs2 == 0.
//   BranchE is a control bit that has travelled one pipeline register from ID.
//   Both belong to the same instruction, so ANDing them is exactly the single-
//   cycle equation - just evaluated one stage later.
//
// THE COST OF DECIDING THIS LATE  (the "branch delay slot")
//   PCSrcE only becomes valid while the branch sits in EX. By then fetch has
//   already read the two instructions that physically follow the branch in
//   memory, and they are sitting in IF/ID and ID/EX. A real pipeline kills them
//   with flush logic. This build has NO flush logic, so those two instructions
//   WILL execute. That is not an accident - it is the documented behaviour of
//   this stage of the project, and src/program.hex puts two NOPs after every
//   taken branch so that what executes is harmless.
//=============================================================================

module Execute_Cycle (
    input  wire        clk,
    input  wire        rst,          // ACTIVE-LOW

    // ---- forward path in, from the ID/EX register -------------------------
    input  wire        RegWriteE,
    input  wire        ALUSrcE,
    input  wire        MemWriteE,
    input  wire        ResultSrcE,
    input  wire        BranchE,      // raw branch-opcode bit (NOT "taken")
    input  wire [2:0]  ALUControlE,
    input  wire [31:0] RD1E,
    input  wire [31:0] RD2E,
    input  wire [31:0] ImmExtE,
    input  wire [31:0] PCE,
    input  wire [4:0]  RdE,

    // ---- backward path out, to the fetch stage ----------------------------
    output wire        PCSrcE,       // 1 = redirect the PC now
    output wire [31:0] PCTargetE,    // ...to here

    // ---- forward path out, into memory (outputs of the EX/MEM register) ---
    output reg         RegWriteM,
    output reg         MemWriteM,
    output reg         ResultSrcM,
    output reg  [31:0] ALU_ResultM,  // address for a load/store, or the result
    output reg  [31:0] WriteDataM,   // value a store will write
    output reg  [4:0]  RdM
);

    //-------------------------------------------------------------------------
    // Combinational signals inside the execute stage. All carry the "E" suffix.
    //-------------------------------------------------------------------------
    wire [31:0] SrcBE;        // second ALU operand after the ALUSrc mux
    wire [31:0] ALU_ResultE;
    wire        ZeroE;        // ALU flag: result was all zeros
    wire        NE, CE, VE;   // negative / carry / overflow - unused, see below

    //-------------------------------------------------------------------------
    // ALU SOURCE-B MUX
    //
    // Byte-for-byte the same mux as the single-cycle core:
    //   ALUSrcE = 0 -> operand B is the rs2 register value  (R-type, beq)
    //   ALUSrcE = 1 -> operand B is the immediate           (addi, lw, sw)
    // The only difference is the E suffix, i.e. the select bit arrived through
    // a pipeline register rather than straight off the decoder.
    //-------------------------------------------------------------------------
    assign SrcBE = ALUSrcE ? ImmExtE : RD2E;

    //-------------------------------------------------------------------------
    // BRANCH DECISION
    //
    // For beq the ALU is told to SUBTRACT, so ZeroE is high exactly when
    // rs1 == rs2. BranchE gates that so a non-branch instruction which happens
    // to produce a zero result (say  sub x4, x1, x1 ) cannot hijack the PC.
    //
    // Both terms describe the SAME instruction: BranchE came down the pipe with
    // it, ZeroE is being produced for it right now.
    //-------------------------------------------------------------------------
    assign PCSrcE = BranchE & ZeroE;

    //-------------------------------------------------------------------------
    // BRANCH TARGET ADDER
    //
    // PCE is this branch's OWN address, faithfully carried IF -> ID -> EX for
    // exactly this moment. RISC-V branch offsets are relative to the branch
    // instruction itself, and Sign_Extend already did the B-type bit
    // unscrambling and the implicit <<1, so this is a plain 32-bit add.
    //
    // Same PC_Adder module as the fetch stage uses for PC+4 - it is a generic
    // adder, instanced twice with different operands.
    //-------------------------------------------------------------------------
    PC_Adder Branch_Adder (
        .a (PCE),
        .b (ImmExtE),
        .c (PCTargetE)
    );

    //-------------------------------------------------------------------------
    // ALU
    //
    // Reused unmodified from single_core/. N, C and V are brought out because
    // the module has those ports, but nothing in this core consumes them - only
    // Z matters, and only for beq. They are left unconnected-but-named rather
    // than blank so that a waveform dump still shows them, which is handy when
    // debugging an arithmetic instruction.
    //-------------------------------------------------------------------------
    ALU ALU (
        .A          (RD1E),
        .B          (SrcBE),
        .ALUControl (ALUControlE),
        .Result     (ALU_ResultE),
        .Z          (ZeroE),
        .N          (NE),
        .C          (CE),
        .V          (VE)
    );

    //=========================================================================
    // EX/MEM PIPELINE REGISTER
    //
    // WHAT SURVIVES THIS BOUNDARY AND WHAT DIES HERE
    //   Dies:  ALUSrcE      - the mux it controlled already ran, above.
    //          BranchE      - already consumed by the PCSrcE AND gate.
    //          ALUControlE  - the ALU already ran.
    //          ImmExtE      - both of its consumers (SrcB mux, branch adder)
    //                         were in this stage.
    //          PCE          - the branch adder was its last customer.
    //          RD1E         - it went into the ALU and is never needed again.
    //   Survives: the three control bits that later stages still need, plus the
    //          ALU result, the store data, and the destination register number.
    //
    //   Notice how the bundle gets NARROWER every stage. That is normal and
    //   healthy - each pipeline register should carry only what is genuinely
    //   still in flight. A pipeline register that carries a signal nobody reads
    //   is pure area and power for nothing.
    //
    // WHY RD2E BECOMES "WriteDataM" RATHER THAN KEEPING ITS NAME
    //   For a store, rs2 is the value being written to memory. It skipped the
    //   ALU entirely (the ALU was busy computing base + offset, the ADDRESS).
    //   Renaming it at this boundary documents the role it is about to play.
    //=========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            RegWriteM   <= 1'b0;
            MemWriteM   <= 1'b0;
            ResultSrcM  <= 1'b0;
            ALU_ResultM <= 32'h00000000;
            WriteDataM  <= 32'h00000000;
            RdM         <= 5'b00000;
        end
        else begin
            RegWriteM   <= RegWriteE;
            MemWriteM   <= MemWriteE;
            ResultSrcM  <= ResultSrcE;
            ALU_ResultM <= ALU_ResultE;   // load/store address, or the answer
            WriteDataM  <= RD2E;          // rs2, the value a store writes
            RdM         <= RdE;
        end
    end

endmodule
