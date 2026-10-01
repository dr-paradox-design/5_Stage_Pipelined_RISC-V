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
//   deliberately WITHOUT the condition test, because the ALU flags the test
//   needs do not exist until this stage. The missing half is completed here:
//
//        PCSrcE = BranchE & BranchTakenE
//
//   BranchE is a control bit that travelled one pipeline register from ID.
//   BranchTakenE is produced RIGHT NOW by Branch_Condition, which reads funct3E
//   (also piped down from ID) and the ALU's four condition flags to evaluate
//   whichever of the six comparisons this branch actually asked for. Both terms
//   describe the same instruction, so ANDing them is exactly the single-cycle
//   equation - just evaluated one stage later.
//
//   This is where all six RV32I branches live: beq, bne, blt, bge, bltu, bgeu.
//   Until Branch_Condition existed, the right-hand term was the bare ZeroE flag
//   and the core could only really do beq - the other five decoded as branches
//   but silently behaved like beq.
//
// THE COST OF DECIDING THIS LATE
//   PCSrcE only becomes valid while the branch sits in EX. By then fetch has
//   already read the two instructions that physically follow the branch in
//   memory, and they are sitting in IF/ID and ID/EX.
//
//   PCSrcE therefore has a SECOND consumer besides the PC mux in Fetch: the
//   Hazard_Unit, which turns it into FlushD and FlushE and wipes both of those
//   wrong-path instructions out at the same clock edge that redirects the PC.
//   src/program.hex used to carry two hand-written NOPs after every taken
//   branch to make them harmless; that workaround is gone.
//
//   The two cycles themselves are NOT recovered - the pipe is simply two
//   instructions emptier for a moment. Flushing buys correctness, not speed.
//   Recovering the cycles needs branch prediction, which this core lacks.
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
    input  wire [1:0]  ALUSrcAE,     // ALU operand A: 00 rs1, 01 PC (auipc), 10 zero (lui)
    input  wire        MemWriteE,
    input  wire        ResultSrcE,
    input  wire        BranchE,      // raw branch-opcode bit (NOT "taken")
    input  wire        JumpE,        // jal/jalr: unconditional redirect
    input  wire        JalrE,        // jalr: target = (rs1 + imm) & ~1, from the ALU
    input  wire [2:0]  funct3E,      // WHICH branch comparison: beq/bne/blt/...
    input  wire [3:0]  ALUControlE,
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
    output reg  [4:0]  RdM,
    output reg  [2:0]  funct3M       // load/store WIDTH (b/h/w, signed/unsigned) for MEM
);

    //-------------------------------------------------------------------------
    // Combinational signals inside the execute stage. All carry the "E" suffix.
    //-------------------------------------------------------------------------
    wire [31:0] SrcBE;        // second ALU operand after the ALUSrc mux
    wire [31:0] ALU_ResultE;
    wire [31:0] PCRelTargetE; // PC + imm   (branches, jal)
    wire [31:0] PCPlus4E;     // link value (jal, jalr)
    wire [31:0] ExResultE;    // what EX hands to MEM: ALU result or link value
    wire        ZeroE;        // ALU flag: result was all zeros
    wire        NE, CE, VE;   // negative / carry / overflow - ALL now consumed
    wire        BranchTakenE; // Branch_Condition's verdict on funct3E + flags

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
    // THE ASSUMPTION THIS UNIT MAKES, AND WHO GUARANTEES IT
    //   Look at what the 2'b10 case forwards: ALU_ResultM. For an ALU
    //   instruction that is the answer, and forwarding it is correct. But if
    //   the instruction sitting in MEM is a LOAD, ALU_ResultM is the ADDRESS
    //   the load is reading from - the data has not come back from memory yet
    //   and will not exist until the edge that ends this cycle.
    //
    //   Nothing in the code below checks for that. Forwarding an address where
    //   data was wanted would be a silent, extremely confusing bug - and this
    //   unit, on its own, would commit it happily.
    //
    //   It never gets the chance, because Hazard_Unit.v detects exactly that
    //   situation one stage earlier (a load in EX with a dependent instruction
    //   in ID) and stalls for one cycle. By the time the dependent instruction
    //   reaches EX, the load has moved on to WB, so the match here is against
    //   RdW and the forwarded value is ResultW - which for a load is the data
    //   read out of memory, correctly selected by the write-back mux.
    //
    //   In other words the 2'b10 path is only ever reachable when the producer
    //   in MEM is an ALU instruction. That is a real invariant maintained by
    //   another module, not a property of this code, so it is written down
    //   here: if the hazard unit is ever removed or its lwStall condition
    //   weakened, THIS is the line that silently starts producing wrong
    //   answers.
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
    wire [31:0] ForwardedRD1E;
    wire [31:0] ForwardedRD2E;

    assign ForwardedRD1E = (ForwardAE == 2'b10) ? ALU_ResultM :
                           (ForwardAE == 2'b01) ? ResultW     :
                                                  RD1E;

    // Operand-A select, AFTER forwarding. lui/auipc have no rs1: bits [19:15]
    // are part of their immediate, so the forwarding unit may "match" them
    // against RdM/RdW by accident. Selecting PC or 0 here throws that bogus
    // forward away, which is why this mux sits after the forwarding mux and
    // not before it.
    assign SrcAE = (ALUSrcAE == 2'b01) ? PCE          :
                   (ALUSrcAE == 2'b10) ? 32'h00000000 :
                                         ForwardedRD1E;

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

    //=========================================================================
    // BRANCH DECISION  -  all six RV32I conditional branches
    //
    // This used to be  `PCSrcE = BranchE & ZeroE`, which implemented exactly
    // one instruction: beq. Because the old decoder never looked at funct3,
    // bne/blt/bge/bltu/bgeu were decoded as branches, subtracted like beq, and
    // then tested against the zero flag - so all five of them executed AS beq.
    // bne, in particular, branched when its operands were EQUAL: the precise
    // opposite of what it means. Silent, and the nastiest kind of wrong.
    //
    // The fix is to keep the same two-term structure but upgrade the right-hand
    // term from one flag to a funct3-selected function of all four flags:
    //
    //     BranchE      "this instruction is a B-type branch"   - from ID
    //     BranchTakenE "the comparison funct3E names is TRUE"  - computed now
    //
    // BranchE remains essential as a gate. Every instruction sets flags, so an
    // ordinary `sub x4, x1, x1` produces Z=1 and would otherwise look exactly
    // like a satisfied beq and hijack the PC.
    //
    // WHY THIS COST NO NEW ARITHMETIC
    //   The ALU has always computed N, C and V alongside Z; this file used to
    //   declare them and leave them dangling (the old comment here literally
    //   said "nothing in this core consumes them"). A subtractor that sets
    //   flags is already a complete comparator - signed, unsigned, and equality
    //   all fall out of the same subtraction. Going from one branch instruction
    //   to six therefore added a 6-way mux and not one gate of datapath. See
    //   Branch_Condition.v for the derivation, especially why signed less-than
    //   is N^V rather than N alone.
    //
    // STILL THE SAME STAGE, STILL THE SAME 2-CYCLE PENALTY
    //   The decision is made in EX exactly as before, so the flush machinery
    //   downstream of PCSrcE is untouched and a taken branch still costs two
    //   flushed cycles. The core now branches on more CONDITIONS, not sooner.
    //
    // WHY funct3E HAD TO BE PIPELINED TO GET HERE
    //   funct3 is an instruction field, and the instruction word itself is long
    //   gone - InstrD was consumed in ID and never travels past the ID/EX
    //   register (see the comment on that register in Decode_Cycle.v). Any
    //   instruction bits a later stage needs must be carried explicitly. The
    //   branch condition is the first thing in this core to need a raw ISA
    //   field this far down the pipe.
    //=========================================================================
    Branch_Condition Branch_Condition (
        .funct3      (funct3E),
        .Z           (ZeroE),
        .N           (NE),
        .C           (CE),
        .V           (VE),
        .BranchTaken (BranchTakenE)
    );

    // A jump is a branch whose condition is always true.
    assign PCSrcE = (BranchE & BranchTakenE) | JumpE;

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
        .c (PCRelTargetE)
    );

    // Redirect target. Branches and jal are PC-relative (the adder above).
    // jalr is register-relative: the ALU has already computed rs1 + imm with
    // rs1 FORWARDED, so `jalr x0, 0(x1)` right after the instruction that
    // wrote x1 still returns to the right place. The ISA then clears bit 0.
    assign PCTargetE = JalrE ? {ALU_ResultE[31:1], 1'b0} : PCRelTargetE;

    // LINK VALUE. jal/jalr write PC+4 to rd. Instead of adding a third input to
    // the write-back mux (and a PC+4 field to two more pipeline registers), it
    // replaces the ALU result right here. From EX/MEM on, a jump looks exactly
    // like an ALU instruction - so EX/MEM forwarding, MEM/WB forwarding, the
    // decode bypass and write-back all handle the link register for free.
    PC_Adder Link_Adder (
        .a (PCE),
        .b (32'h00000004),
        .c (PCPlus4E)
    );
    assign ExResultE = JumpE ? PCPlus4E : ALU_ResultE;

    //-------------------------------------------------------------------------
    // ALU
    //
    // Reused unmodified from single_core/. ALL FOUR condition flags are now
    // consumed: Z, N, C and V all feed Branch_Condition above. They used to be
    // brought out only so a waveform dump would show them, with a comment
    // explaining that nothing read them. Widening the branch set is what
    // finally gave three of them a job - without changing a line of ALU.v,
    // because the flags were correct all along and merely unused.
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
    //          funct3E      - Branch_Condition was its only downstream reader,
    //                         and it just ran. (If this core ever gains lb/lh/
    //                         sb/sh, funct3 would suddenly need to survive to
    //                         MEM as well, since it is what distinguishes the
    //                         access widths. It goes in the ID/EX register the
    //                         day those instructions do.)
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
            funct3M     <= 3'b000;
        end
        else begin
            RegWriteM   <= RegWriteE;
            MemWriteM   <= MemWriteE;
            ResultSrcM  <= ResultSrcE;
            ALU_ResultM <= ExResultE;     // load/store address, the answer, or PC+4 for a jump
            WriteDataM  <= ForwardedRD2E; // rs2, AFTER forwarding - see note above
            RdM         <= RdE;
            funct3M     <= funct3E;     // same field branches use; MEM reads it as the access width
        end
    end

endmodule
