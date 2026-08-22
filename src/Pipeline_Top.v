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
//   Backward: exactly two paths, and they are the source of all the difficulty
//   in pipelining.
//
//     BACKWARD PATH 1 - branch redirect  (EX -> IF)
//        PCSrcE, PCTargetE
//        A branch is resolved in EX, but the PC lives in IF. By the time the
//        answer arrives, IF has already fetched two more instructions.
//        Consequence: 2 delay-slot NOPs after every taken branch.
//
//     BACKWARD PATH 2 - register write-back  (WB -> ID)
//        RegWriteW, RdW, ResultW
//        The register file is read in ID but written from WB, four stages
//        later, with no write-through bypass.
//        Consequence: 3 NOPs between a producer and its consumer.
//
//   Both consequences are handled IN SOFTWARE in this build, by scheduling NOPs
//   in src/program.hex. That is a real historical technique (early MIPS exposed
//   the branch delay slot in its ISA for exactly this reason), and it keeps the
//   hardware here honest: no hazard unit is present, and none is pretended.
//
// WHAT THIS BUILD DELIBERATELY DOES NOT HAVE
//   - no hazard detection unit
//   - no forwarding / bypass network
//   - no stalling (nothing ever holds a pipeline register)
//   - no flushing (nothing ever clears a pipeline register mid-run)
//   Those are the next project stage. Leaving them out makes the pipeline
//   registers themselves - the actual subject of this build - easy to see.
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
    wire [4:0]  RdE;

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
        .RdE         (RdE)
    );

    //=========================================================================
    // STAGE 3 - EXECUTE
    //
    // The only stage that produces a backward bundle for fetch. Everything
    // else it emits flows forward into MEM.
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
