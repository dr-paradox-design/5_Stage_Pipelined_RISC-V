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
//   Backward: THREE paths now. Two are architectural necessities (branch
//   redirect, register write-back); the third is forwarding, which exists
//   purely to shorten the delay the second one would otherwise cost.
//
//     BACKWARD PATH 1 - branch redirect  (EX -> IF)
//        PCSrcE, PCTargetE
//        A branch is resolved in EX, but the PC lives in IF. By the time the
//        answer arrives, IF has already fetched two more instructions.
//        Consequence: 2 delay-slot NOPs after every taken branch. STILL
//        PRESENT - forwarding does nothing for control hazards, only data
//        hazards. Fixing this needs flush logic, not built yet.
//
//     BACKWARD PATH 2 - register write-back  (WB -> ID)
//        RegWriteW, RdW, ResultW
//        The register file is read in ID but written from WB, four stages
//        later, with no write-through bypass. Left completely unchanged by
//        this update - still the mechanism that eventually commits a value.
//
//     BACKWARD PATH 3 - forwarding  (WB -> EX, and MEM's own regs -> EX)
//        RegWriteW, RdW, ResultW ALSO now reach into Execute_Cycle directly
//        (the same three wires as path 2, just wired to a second
//        destination), plus Execute_Cycle reads its OWN EX/MEM register's
//        present value for the nearer hazard - see the FORWARDING UNIT
//        comment in Execute_Cycle.v. This is what removed the 3-NOP data-
//        hazard gap: EX no longer has to wait for path 2 to complete, it can
//        grab the value the moment it exists.
//
//   The branch-delay consequence is still handled IN SOFTWARE, by scheduling
//   2 NOPs in src/program.hex after every taken branch. That is a real
//   historical technique (early MIPS exposed the branch delay slot in its ISA
//   for exactly this reason).
//
// WHAT THIS BUILD DELIBERATELY DOES NOT HAVE (YET)
//   - no hazard detection unit / load-use stall logic
//   - no flushing (nothing ever clears a pipeline register mid-run)
//   Forwarding (EX/MEM and MEM/WB -> EX) IS now present - see
//   Execute_Cycle.v. It resolves ordinary RAW hazards with zero stall
//   cycles. The one pattern it cannot resolve is load-use (a lw immediately
//   followed by a dependent instruction), because the loaded data is not
//   ready until MEM completes - one cycle later than forwarding can reach.
//   That needs hazard detection + a stall, the next project stage.
//=============================================================================

// ---- the five NEW stage files, here in src/ ----
`include "Fetch_Cycle.v"
`include "Decode_Cycle.v"
`include "Execute_Cycle.v"
`include "Memory_Cycle.v"
`include "Writeback_Cycle.v"

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
    wire [2:0]  ALUControlE;
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

    // ---- the two backward paths ----
    wire        PCSrcE;      // EX -> IF : redirect the PC
    wire [31:0] PCTargetE;   // EX -> IF : redirect target
    wire [31:0] ResultW;     // WB -> ID : value to write into the register file

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
        .RegWriteE   (RegWriteE),
        .ALUSrcE     (ALUSrcE),
        .MemWriteE   (MemWriteE),
        .ResultSrcE  (ResultSrcE),
        .BranchE     (BranchE),
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
        .MemWriteE   (MemWriteE),
        .ResultSrcE  (ResultSrcE),
        .BranchE     (BranchE),
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

endmodule
