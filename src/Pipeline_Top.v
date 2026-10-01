//=============================================================================
// Pipeline_Top.v  -  5-stage RV32I pipeline, top-level integration
//=============================================================================
//
// WHAT THIS FILE IS
//   Wiring, and only wiring. Every gate in the design lives inside one of the
//   five stage modules; this file declares the wires that connect them and
//   instantiates each stage exactly once. If you want to understand HOW the
//   core works, read the five stage files. If you want to understand how the
//   pieces FIT TOGETHER, read this one.
//
// INCLUDE STRATEGY - READ THIS BEFORE TRYING TO COMPILE
//   Two groups of files are included below: the five NEW stage files that live
//   here in src/, and the eight SHARED functional units that live in
//   single_core/ and are reused untouched.
//
//   The shared files are included by BARE FILENAME, not by relative path, so
//   the build must hand iverilog a search path:
//
//       cd src
//       iverilog -I ../single_core -o out.vvp Pipeline_Top_TestBench.v
//       vvp out.vvp
//
//   Why not just `include "../single_core/Control_Unit_Top.v"? Because that
//   file itself contains `include "main_decoder.v", and a nested include is
//   resolved relative to the CURRENT WORKING DIRECTORY - not relative to the
//   file doing the including. So the outer include would succeed and the inner
//   one would fail with "Include file main_decoder.v not found". The -I search
//   path fixes it correctly at every level of nesting.
//
// WHY single_core/ IS REUSED INSTEAD OF COPIED
//   The functional units do not change when you pipeline a processor. An ALU is
//   an ALU. What changes is that you put REGISTERS BETWEEN THEM. Sharing the
//   modules makes that point structurally, and guarantees the two cores cannot
//   silently drift apart.
//
//=============================================================================
// THE SHAPE OF THE DATAPATH
//
//   IF ---> [IF/ID] ---> ID ---> [ID/EX] ---> EX ---> [EX/MEM] ---> MEM --->
//                                                          [MEM/WB] ---> WB
//
//   Forward: five stages, four pipeline registers between them.
//   Backward: FOUR paths now.
//
//     BACKWARD PATH 1 - branch redirect  (EX -> IF)
//        PCSrcE, PCTargetE
//        A branch is resolved in EX, but the PC lives in IF. By the time the
//        answer arrives, IF has already fetched two more instructions. Those
//        two are now KILLED by the hazard unit's FlushD/FlushE rather than
//        being tolerated - see path 4. A taken branch still costs 2 cycles of
//        empty pipeline, but it no longer costs the PROGRAMMER anything.
//
//     BACKWARD PATH 2 - register write-back  (WB -> ID)
//        RegWriteW, RdW, ResultW
//        The register file is read in ID but written from WB, four stages
//        later. Still the mechanism that eventually commits every value.
//        Decode_Cycle.v now also bypasses these same three wires straight
//        into the ID/EX register when the producer is exactly 3 slots ahead -
//        the case neither the register file nor forwarding could cover.
//
//     BACKWARD PATH 3 - forwarding  (WB -> EX, and MEM's own regs -> EX)
//        RegWriteW, RdW, ResultW ALSO reach into Execute_Cycle directly (the
//        same three wires as path 2, wired to a second destination), plus
//        Execute_Cycle reads its OWN EX/MEM register's present value for the
//        nearer hazard - see the FORWARDING UNIT comment in Execute_Cycle.v.
//        Resolves producers 1 and 2 instructions back at zero cost.
//
//     BACKWARD PATH 4 - stall and flush control  (Hazard_Unit -> IF, ID)
//        StallF, StallD, FlushD, FlushE
//        The only path that can make the pipeline do LESS work rather than
//        more. Handles the two things forwarding physically cannot: a load
//        whose data does not exist yet (stall one cycle), and instructions
//        fetched down a path a branch turned out not to take (throw away).
//        See Hazard_Unit.v.
//
// WHAT THIS BUILD NOW HANDLES - COMPLETE HAZARD COVERAGE
//   RAW distance 1   -> EX/MEM forwarding                     0 cycles
//   RAW distance 2   -> MEM/WB forwarding                     0 cycles
//   RAW distance 3   -> decode write-through bypass           0 cycles
//   RAW distance 4+  -> ordinary register-file read           0 cycles
//   load-use         -> 1-cycle stall, then MEM/WB forwarding 1 cycle
//   taken branch     -> flush IF/ID and ID/EX                 2 cycles
//   WAR / WAW        -> impossible in an in-order pipeline (see Hazard_Unit.v)
//   structural       -> impossible, instruction and data memory are separate
//
//   src/program.hex therefore needs NO hand-scheduled NOPs of any kind. Every
//   hazard in this ISA subset is now handled in hardware. That is the
//   difference between a pipeline that works and a pipeline that works only
//   for programs written carefully enough not to break it.
//
// WHAT THIS BUILD STILL DOES NOT HAVE
//   - no branch prediction. A taken branch is resolved in EX and always costs
//     2 flushed cycles. Prediction would hide that; flushing only makes it
//     correct, not cheap.
//   - no exceptions, interrupts, or CSRs.
//   - no multiply/divide, no jal/jalr, no lb/lh/sb/sh.
//=============================================================================

// ---- the five NEW stage files, here in src/ ----
`include "Fetch_Cycle.v"
`include "Decode_Cycle.v"
`include "Execute_Cycle.v"
`include "Memory_Cycle.v"
`include "Writeback_Cycle.v"
`include "Hazard_Unit.v"      // not a stage - the stall/flush controller

// ---- the eight SHARED functional units, reused verbatim from single_core/ ----
// Found via  iverilog -I ../single_core  (see the note above). Not one line of
// any of these files was changed to pipeline the core - that is the point.
// Control_Unit_Top.v pulls in main_decoder.v and ALU_decoder.v itself.
`include "PC.v"                  // PC_Module
`include "PC_Adder.v"            // PC_Adder        - instanced twice (PC+4, branch target)
`include "instruction_Memory.v"  // instruction_Memory
`include "Register_file.v"       // Register_file
`include "Sign_Extend.v"         // Sign_Extend
`include "Control_Unit_Top.v"    // Control_Unit_Top (+ main_decoder + ALU_decoder)
`include "ALU.v"                 // ALU
`include "Data_Mem.v"            // Data_Memory
`include "Branch_Condition.v"    // Branch_Condition - funct3 + flags -> taken

module Pipeline_Top (
    input wire clk,
    input wire rst              // ACTIVE-LOW: rst==0 means "in reset"
);

    //-------------------------------------------------------------------------
    // INTER-STAGE WIRES
    //
    // Read these as a map of the pipeline. Each group is the output bundle of
    // one pipeline register, and the suffix letter tells you which stage the
    // bundle has arrived in. The bundle gets narrower as you go down the page,
    // because each stage consumes some signals and passes on only the rest.
    //-------------------------------------------------------------------------

    // ---- IF/ID outputs: what decode sees ----
    wire [31:0] InstrD, PCD;

    // ---- ID/EX outputs: what execute sees ----
    wire        RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE;
    wire [3:0]  ALUControlE;
    wire [1:0]  ALUSrcAE;  // operand A select: rs1 / PC / 0
    wire [2:0]  funct3E;   // raw ISA field - picks WHICH branch comparison
    wire [31:0] RD1E, RD2E, ImmExtE, PCE;
    wire [4:0]  RdE, Rs1E, Rs2E;   // Rs1E/Rs2E: register NUMBERS, for forwarding

    // ---- EX/MEM outputs: what memory sees ----
    wire        RegWriteM, MemWriteM, ResultSrcM;
    wire [31:0] ALU_ResultM, WriteDataM;
    wire [4:0]  RdM;

    // ---- MEM/WB outputs: what write-back sees ----
    wire        RegWriteW, ResultSrcW;
    wire [31:0] ALU_ResultW, ReadDataW;
    wire [4:0]  RdW;

    // ---- the backward paths ----
    wire        PCSrcE;      // EX -> IF : redirect the PC
    wire [31:0] PCTargetE;   // EX -> IF : redirect target
    wire [31:0] ResultW;     // WB -> ID : value to write into the register file

    // ---- hazard-unit control (see Hazard_Unit.v) ----
    wire        StallF;      // Hazard -> IF : hold the PC
    wire        StallD;      // Hazard -> IF : hold the IF/ID register
    wire        FlushD;      // Hazard -> IF : clear the IF/ID register
    wire        FlushE;      // Hazard -> ID : clear the ID/EX register

    //=========================================================================
    // STAGE 1 - INSTRUCTION FETCH
    //
    // Note the mixed direction of its ports: PCSrcE/PCTargetE flow IN from a
    // stage two positions downstream. That is the branch-redirect path, and it
    // is the only reason this stage needs to know anything about EX.
    //=========================================================================
    Fetch_Cycle Fetch (
        .clk       (clk),
        .rst       (rst),
        .PCSrcE    (PCSrcE),        // <-- backward, from EX
        .PCTargetE (PCTargetE),     // <-- backward, from EX
        .StallF    (StallF),        // <-- backward, from the hazard unit
        .StallD    (StallD),        // <-- backward, from the hazard unit
        .FlushD    (FlushD),        // <-- backward, from the hazard unit
        .InstrD    (InstrD),
        .PCD       (PCD)
    );

    //=========================================================================
    // STAGE 2 - INSTRUCTION DECODE
    //
    // Also has a backward input bundle: RegWriteW/RdW/ResultW drive the WRITE
    // port of the register file that physically sits inside this module. Read
    // in ID, written from WB - one register file, two stages.
    //=========================================================================
    Decode_Cycle Decode (
        .clk         (clk),
        .rst         (rst),
        .InstrD      (InstrD),
        .PCD         (PCD),
        .RegWriteW   (RegWriteW),   // <-- backward, from WB
        .RdW         (RdW),         // <-- backward, from WB
        .ResultW     (ResultW),     // <-- backward, from WB
        .FlushE      (FlushE),      // <-- backward, from the hazard unit
        .RegWriteE   (RegWriteE),
        .ALUSrcE     (ALUSrcE),
        .ALUSrcAE    (ALUSrcAE),
        .MemWriteE   (MemWriteE),
        .ResultSrcE  (ResultSrcE),
        .BranchE     (BranchE),
        .funct3E     (funct3E),
        .ALUControlE (ALUControlE),
        .RD1E        (RD1E),
        .RD2E        (RD2E),
        .ImmExtE     (ImmExtE),
        .PCE         (PCE),
        .RdE         (RdE),
        .Rs1E        (Rs1E),
        .Rs2E        (Rs2E)
    );

    //=========================================================================
    // STAGE 3 - EXECUTE
    //
    // Produces the branch-redirect bundle for fetch, as before. It now ALSO
    // consumes RegWriteW/RdW/ResultW - the SAME three wires already wired
    // into Decode for the write-back path - as its forwarding source from
    // WB. One producer, two consumers; nothing new needed at the WB end.
    //=========================================================================
    Execute_Cycle Execute (
        .clk         (clk),
        .rst         (rst),
        .RegWriteE   (RegWriteE),
        .ALUSrcE     (ALUSrcE),
        .ALUSrcAE    (ALUSrcAE),
        .MemWriteE   (MemWriteE),
        .ResultSrcE  (ResultSrcE),
        .BranchE     (BranchE),
        .funct3E     (funct3E),     // which of the six comparisons to apply
        .ALUControlE (ALUControlE),
        .RD1E        (RD1E),
        .RD2E        (RD2E),
        .ImmExtE     (ImmExtE),
        .PCE         (PCE),
        .RdE         (RdE),
        .Rs1E        (Rs1E),
        .Rs2E        (Rs2E),
        .RegWriteW   (RegWriteW),   // <-- forwarding source, from WB
        .RdW         (RdW),         // <-- forwarding source, from WB
        .ResultW     (ResultW),     // <-- forwarding source, from WB
        .PCSrcE      (PCSrcE),      // --> backward, to IF
        .PCTargetE   (PCTargetE),   // --> backward, to IF
        .RegWriteM   (RegWriteM),
        .MemWriteM   (MemWriteM),
        .ResultSrcM  (ResultSrcM),
        .ALU_ResultM (ALU_ResultM),
        .WriteDataM  (WriteDataM),
        .RdM         (RdM)
    );

    //=========================================================================
    // STAGE 4 - MEMORY
    //=========================================================================
    Memory_Cycle Memory (
        .clk         (clk),
        .rst         (rst),
        .RegWriteM   (RegWriteM),
        .MemWriteM   (MemWriteM),
        .ResultSrcM  (ResultSrcM),
        .ALU_ResultM (ALU_ResultM),
        .WriteDataM  (WriteDataM),
        .RdM         (RdM),
        .RegWriteW   (RegWriteW),
        .ResultSrcW  (ResultSrcW),
        .ALU_ResultW (ALU_ResultW),
        .ReadDataW   (ReadDataW),
        .RdW         (RdW)
    );

    //=========================================================================
    // STAGE 5 - WRITE-BACK
    //
    // Purely combinational - there is no sixth stage to hand anything to. Its
    // one output loops back to the register file in Decode.
    //
    // Notice RegWriteW and RdW are NOT routed through this module: they come
    // straight out of the MEM/WB register above and go straight into Decode.
    // Write-back only chooses the VALUE; the enable and the address need no
    // further processing.
    //=========================================================================
    Writeback_Cycle Writeback (
        .ResultSrcW  (ResultSrcW),
        .ALU_ResultW (ALU_ResultW),
        .ReadDataW   (ReadDataW),
        .ResultW     (ResultW)      // --> backward, to the register file in ID
    );

    //=========================================================================
    // HAZARD UNIT  -  not a pipeline stage
    //
    // This is the one block in the design that sits BESIDE the pipeline rather
    // than inside it. It holds no data and adds no latency; it only watches
    // signals that already exist and decides whether the front of the pipe
    // should freeze or discard work. See Hazard_Unit.v for the full derivation
    // of both conditions.
    //
    // WHY Rs1D/Rs2D ARE SLICED OUT OF InstrD HERE RATHER THAN PORTED OUT OF
    // DECODE
    //   The hazard unit needs the register numbers of the instruction being
    //   DECODED right now - one stage earlier than the Rs1E/Rs2E that
    //   Execute_Cycle's forwarding unit uses. InstrD is already a top-level
    //   wire (it is the IF/ID register's output, driven by Fetch and consumed
    //   by Decode), so those fields are available here for free. Adding
    //   Rs1D/Rs2D output ports to Decode_Cycle would create two more wires
    //   carrying bits this module can already see - pure redundancy.
    //
    //   The field positions are fixed by the RV32I encoding and identical for
    //   every instruction format that has them: rs1 = [19:15], rs2 = [24:20].
    //   That regularity is deliberate in the ISA, precisely so hardware can
    //   read register numbers before it knows what the instruction is.
    //
    // WHY THIS CANNOT CREATE A COMBINATIONAL LOOP
    //   Every input here is a pipeline-register OUTPUT (InstrD from IF/ID,
    //   RdE/ResultSrcE from ID/EX) or derived from one (PCSrcE, from ID/EX
    //   contents through the ALU). Every output feeds only the CONTROL side of
    //   a pipeline register - an enable or a clear, never a data path that
    //   loops back into this unit's own inputs within the same cycle. The
    //   logic is a pure feed-forward cone from registered state to register
    //   controls, which is exactly what a hazard unit is supposed to be.
    //=========================================================================
    Hazard_Unit Hazard_Unit (
        .Rs1D       (InstrD[19:15]),  // rs1 of the instruction now in DECODE
        .Rs2D       (InstrD[24:20]),  // rs2 of the instruction now in DECODE
        .RdE        (RdE),            // destination of the instruction in EX
        .ResultSrcE (ResultSrcE),     // ...and whether that one is a LOAD
        .PCSrcE     (PCSrcE),         // ...or a TAKEN BRANCH
        .StallF     (StallF),
        .StallD     (StallD),
        .FlushD     (FlushD),
        .FlushE     (FlushE)
    );

endmodule
