//=============================================================================
// Hazard_Unit.v  -  stall and flush control for the 5-stage pipeline
//=============================================================================
//
// WHAT THIS MODULE IS
//   Pure combinational glue. It owns no data and no state - it just watches
//   four facts about instructions already in flight and decides whether the
//   front of the pipeline should HOLD STILL (stall) or THROW WORK AWAY (flush).
//
//   It is deliberately a separate file rather than a few lines inside
//   Pipeline_Top.v, because "what makes this pipeline stall?" is a question
//   worth being able to answer by opening exactly one file.
//
//=============================================================================
// THE DIVISION OF LABOUR: FORWARDING vs STALLING vs FLUSHING
//
//   This core now has THREE distinct hazard mechanisms, and it matters that
//   you can say which one handles which problem:
//
//     FORWARDING  (Execute_Cycle.v)  - fixes ordinary RAW data hazards where
//                 the value ALREADY EXISTS somewhere on-chip. Costs 0 cycles.
//                 Reaches back 2 stages: EX/MEM and MEM/WB.
//
//     DECODE BYPASS (Decode_Cycle.v) - fixes the RAW hazard at distance
//                 exactly 3, where the value exists in WB at the very moment
//                 the consumer is reading the register file. Costs 0 cycles.
//
//     STALLING    (this file)        - the last resort, for when the value
//                 DOES NOT EXIST YET at any point on the chip. There is
//                 exactly one such case in this ISA subset: load-use.
//
//     FLUSHING    (this file)        - for work that was started but turned
//                 out to be WRONG WORK. Exactly one case here: the two
//                 instructions fetched behind a branch that turns out taken.
//
//   Note the asymmetry in cost. Forwarding is free, so it is always preferred.
//   Stalling costs a cycle of throughput, so it is used only where forwarding
//   is physically impossible. That ordering is the whole design philosophy of
//   a hazard unit.
//
//=============================================================================
// HAZARD 1 - LOAD-USE. WHY FORWARDING CANNOT SAVE US HERE
//
//   Forwarding works by grabbing a value off a pipeline register EARLIER than
//   the register file would deliver it. That only works if the value is
//   actually sitting there. Trace a load:
//
//       lw   x9, 0(x0)      <- produces x9
//       addi x13, x9, 1     <- consumes x9, one instruction later
//
//     cycle:      1     2     3     4     5
//     lw          IF    ID    EX    MEM   WB
//     addi              IF    ID    EX    MEM
//
//   In cycle 4 the addi is in EX and needs x9. Where is x9? The lw is in MEM
//   in cycle 4 - the data memory is being READ during that cycle and the word
//   does not land in the MEM/WB register until the edge that ENDS cycle 4.
//   The EX/MEM register at that moment holds ALU_ResultM, which for a load is
//   the ADDRESS, not the data.
//
//   So forwarding from EX/MEM here would not be "slightly early" - it would
//   forward a completely wrong value (an address where data was wanted), and
//   it would do so SILENTLY. That is the single most important reason this
//   module has to exist.
//
//   The fix is the only one available: hold the consumer still for one cycle.
//
//     cycle:      1     2     3     4     5     6
//     lw          IF    ID    EX    MEM   WB
//     addi              IF    ID    ID*   EX    MEM        (* = stalled)
//     bubble                        EX->  MEM   WB
//
//   Now the addi reaches EX in cycle 5, by which time the lw is in WB and
//   ResultW carries the loaded word. The MEM/WB forwarding path that already
//   exists picks it up with no further help. Stalling did not REPLACE
//   forwarding - it bought forwarding the one cycle it needed to become
//   applicable.
//
//   WHAT "STALLING" PHYSICALLY MEANS - THREE SIMULTANEOUS ACTIONS
//     1. StallF: the PC must not advance, or the next instruction is lost.
//     2. StallD: the IF/ID register must HOLD, so the consumer sits in decode
//        for a second cycle and re-reads its operands.
//     3. FlushE: the ID/EX register must be CLEARED, not held. If it held, the
//        consumer would be issued into EX twice - executing once with the bad
//        value and once with the good one. Clearing injects a bubble (an
//        all-zeros control word = a harmless NOP) into EX instead.
//
//     Points 2 and 3 together are the part people get wrong: the front of the
//     pipe freezes while the back of the pipe keeps draining, and the gap
//     that opens between them has to be filled with something inert.
//
//=============================================================================
// HAZARD 2 - CONTROL. THE BRANCH DELAY SLOTS, NOW FIXED IN HARDWARE
//
//   PCSrcE (branch taken) is not known until the branch reaches EX. By then
//   fetch has already pulled in the two instructions physically following the
//   branch in memory:
//
//     cycle:        1     2     3
//     beq           IF    ID    EX     <- PCSrcE valid only now
//     beq+4               IF    ID     <- already in the pipe, WRONG PATH
//     beq+8                     IF     <- already in the pipe, WRONG PATH
//
//   Until now this core had no flush logic, so those two ran, and
//   src/program.hex had to place two NOPs after every taken branch to make
//   that harmless. That workaround is now GONE: FlushD kills the instruction
//   in IF/ID and FlushE kills the one in ID/EX, both at the same clock edge
//   that redirects the PC.
//
//   Note that a taken branch still COSTS two cycles - the pipeline is two
//   instructions emptier than it could have been. Flushing does not make
//   branches free; it makes them CORRECT without help from the programmer.
//   Making them cheap needs branch prediction, which this core does not have.
//
//   A NOT-taken branch costs nothing and flushes nothing: the two instructions
//   already fetched are the ones that should run anyway.
//
//=============================================================================
// WHY THERE IS NO THIRD HAZARD TO HANDLE
//
//   WAR and WAW hazards cannot occur in this design. Every instruction reads
//   its registers in ID and writes them in WB, in strict program order, and
//   nothing ever completes out of order. A later instruction therefore can
//   never write a register before an earlier one reads it (WAR), and two
//   writes can never land out of sequence (WAW). Those hazards appear only in
//   out-of-order or multi-cycle-execute machines. Worth stating explicitly so
//   their absence reads as a conclusion rather than an oversight.
//
//   Structural hazards are also absent by construction: instruction memory and
//   data memory are physically separate (a Harvard split), so IF and MEM never
//   compete for one memory port. In a shared-memory (von Neumann) design this
//   module would need a fourth stall condition.
//=============================================================================

module Hazard_Unit (
    // ---- what is currently in the DECODE stage ----------------------------
    input  wire [4:0] Rs1D,        // register numbers the decode-stage
    input  wire [4:0] Rs2D,        //   instruction is about to read

    // ---- what is currently in the EXECUTE stage ---------------------------
    input  wire [4:0] RdE,         // register the EX instruction will write
    input  wire       ResultSrcE,  // 1 = that EX instruction is a LOAD
    input  wire       PCSrcE,      // 1 = that EX instruction is a TAKEN branch

    // ---- the four control outputs -----------------------------------------
    output wire       StallF,      // hold the PC
    output wire       StallD,      // hold the IF/ID register
    output wire       FlushD,      // clear the IF/ID register
    output wire       FlushE       // clear the ID/EX register (inject a bubble)
);

    //-------------------------------------------------------------------------
    // LOAD-USE DETECTION
    //
    //   "The instruction in EX is a load, AND the instruction in DECODE wants
    //    to read the very register that load is going to write."
    //
    // ResultSrcE IS the load flag. In this core ResultSrc means "write-back
    // value comes from memory rather than the ALU", and lw is the only
    // instruction that sets it - so it doubles as "is a load" for free,
    // with no extra decoding. (If this core ever gains other memory-sourced
    // instructions, e.g. lb/lh, they set the same bit and are covered
    // automatically. That is a happy accident worth noticing, not a design
    // I would rely on without re-checking.)
    //
    // WHY RdE != 0 IS CHECKED
    //   `lw x0, 0(x2)` is legal RV32I - a load whose result is discarded.
    //   Register_file.v refuses to write x0, so nothing downstream can ever
    //   observe that load's data, and stalling for it would waste a cycle for
    //   no benefit. This guard also stops a decode-stage instruction whose
    //   rs1/rs2 fields read as 0 (very common - every `addi rd, x0, imm`)
    //   from being mistaken for a dependent.
    //
    // A KNOWN, ACCEPTED IMPRECISION - THE FALSE STALL
    //   Rs2D is taken straight from InstrD[24:20] without asking whether the
    //   instruction actually HAS an rs2 operand. For an I-type instruction
    //   (addi, lw) those five bits are part of the immediate, not a register
    //   number. If that immediate slice happens to equal RdE, this unit sees a
    //   dependency that does not exist and stalls one unnecessary cycle.
    //
    //   This is CORRECT but not OPTIMAL: a stall never produces a wrong
    //   answer, it only costs throughput. Eliminating it would mean piping a
    //   "uses rs2" bit out of the decoder, which is real extra work for a rare
    //   1-cycle saving. The textbook designs (Harris & Harris, Patterson &
    //   Hennessy) make exactly the same trade. Documented here so that anyone
    //   counting cycles in a waveform and finding one more stall than they
    //   predicted knows this is the reason, and that it is deliberate.
    //-------------------------------------------------------------------------
    wire lwStall;

    assign lwStall = ResultSrcE
                  && (RdE != 5'b00000)
                  && ((RdE == Rs1D) || (RdE == Rs2D));

    //-------------------------------------------------------------------------
    // THE FOUR OUTPUTS
    //
    // StallF / StallD  - freeze the front of the pipe for one cycle.
    // FlushE           - fires for EITHER reason:
    //                      * a load-use stall, to fill the gap the freeze
    //                        opens up with a bubble;
    //                      * a taken branch, to kill the wrong-path
    //                        instruction that already reached decode.
    //                    Both cases want the same thing - an all-zeros control
    //                    word in ID/EX - so they share one output.
    // FlushD           - taken branch only. There is nothing to flush in IF/ID
    //                    for a load-use stall; that register is being HELD, and
    //                    holding it is the entire point.
    //
    // CAN StallD AND FlushD BE HIGH TOGETHER?
    //   No, and it is worth understanding why rather than just adding priority
    //   logic. Both lwStall and PCSrcE are statements about THE SAME
    //   instruction - the one currently in EX. That instruction is either a
    //   load or a taken branch; it cannot be both, because they are different
    //   opcodes. So the two conditions are mutually exclusive by construction.
    //
    //   Decode_Cycle.v and Fetch_Cycle.v still write their flush check ABOVE
    //   their stall check, giving flush priority. That costs nothing and means
    //   the RTL stays safe if a future instruction (say a load that also
    //   branches, or a trap) ever breaks the mutual exclusion.
    //-------------------------------------------------------------------------
    assign StallF = lwStall;
    assign StallD = lwStall;
    assign FlushE = lwStall | PCSrcE;
    assign FlushD = PCSrcE;

endmodule
