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
// WHAT WE ARE DELIBERATELY NOT DOING YET
//   Nothing here checks whether the register we are reading is about to be
//   written by an instruction still in flight. That is a data hazard, and this
//   build has no hazard hardware at all - the test program in program.hex
//   spaces dependent instructions apart with NOPs instead. See the header of
//   src/program.hex for the exact spacing rule and why it is 3 NOPs.
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

    // ---- forward path out, into execute (outputs of the ID/EX register) ---
    output reg         RegWriteE,    // control: write a register in WB
    output reg         ALUSrcE,      // control: ALU operand B = imm, not rs2
    output reg         MemWriteE,    // control: store to data memory in MEM
    output reg         ResultSrcE,   // control: WB value = load data, not ALU
    output reg         BranchE,      // control: this is a branch opcode
    output reg  [2:0]  ALUControlE,  // control: which ALU operation
    output reg  [31:0] RD1E,         // data: rs1 value
    output reg  [31:0] RD2E,         // data: rs2 value
    output reg  [31:0] ImmExtE,      // data: sign-extended immediate
    output reg  [31:0] PCE,          // data: this instruction's own address
    output reg  [4:0]  RdE           // data: destination register number
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
    // READ THIS BEFORE JUDGING THE .zero(1'b1) BELOW.
    //
    // Control_Unit_Top was written for the single-cycle core, where the ALU's
    // zero flag was available in the same clock period as decoding. Internally
    // it computes:
    //
    //       Branch (a.k.a. PCSrc) = <opcode is a branch> & zero
    //
    // In a PIPELINE that equation cannot be evaluated here. Decoding happens in
    // ID; the comparison that produces the zero flag does not happen until the
    // ALU runs in EX, one cycle later. The zero flag simply does not exist yet
    // at this point in time.
    //
    // What we need out of the decoder is only the LEFT half of that AND - the
    // raw "is this a branch instruction?" bit. Tying zero to 1'b1 gives exactly
    // that, because  x & 1 == x :
    //
    //       BranchD = <opcode is a branch> & 1 = <opcode is a branch>
    //
    // The other half of the AND is then performed in Execute_Cycle.v, where the
    // real zero flag exists:
    //
    //       assign PCSrcE = BranchE & ZeroE;
    //
    // So the logic is not lost or weakened - it is SPLIT ACROSS TWO STAGES,
    // which is the whole point of pipelining.
    //
    // WHY THIS IS NOT THE OLD BUG
    //   The single-cycle core once had a genuine defect where main_decoder's
    //   zero port was hardcoded to 1'b0 (documented in
    //   docs/RV32I_Single_Cycle_Core.pdf, section 6). That was fatal because
    //   x & 0 == 0 always - the branch condition was destroyed and beq could
    //   never be taken. Tying it to 1'b1 is the opposite: it is the identity
    //   element of AND, so it destroys nothing and merely defers the real test.
    //
    // WHY NOT JUST ADD A CLEAN "branch_op" OUTPUT TO main_decoder?
    //   That would be tidier, but it means editing main_decoder.v,
    //   Control_Unit_Top.v and Single_Cycle_Top.v - three files belonging to a
    //   core that currently passes its regression. Keeping single_core/ frozen
    //   and untouched means any bug found here is provably a pipeline bug, not
    //   a regression I introduced in the shared modules.
    //=========================================================================
    Control_Unit_Top Control_Unit_Top (
        .Op         (InstrD[6:0]),
        .funct3     (InstrD[14:12]),
        .funct7     (InstrD[31:25]),
        .zero       (1'b1),          // see the long explanation directly above
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
    // TIMING CONSEQUENCE YOU MUST KNOW ABOUT
    //   Register_file.v writes on the RISING edge and its reads have no
    //   write-through bypass. So a value written at edge T is only visible to
    //   reads that are latched at edge T+1 or later. Combined with the four
    //   stages between ID and WB, that is why a dependent instruction must sit
    //   at least 4 slots behind its producer (3 NOPs in between). Worked out
    //   arithmetically in the src/program.hex header.
    //=========================================================================
    Register_file Register_file (
        .clk (clk),
        .rst (rst),
        .A1  (InstrD[19:15]),   // rs1
        .A2  (InstrD[24:20]),   // rs2
        .A3  (RdW),             // write address  - from WB, 4 stages ahead
        .WD3 (ResultW),         // write data     - from WB
        .WE3 (RegWriteW),       // write enable   - from WB
        .RD1 (RD1D),
        .RD2 (RD2D)
    );

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
    //=========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            RegWriteE   <= 1'b0;
            ALUSrcE     <= 1'b0;
            MemWriteE   <= 1'b0;
            ResultSrcE  <= 1'b0;
            BranchE     <= 1'b0;
            ALUControlE <= 3'b000;
            RD1E        <= 32'h00000000;
            RD2E        <= 32'h00000000;
            ImmExtE     <= 32'h00000000;
            PCE         <= 32'h00000000;
            RdE         <= 5'b00000;
        end
        else begin
            // ---- the control backpack ----
            RegWriteE   <= RegWriteD;
            ALUSrcE     <= ALUSrcD;
            MemWriteE   <= MemWriteD;
            ResultSrcE  <= ResultSrcD;
            BranchE     <= BranchD;
            ALUControlE <= ALUControlD;
            // ---- the data ----
            RD1E        <= RD1D;
            RD2E        <= RD2D;
            ImmExtE     <= ImmExtD;
            PCE         <= PCD;
            RdE         <= InstrD[11:7];   // rd field
        end
    end

endmodule
