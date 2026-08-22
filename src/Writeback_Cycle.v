//=============================================================================
// Writeback_Cycle.v  -  STAGE 5 of 5  (WB)
//=============================================================================
//
// WHAT THIS STAGE DOES
//   Picks which of two values the instruction should write into its destination
//   register, and hands it back to the register file. That is the entire stage:
//   one 32-bit 2-to-1 mux.
//
// WHY THERE IS NO PIPELINE REGISTER IN THIS FILE
//   Every other stage ends with a pipeline register because it has to hand work
//   to the stage after it. There is no stage after WB. The "register" that this
//   stage writes into is the register FILE itself, which is clocked, and it
//   lives in Decode_Cycle.v. So WB is purely combinational, and its output
//   ResultW goes backwards up the pipe to the register file's WD3 port.
//
//   That backward path is why the register file is drawn straddling ID and WB
//   in pipeline diagrams: read in ID, written from WB, one physical block.
//
// WHY THE MUX IS DOWN HERE AND NOT BACK IN MEM
//   Because putting it in MEM would stack "memory read -> mux -> flip-flop"
//   into a single clock period, on a stage that is already one of the slowest.
//   Carrying both candidates through MEM/WB costs 32 extra flip-flops and buys
//   a shorter critical path. See the comment on the MEM/WB register in
//   Memory_Cycle.v.
//
// WHO WRITES, AND WHEN
//   This stage does not decide WHETHER to write - RegWriteW does, and it is
//   passed straight through to the register file's write enable by
//   Pipeline_Top.v. Nor does it decide WHERE - RdW does. WB only decides WHAT.
//   The write itself lands on the next rising clock edge, inside
//   Register_file.v.
//
// THE ONE HAZARD FACT TO REMEMBER
//   That write lands FOUR stages after the instruction was decoded, and the
//   register file has no read/write bypass. So an instruction that reads this
//   register must be latched into ID/EX at a later edge than the write. Do the
//   counting and you get: the consumer must be at least 4 instruction slots
//   behind the producer - 3 NOPs in between. With forwarding hardware (a later
//   project stage) that gap collapses to zero, because the value would be
//   grabbed from these very wires instead of waiting for the register file.
//=============================================================================

module Writeback_Cycle (
    // ---- forward path in, from the MEM/WB register ------------------------
    input  wire        ResultSrcW,   // 0 = ALU result, 1 = memory read data
    input  wire [31:0] ALU_ResultW,  // answer computed by the ALU back in EX
    input  wire [31:0] ReadDataW,    // word a load pulled out of memory in MEM

    // ---- backward path out, to the register file in Decode_Cycle.v --------
    output wire [31:0] ResultW       // the value that will be written to RdW
);

    //-------------------------------------------------------------------------
    // RESULT-SOURCE MUX
    //
    // Identical to the single-cycle core's write-back mux, and driven by the
    // same decoder bit - only now that bit has taken three pipeline registers
    // to get here (ResultSrcE -> ResultSrcM -> ResultSrcW) so that it arrives
    // in the same cycle as the data it is selecting between.
    //
    //   lw                     -> ResultSrcW = 1 -> ReadDataW
    //   add/sub/and/or/slt/addi-> ResultSrcW = 0 -> ALU_ResultW
    //   sw, beq                -> RegWriteW = 0, so whatever this mux produces
    //                             is simply ignored by the register file.
    //-------------------------------------------------------------------------
    assign ResultW = ResultSrcW ? ReadDataW : ALU_ResultW;

endmodule
