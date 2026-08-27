//=============================================================================
// Fetch_Cycle.v  -  STAGE 1 of 5  (IF)
//=============================================================================
//
// WHAT THIS STAGE DOES
//   Reads the instruction that the PC points at, and works out which address to
//   read next. That is all. It does not look at the instruction it fetched -
//   decoding is the next stage's job.
//
// THE NAMING RULE USED THROUGHOUT src/
//   Every signal ends in a letter saying WHICH STAGE IT LIVES IN:
//       F = Fetch      D = Decode     E = Execute
//       M = Memory     W = Write-back
//   So PCF is "the PC, as seen in the fetch stage" and PCD is "the same PC
//   value one cycle later, after it has been latched into the IF/ID register".
//   The moment a signal crosses a pipeline register, its letter changes.
//   This is the single most useful habit for reading pipelined RTL: if you see
//   RD2E and RD2M you instantly know they are the same wire, one cycle apart.
//
// WHAT MAKES THIS "PIPELINED"
//   In the single-cycle core, the instruction was fetched and fully executed in
//   the same clock period. Here, fetch hands the instruction to a REGISTER
//   (the IF/ID register at the bottom of this file) and immediately moves on to
//   fetch the next one. Five instructions end up in flight at once.
//
// THE BACKWARDS SIGNALS
//   PCSrcE / PCTargetE come BACKWARDS from the execute stage. A branch is not
//   resolved until EX, but the PC lives here in IF. That backward path is what
//   makes branches expensive in a pipeline.
//
//   StallF / StallD / FlushD come backwards from the Hazard_Unit. They are the
//   reason this stage no longer just marches forward unconditionally: it can
//   now be told to FREEZE (a load-use stall downstream) or to THROW AWAY what
//   it just fetched (a taken branch). Read Hazard_Unit.v for why each one
//   exists; this file only implements them.
//=============================================================================

module Fetch_Cycle (
    input  wire        clk,
    input  wire        rst,        // ACTIVE-LOW: rst==0 means "in reset"

    // ---- backward path from the execute stage -----------------------------
    input  wire        PCSrcE,     // 1 = a branch in EX resolved as TAKEN
    input  wire [31:0] PCTargetE,  // where that taken branch wants to go

    // ---- backward path from the hazard unit -------------------------------
    input  wire        StallF,     // 1 = hold the PC, do not advance
    input  wire        StallD,     // 1 = hold the IF/ID register
    input  wire        FlushD,     // 1 = clear the IF/ID register

    // ---- forward path into the decode stage (outputs of the IF/ID reg) ----
    output reg  [31:0] InstrD,     // the fetched instruction word
    output reg  [31:0] PCD         // the PC that instruction was fetched from
);

    //-------------------------------------------------------------------------
    // Signals internal to the fetch stage. All carry the "F" suffix.
    //-------------------------------------------------------------------------
    wire [31:0] PCF;        // current program counter
    wire [31:0] PCPlus4F;   // PCF + 4, the sequential next address
    wire [31:0] PCNextF;    // whichever of the two we actually go to
    wire [31:0] InstrF;     // instruction read out of memory this cycle

    //-------------------------------------------------------------------------
    // PC-SOURCE MUX  (now three-way: hold / branch / sequential)
    //
    // The inner mux is identical in spirit to Single_Cycle_Top.v's: PCSrcE
    // chooses between the branch target and PC+4. Note WHERE that select comes
    // from - an E suffix, meaning it is produced two stages downstream. By the
    // time a branch in EX asserts PCSrcE, this stage has already fetched the
    // two instructions sitting behind it in memory. Those two are now KILLED
    // by FlushD (here) and FlushE (in Decode_Cycle.v), so they never commit -
    // which is what retired the two hand-written NOPs src/program.hex used to
    // need after every taken branch.
    //
    // HOW THE PC IS STALLED WITHOUT AN ENABLE PIN
    //   PC_Module (single_core/PC.v) is a plain unconditional flip-flop: every
    //   rising edge it does PC <= PC_NEXT. There is no enable input, and that
    //   file is frozen and shared with the single-cycle core, so adding one is
    //   off the table.
    //
    //   No enable is needed. Feeding the PC's own current value back into its
    //   input makes the next edge a no-op: PC <= PCF leaves PC exactly where it
    //   was. A hold is just a self-assignment. This is a genuinely useful trick
    //   - an unconditional register plus a feedback mux IS an enabled register,
    //   and on an FPGA it synthesises to the same thing, because the enable pin
    //   on a real LUT-flop is built exactly this way underneath.
    //
    // WHY StallF SITS OUTSIDE PCSrcE
    //   Priority: freeze beats redirect. The two cannot actually occur together
    //   (see Hazard_Unit.v - both describe the same EX-stage instruction, which
    //   cannot be both a load and a taken branch), so this ordering is
    //   defensive rather than load-bearing. It mirrors Harris & Harris, where
    //   the PC's enable is ~StallF and the branch mux feeds its D input.
    //-------------------------------------------------------------------------
    assign PCNextF = StallF ? PCF :
                     PCSrcE ? PCTargetE :
                              PCPlus4F;

    //-------------------------------------------------------------------------
    // Reused, unmodified, from single_core/. The pipeline does not need
    // different functional units - it needs the SAME units with registers
    // between them. Keeping these shared means a fix in the single-cycle core
    // is automatically a fix here.
    //-------------------------------------------------------------------------
    PC_Module PC_Module (
        .clk     (clk),
        .rst     (rst),
        .PC_NEXT (PCNextF),
        .PC      (PCF)
    );

    PC_Adder PC_Adder (
        .a (PCF),
        .b (32'h00000004),
        .c (PCPlus4F)
    );

    // Note there is NO Branch_Adder here, unlike the single-cycle core.
    // The branch target is PC-of-the-branch + immediate, and the immediate is
    // not known until the sign-extender runs in DECODE. So the branch adder
    // moved down into Execute_Cycle.v, and this stage forwards PCF onward
    // through PCD so that EX still has the branch's own address to add to.
    instruction_Memory instruction_Memory (
        .rst (rst),
        .A   (PCF),
        .RD  (InstrF)
    );

    //=========================================================================
    // IF/ID PIPELINE REGISTER
    //
    // This is the actual "pipelining". Everything above is combinational and
    // finishes within this clock period; this block freezes the result at the
    // clock edge so the decode stage can work on it next cycle while fetch
    // moves on to a new instruction.
    //
    // WHY IT MUST CLEAR ON RESET
    //   If these registers powered up holding X, that X would march down the
    //   pipe and eventually reach RegWrite, which decides whether to write the
    //   register file. An X on a write-enable is not something you want to
    //   debug. Clearing to 32'h00000000 injects opcode 7'b0000000, which our
    //   main_decoder matches on no case at all, so it asserts neither RegWrite
    //   nor MemWrite - a genuinely harmless NOP.
    //
    // WHY NON-BLOCKING (<=) AND NOT BLOCKING (=)
    //   Every pipeline register in this design updates on the same edge. With
    //   <=, all of them sample their OLD inputs simultaneously and then update
    //   together, which is what real flip-flops do. With =, the result would
    //   depend on the order Verilog happened to evaluate the blocks, and data
    //   could race through two stages in one cycle.
    //
    // THE THREE-WAY PRIORITY: RESET, THEN FLUSH, THEN STALL, THEN LATCH
    //   reset  - highest, obviously.
    //   FlushD - a taken branch means the instruction currently in this
    //            register is on the wrong path. Overwrite it with 32'h0, which
    //            decodes to a NOP (opcode 7'b0000000 matches no case in
    //            main_decoder, so neither RegWrite nor MemWrite asserts).
    //            Clearing PCD too is not strictly required - nothing reads the
    //            PC of a NOP - but leaving a stale address behind makes
    //            waveforms lie about which instruction is where, so it is
    //            cleared for debuggability.
    //   StallD - hold: do nothing at all this edge. The instruction already in
    //            IF/ID stays put and gets decoded a second time. This is the
    //            ONLY branch of this block that writes nothing, and that
    //            "writes nothing" is precisely what a stall IS in hardware.
    //   else   - the normal case: advance.
    //
    //   Flush is checked before stall purely defensively - see Hazard_Unit.v
    //   for why the two can never actually be asserted in the same cycle.
    //=========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            InstrD <= 32'h00000000;
            PCD    <= 32'h00000000;
        end
        else if (FlushD) begin
            InstrD <= 32'h00000000;   // wrong-path instruction -> NOP
            PCD    <= 32'h00000000;
        end
        else if (StallD) begin
            InstrD <= InstrD;         // hold - re-decode the same instruction
            PCD    <= PCD;
        end
        else begin
            InstrD <= InstrF;   // instruction moves IF -> ID
            PCD    <= PCF;      // and its address travels with it
        end
    end

endmodule
