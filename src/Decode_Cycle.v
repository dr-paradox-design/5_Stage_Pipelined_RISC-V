//=============================================================================
// Decode_Cycle.v  -  STAGE 2 of 5  (ID)
//=============================================================================
//
// WHAT THIS STAGE DOES
//   Takes the 32-bit instruction word that fetch handed over and turns it into
//   three things:
//     1. CONTROL SIGNALS  - "what should the later stages do with this?"
//     2. OPERANDS         - the two register values rs1 and rs2 read out of the
//                           register file
//     3. THE IMMEDIATE    - the constant baked into the instruction, sign
//                           extended to 32 bits
//   All three are then latched into the ID/EX register at the bottom of the
//   file and travel downstream together, in lock-step with the instruction they
//   belong to.
//
// THE BIG IDEA: CONTROL SIGNALS ARE PIPELINED DATA
//   This is the part that surprises people coming from the single-cycle core.
//   There, Control_Unit_Top's outputs went straight to the units that used
//   them, because everything happened in one clock period.
//
//   Here, MemWrite is decoded in ID but the data memory does not run until MEM,
//   three cycles later. If we wired the decoder's MemWrite straight to the data
//   memory, the memory would see the MemWrite of whatever instruction happens to
//   be sitting in DECODE at that moment - not the store that actually wants to
//   write. Total chaos.
//
//   So control signals get carried through the SAME pipeline registers as the
//   data. MemWriteE is delayed one cycle to become MemWriteM. RegWrite has to
//   survive the longest journey of all: decoded in ID, used in WB, so it rides
//   through three registers as RegWriteE -> RegWriteM -> RegWriteW.
//
//   Mental model: each instruction drags a little backpack of control bits down
//   the pipe with it, and each stage reaches into the backpack for the bits it
//   needs right now.
//
// THE WRITE-BACK PORT COMES BACKWARDS
//   The register file physically lives in this stage, but the WRITE side of it
//   is driven from the write-back stage (RegWriteW / RdW / ResultW). That is
//   why the register file straddles ID and WB in every textbook pipeline
//   diagram - it is one piece of hardware read by one stage and written by
//   another, four cycles apart.
//
// RS1E / RS2E - REGISTER NUMBERS, CARRIED PURELY SO EXECUTE CAN FORWARD
//   RD1D/RD2D above are the register VALUES read this cycle. Execute_Cycle.v
//   also needs the register NUMBERS (rs1, rs2) themselves, because forwarding
//   works by comparing "which register does EX still need?" against "which
//   register did MEM or WB just finish computing?" (RdM / RdW). That
//   comparison cannot be done with values - only numbers identify WHICH
//   register a value belongs to. So Rs1E/Rs2E ride the pipe purely as
//   identifiers; RD1E/RD2E ride alongside them as the (possibly stale) values
//   that forwarding will override if a hazard is detected downstream.
//
// THE DECODE-STAGE WRITE-THROUGH BYPASS  (closes the "distance 3" hole)
//   See the long comment on the register file below. In short: EX-stage
//   forwarding reaches producers 1 and 2 instructions back, and a plain
//   register-file read is safe for producers 4 or more instructions back.
//   A producer EXACTLY 3 back falls between the two and used to read stale
//   data. The two-line bypass below fixes it, here in ID, without modifying
//   the shared/frozen single_core/Register_file.v.
//
// HAZARD COVERAGE AFTER THIS FILE, EXECUTE_CYCLE.V AND HAZARD_UNIT.V
//   distance 1  -> EX/MEM forwarding        (Execute_Cycle.v)   0 cycles
//   distance 2  -> MEM/WB forwarding        (Execute_Cycle.v)   0 cycles
//   distance 3  -> decode write-through     (this file)         0 cycles
//   distance 4+ -> plain register-file read (already committed) 0 cycles
//   load-use    -> stall 1, then distance 2 (Hazard_Unit.v)     1 cycle
//   taken branch-> flush IF/ID and ID/EX    (Hazard_Unit.v)     2 cycles
//   That is every hazard this ISA subset can produce. WAR and WAW cannot
//   occur in a strictly in-order pipeline - see Hazard_Unit.v for why.
//=============================================================================

module Decode_Cycle (
    input  wire        clk,
    input  wire        rst,          // ACTIVE-LOW

    // ---- forward path in, from the IF/ID register -------------------------
    input  wire [31:0] InstrD,       // instruction to decode
    input  wire [31:0] PCD,          // address it was fetched from

    // ---- backward path in, from the write-back stage ----------------------
    // These three drive the WRITE port of the register file below. They belong
    // to an instruction that is four stages ahead of the one we are decoding.
    input  wire        RegWriteW,    // does that older instruction write a reg?
    input  wire [4:0]  RdW,          // which register number
    input  wire [31:0] ResultW,      // the value to put in it

    // ---- backward path in, from the hazard unit ---------------------------
    input  wire        FlushE,       // 1 = clear ID/EX (bubble or wrong path)

    // ---- forward path out, into execute (outputs of the ID/EX register) ---
    output reg         RegWriteE,    // control: write a register in WB
    output reg         ALUSrcE,      // control: ALU operand B = imm, not rs2
    output reg         MemWriteE,    // control: store to data memory in MEM
    output reg         ResultSrcE,   // control: WB value = load data, not ALU
    output reg         BranchE,      // control: this is a branch opcode
    output reg  [2:0]  ALUControlE,  // control: which ALU operation
    output reg  [2:0]  funct3E,      // control: WHICH branch comparison (EX)
    output reg  [31:0] RD1E,         // data: rs1 value
    output reg  [31:0] RD2E,         // data: rs2 value
    output reg  [31:0] ImmExtE,      // data: sign-extended immediate
    output reg  [31:0] PCE,          // data: this instruction's own address
    output reg  [4:0]  RdE,          // data: destination register number
    output reg  [4:0]  Rs1E,         // data: rs1 register NUMBER (not value)
    output reg  [4:0]  Rs2E          // data: rs2 register NUMBER (not value)
);

    //-------------------------------------------------------------------------
    // Combinational signals inside the decode stage. All carry the "D" suffix.
    //-------------------------------------------------------------------------
    wire        RegWriteD;
    wire        ALUSrcD;
    wire        MemWriteD;
    wire        ResultSrcD;
    wire        BranchD;
    wire [1:0]  ImmSrcD;
    wire [2:0]  ALUControlD;
    wire [31:0] RD1D, RD2D;
    wire [31:0] ImmExtD;

    //=========================================================================
    // CONTROL UNIT
    //
    // THE .zero(1'b1) WORKAROUND IS GONE - AND WHY THAT MATTERS
    //
    // Control_Unit_Top used to take the ALU's zero flag as an input, because in
    // the single-cycle core it computed the whole branch decision internally:
    //
    //       Branch (really PCSrc) = <opcode is a branch> & zero
    //
    // A pipeline cannot evaluate that equation here. Decoding happens in ID;
    // the flag it depends on is not produced until the ALU runs in EX, one
    // cycle later. The flag does not exist yet at this point in time.
    //
    // This file used to work around that by passing `.zero(1'b1)`, exploiting
    // x & 1 == x to neutralise the AND gate and recover just the raw branch-
    // opcode bit, then redoing the real AND in Execute_Cycle.v. It worked, but
    // it was a hack papering over a genuine layering mistake in the decoder.
    //
    // The decoder has now been fixed properly: main_decoder.v emits a raw
    // `Branch` bit and has no `zero` port at all, so there is nothing left to
    // neutralise. The condition is evaluated by Branch_Condition.v in whichever
    // stage holds the ALU flags - here that is Execute_Cycle.v.
    //
    // That refactor is also what made bne/blt/bge/bltu/bgeu possible. The old
    // single-flag test could only ever express beq; all five other branches
    // silently executed AS beq. See Branch_Condition.v.
    //
    // funct3 IS NOW NEEDED TWICE
    //   ALU_decoder consumes it here in ID to pick the ALU operation. But the
    //   branch condition ALSO depends on it, and that test happens in EX. So
    //   funct3 has become a signal with a consumer in a later stage, which is
    //   precisely the criterion for earning a seat in the pipeline register -
    //   see funct3E in the ID/EX block at the bottom of this file.
    //=========================================================================
    Control_Unit_Top Control_Unit_Top (
        .Op         (InstrD[6:0]),
        .funct3     (InstrD[14:12]),
        .funct7     (InstrD[31:25]),
        .RegWrite   (RegWriteD),
        .ImmSrc     (ImmSrcD),
        .ALUSrc     (ALUSrcD),
        .MemWrite   (MemWriteD),
        .ResultSrc  (ResultSrcD),
        .Branch     (BranchD),       // = raw branch-opcode bit, NOT "branch taken"
        .ALUControl (ALUControlD)
    );

    //=========================================================================
    // REGISTER FILE - read here in ID, written from WB
    //
    // Reads (A1/A2 -> RD1/RD2) are combinational, so the values are ready
    // within this clock period and get latched into ID/EX at the end of it.
    //
    // The write side is a posedge write driven entirely by the WB stage. This
    // module has no idea, and needs no idea, which instruction those write
    // signals belong to.
    //
    // THE TIMING PROBLEM THIS MODULE HAS, AND WHY IT IS FIXED OUTSIDE IT
    //   Register_file.v writes on the RISING edge and its reads have NO
    //   write-through bypass. A value written at edge T is therefore invisible
    //   to a read latched at that same edge T - the read sees the pre-edge
    //   value. (Verilog's non-blocking semantics make this deterministic
    //   rather than a race: both sides sample old state, then update.)
    //
    //   Now count when that collision actually happens. Take a producer p and
    //   a consumer c = p+3, with no stalls between them:
    //
    //       cycle:   T-3   T-2   T-1    T
    //       p (idx)  EX    MEM   WB
    //       c=p+3    --    IF    ID    EX
    //
    //   The consumer is in ID during cycle T-1, which is EXACTLY the cycle the
    //   producer spends in WB. The producer's write commits at the edge ending
    //   T-1; the consumer's ID/EX register latches its operands at that same
    //   edge. Stale read.
    //
    //   And EX-stage forwarding cannot rescue it either: by cycle T, when the
    //   consumer is in EX, the producer has already LEFT WB. It is not on
    //   EX/MEM (that is p+1's slot) and not on MEM/WB (that is p+2's). The
    //   value has fallen off the end of every forwarding path.
    //
    //   So distance 3 - and only distance 3 - was a real hole. Distances 1 and
    //   2 are forwarded in EX; distance 4+ is safely committed and read
    //   normally.
    //
    // THE TEXTBOOK FIX, AND WHY THIS PROJECT DOES IT DIFFERENTLY
    //   Harris & Harris and Patterson & Hennessy both solve this inside the
    //   register file: write during the FIRST half of the clock cycle, read
    //   during the SECOND half, so a same-cycle write-then-read just works.
    //
    //   That would mean editing single_core/Register_file.v - a file shared
    //   verbatim with the single-cycle core, which currently passes its own
    //   regression. Changing its write timing to fix a pipeline-only problem
    //   risks breaking a core that does not even have this problem. So the fix
    //   is applied HERE instead, in a file the pipeline owns outright.
    //
    // WHAT THE BYPASS BELOW ACTUALLY DOES
    //   It reproduces write-first-read-second behaviour in combinational logic
    //   OUTSIDE the register file: if the value being written from WB this
    //   cycle is for the very register we are reading this cycle, use the
    //   write data directly instead of the array output. Same observable
    //   behaviour as a half-cycle register file, zero changes to shared code.
    //
    //   The RdW != 0 guard matters for the same reason it does in the
    //   forwarding unit: x0 must always read as zero, and rs1/rs2 fields read
    //   as 0 on instructions that do not use them.
    //
    // DOES THIS EVER FIGHT WITH EX-STAGE FORWARDING?
    //   No - and the priority works out correctly without any coordination
    //   between them. Suppose two producers write the same register and the
    //   consumer needs the LATER one. If that later producer is 1 or 2 back,
    //   Execute_Cycle.v's forwarding muxes override whatever value was latched
    //   into RD1E/RD2E, so this bypass is simply ignored. If it is 3 back,
    //   this bypass supplies it and EX forwarding finds no match. If it is 4+
    //   back, nobody is in WB writing that register while we decode, so the
    //   plain array read is already right. The three mechanisms partition the
    //   distance axis cleanly with no overlap and no gap.
    //=========================================================================
    Register_file Register_file (
        .clk (clk),
        .rst (rst),
        .A1  (InstrD[19:15]),   // rs1
        .A2  (InstrD[24:20]),   // rs2
        .A3  (RdW),             // write address  - from WB, 4 stages ahead
        .WD3 (ResultW),         // write data     - from WB
        .WE3 (RegWriteW),       // write enable   - from WB
        .RD1 (RD1D),            // raw array read - may be one edge stale
        .RD2 (RD2D)
    );

    //-------------------------------------------------------------------------
    // WRITE-THROUGH BYPASS - see the long explanation directly above.
    // These, not RD1D/RD2D, are what gets latched into the ID/EX register.
    //-------------------------------------------------------------------------
    wire RD1_bypass = RegWriteW && (RdW != 5'b00000) && (RdW == InstrD[19:15]);
    wire RD2_bypass = RegWriteW && (RdW != 5'b00000) && (RdW == InstrD[24:20]);

    wire [31:0] RD1D_fwd = RD1_bypass ? ResultW : RD1D;
    wire [31:0] RD2D_fwd = RD2_bypass ? ResultW : RD2D;

    //=========================================================================
    // SIGN EXTENDER
    //
    // Unchanged from the single-cycle core. Reused verbatim: ImmSrcD selects
    // between I-type, S-type and B-type immediate layouts.
    //
    // Note that ImmSrcD itself never enters the pipeline register. It is only
    // needed to *produce* ImmExtD, which happens right here in ID. Once the
    // 32-bit immediate exists, the 2-bit selector has served its purpose and is
    // thrown away. Only signals a LATER stage consumes deserve a seat in the
    // pipeline register - carrying anything else is wasted flip-flops.
    //=========================================================================
    Sign_Extend Sign_Extend (
        .In      (InstrD),
        .ImmSrc  (ImmSrcD),
        .Imm_Ext (ImmExtD)
    );

    //=========================================================================
    // ID/EX PIPELINE REGISTER
    //
    // Everything the execute stage and beyond will ever need about this
    // instruction is frozen here. After this edge, InstrD is free to be
    // overwritten by the next instruction - nothing downstream ever looks at
    // the raw instruction word again. That is deliberate: by ID/EX the
    // instruction has been fully translated into control bits + operands.
    //
    // WHY PCE IS CARRIED
    //   Branch_Adder is no longer in the fetch stage (see the note in
    //   Fetch_Cycle.v). The branch target is "address of the branch itself +
    //   immediate", and the immediate only exists after sign extension here in
    //   ID, so the addition was pushed down into EX. For EX to do that addition
    //   it needs the branch's own address, which is why PC rides IF -> ID -> EX.
    //
    // WHY PCPlus4 IS *NOT* CARRIED
    //   Textbook pipelines pipe PC+4 all the way to WB, because jal writes the
    //   return address PC+4 into rd. This core does not implement jal, so PC+4
    //   has exactly one consumer - the PC mux back in fetch - and it never
    //   needs to leave the fetch stage. Adding it here would be four registers
    //   of dead silicon. It goes in the moment jal does.
    //
    // WHY RdE IS CARRIED
    //   The destination register number is decided by the instruction encoding
    //   here in ID, but is not USED until WB names the register to write. So
    //   the 5-bit field rides the whole pipe: RdE -> RdM -> RdW.
    //
    // RESET CLEARS EVERY CONTROL BIT
    //   Same reasoning as the IF/ID register: an X on RegWrite or MemWrite
    //   would let a garbage write land in the register file or data memory
    //   before the program even starts. Zeroing them makes the reset state a
    //   stream of harmless NOPs draining out of the pipe.
    //
    // FlushE CLEARS EXACTLY THE SAME THINGS RESET DOES - AND THAT IS THE POINT
    //   A "bubble" is not a special kind of instruction with its own encoding.
    //   It is just an all-zeros control word: RegWriteE=0, MemWriteE=0,
    //   BranchE=0. Such an entry flows down the pipe occupying a slot, doing
    //   arithmetic nobody reads, and writing nothing anywhere. Architecturally
    //   invisible - which is the entire requirement.
    //
    //   So the flush clause shares the reset clause's body. Two very different
    //   REASONS (start-up vs. a hazard) needing the identical ACTION (make
    //   this pipeline slot inert) is worth noticing rather than treating as a
    //   coincidence - it is why one `if (!rst || FlushE)` is honest here
    //   rather than a shortcut.
    //
    //   FlushE fires for both of the hazard unit's cases:
    //     * load-use stall - fills the gap opened when IF/ID is held, so the
    //       held instruction is not issued into EX twice.
    //     * taken branch   - kills the wrong-path instruction that already
    //       made it into decode.
    //   See Hazard_Unit.v for the derivation of both.
    //
    // WHY THERE IS NO "StallE"
    //   The back half of the pipe (EX, MEM, WB) NEVER stalls in this design.
    //   When the front freezes, the back keeps draining - that is what makes
    //   room for the bubble. A stall that froze every stage at once would
    //   accomplish nothing at all: the pipeline would simply stop, and the
    //   load whose data we are waiting for would never reach WB.
    //=========================================================================
    always @(posedge clk) begin
        if (!rst || FlushE) begin
            RegWriteE   <= 1'b0;
            ALUSrcE     <= 1'b0;
            MemWriteE   <= 1'b0;
            ResultSrcE  <= 1'b0;
            BranchE     <= 1'b0;
            ALUControlE <= 3'b000;
            funct3E     <= 3'b000;
            RD1E        <= 32'h00000000;
            RD2E        <= 32'h00000000;
            ImmExtE     <= 32'h00000000;
            PCE         <= 32'h00000000;
            RdE         <= 5'b00000;
            Rs1E        <= 5'b00000;
            Rs2E        <= 5'b00000;
        end
        else begin
            // ---- the control backpack ----
            RegWriteE   <= RegWriteD;
            ALUSrcE     <= ALUSrcD;
            MemWriteE   <= MemWriteD;
            ResultSrcE  <= ResultSrcD;
            BranchE     <= BranchD;
            ALUControlE <= ALUControlD;
            // funct3 rides along RAW, undecoded. Every other control bit in
            // this backpack has already been chewed into a mux select by the
            // decoder above; funct3E is the one exception, because its second
            // consumer (Branch_Condition in EX) wants the original ISA field,
            // not a derived signal. Decoding it here would mean inventing a
            // 3-bit "branch type" encoding that carries exactly the same
            // information in exactly as many bits - pure ceremony. Sending the
            // architectural field itself is both cheaper and easier to read
            // against the ISA manual.
            funct3E     <= InstrD[14:12];
            // ---- the data ----
            // RD1D_fwd / RD2D_fwd, not the raw RD1D / RD2D: the write-through
            // bypass above has already substituted the WB value if this
            // instruction's producer is exactly 3 slots ahead of it.
            RD1E        <= RD1D_fwd;
            RD2E        <= RD2D_fwd;
            ImmExtE     <= ImmExtD;
            PCE         <= PCD;
            RdE         <= InstrD[11:7];   // rd field
            Rs1E        <= InstrD[19:15];  // rs1 field - forwarding compares this
            Rs2E        <= InstrD[24:20];  // rs2 field - forwarding compares this
        end
    end

endmodule
