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
//
// FORWARDING - WHY THIS STAGE, OF ALL OF THEM, NEEDS IT
//   The ALU here needs rs1/rs2 values that may not have reached the register
//   file yet, because the instruction that PRODUCES them is still sitting in
//   MEM or WB - up to 3 stages behind where it was written, 0-2 stages ahead
//   of retiring. Without help, this stage would simply read the STALE value
//   RD1E/RD2E fetched back in ID and get the wrong answer.
//
//   The fix is not to wait - it is to notice that the correct value already
//   exists somewhere on-chip, just not yet in the register file, and reach out
//   and grab it directly off the EX/MEM or MEM/WB wires. That reaching-out is
//   "forwarding" (also called "bypassing" - it bypasses the register file).
//   See the FORWARDING UNIT block below for the actual comparison logic, and
//   see Decode_Cycle.v for why Rs1E/Rs2E (register NUMBERS) had to be added to
//   the ID/EX register to make the comparison possible at all.
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
    input  wire [4:0]  Rs1E,       // rs1 register NUMBER - for forwarding compare
    input  wire [4:0]  Rs2E,       // rs2 register NUMBER - for forwarding compare

    // ---- forwarding path in, from the WRITE-BACK stage ---------------------
    // The EX/MEM-stage identity (RegWriteM/RdM/ALU_ResultM) never needs to
    // arrive as an input - it already exists inside THIS module as the EX/MEM
    // register's own present value (see the FORWARDING UNIT comment below).
    // The MEM/WB-stage identity lives two modules away, so it has to be piped
    // in explicitly.
    input  wire        RegWriteW,   // does the instruction in WB write a reg?
    input  wire [4:0]  RdW,         // which register
    input  wire [31:0] ResultW,     // the value it is writing

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

    //=========================================================================
    // FORWARDING UNIT
    //
    // For each ALU operand, decide where its true value actually lives right
    // now: the register file (no hazard), the EX/MEM register (a hazard with
    // the instruction directly ahead), or the MEM/WB register (a hazard with
    // the instruction two ahead).
    //
    // WHY EX/MEM's IDENTITY NEEDS NO INPUT PORT
    //   RegWriteM and RdM are declared below as `output reg` - they are the
    //   EX/MEM pipeline register's OWN storage. Their value right now, before
    //   this clock edge, is whatever was latched on the PREVIOUS edge - i.e.
    //   they already describe the instruction currently sitting in MEM, which
    //   is exactly the producer we need to check against. Comparing against
    //   our own output regs mid-cycle is legal precisely because this is
    //   combinational logic reading registered state, not a race.
    //
    // WHY EX/MEM OUTRANKS MEM/WB WHEN BOTH MATCH
    //   If the instructions in BOTH MEM and WB wrote the same destination
    //   register (only possible if that register was written twice in three
    //   instructions), the one in MEM is the MORE RECENT write - it happened
    //   one cycle later in program order. Forwarding must always prefer the
    //   freshest value, so the EX/MEM check is written first and the MEM/WB
    //   check only fires in the `else` branch.
    //
    // WHY "!= 5'b0" IS NOT OPTIONAL
    //   x0 is hardwired to zero and is never actually written (RegWrite is low
    //   for anything targeting it in a well-formed program, but Rs1E/Rs2E also
    //   read as 0 for any instruction whose encoding simply doesn't use that
    //   operand - e.g. addi's unused rs2 field). Without this guard, two
    //   completely unrelated instructions that both happen to have a zero
    //   field would be treated as a false hazard and forward garbage.
    //
    // ENCODING
    //   2'b00 = no hazard, use the ID-stage value (RD1E / RD2E)
    //   2'b10 = forward from EX/MEM (ALU_ResultM)
    //   2'b01 = forward from MEM/WB (ResultW)
    //=========================================================================
    reg [1:0] ForwardAE, ForwardBE;

    always @(*) begin
        // ---- operand A: rs1 ----
        if (RegWriteM && (RdM != 5'b00000) && (RdM == Rs1E))
            ForwardAE = 2'b10;
        else if (RegWriteW && (RdW != 5'b00000) && (RdW == Rs1E))
            ForwardAE = 2'b01;
        else
            ForwardAE = 2'b00;

        // ---- operand B: rs2 ----
        if (RegWriteM && (RdM != 5'b00000) && (RdM == Rs2E))
            ForwardBE = 2'b10;
        else if (RegWriteW && (RdW != 5'b00000) && (RdW == Rs2E))
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    //-------------------------------------------------------------------------
    // FORWARDING MUXES
    //
    // SrcAE replaces the old direct use of RD1E as the ALU's A operand.
    // ForwardedRD2E replaces RD2E EVERYWHERE RD2E used to be used below -
    // both as the ALU's B-operand candidate AND as the value latched into
    // WriteDataM for a store. Missing the second one is a classic bug: a
    // `sw` right after the instruction that computed the value it stores
    // would silently store the stale register-file value instead of the
    // freshly forwarded one.
    //-------------------------------------------------------------------------
    wire [31:0] SrcAE;
    wire [31:0] ForwardedRD2E;

    assign SrcAE = (ForwardAE == 2'b10) ? ALU_ResultM :
                   (ForwardAE == 2'b01) ? ResultW     :
                                          RD1E;

    assign ForwardedRD2E = (ForwardBE == 2'b10) ? ALU_ResultM :
                            (ForwardBE == 2'b01) ? ResultW     :
                                                   RD2E;

    //-------------------------------------------------------------------------
    // ALU SOURCE-B MUX
    //
    // Same role as the single-cycle core's mux:
    //   ALUSrcE = 0 -> operand B is the rs2 register value  (R-type, beq)
    //   ALUSrcE = 1 -> operand B is the immediate           (addi, lw, sw)
    // The one change from the pre-forwarding version of this file is that the
    // rs2 side now reads ForwardedRD2E instead of the raw, possibly-stale
    // RD2E - a branch's rs2 gets the benefit of forwarding exactly the same
    // way an ALU instruction's does, with no special-case code, because this
    // mux and the forwarding unit above do not know or care what opcode they
    // are serving.
    //-------------------------------------------------------------------------
    assign SrcBE = ALUSrcE ? ImmExtE : ForwardedRD2E;

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
    //
    // .A is SrcAE, NOT the raw RD1E - this is the forwarding mux's only
    // customer for operand A. Every instruction's rs1, including a branch's,
    // passes through it.
    //-------------------------------------------------------------------------
    ALU ALU (
        .A          (SrcAE),
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
    //          RD1E, RD2E   - both went into the ALU/forwarding muxes above
    //                         (as SrcAE / ForwardedRD2E) and are never needed
    //                         again in their raw form.
    //          Rs1E, Rs2E   - only existed so THIS stage's forwarding unit
    //                         could compare against RdM/RdW. Nothing beyond
    //                         EX ever forwards into an ALU operand, so these
    //                         register NUMBERS have done their one job.
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
    //
    // WHY WriteDataM LATCHES ForwardedRD2E, NOT RD2E
    //   A store's data operand needs forwarding exactly like an ALU operand
    //   does - e.g. `add x3,x1,x2` immediately followed by `sw x3,0(x0)` must
    //   store the value ADD just computed, not whatever stale value happened
    //   to be sitting in the register file for x3. Latching the already-
    //   forwarded wire here is what makes that work; latching raw RD2E would
    //   silently reintroduce the exact hazard forwarding exists to remove.
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
            WriteDataM  <= ForwardedRD2E; // rs2, AFTER forwarding - see note above
            RdM         <= RdE;
        end
    end

endmodule
