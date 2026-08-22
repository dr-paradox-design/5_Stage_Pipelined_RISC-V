//=============================================================================
// Memory_Cycle.v  -  STAGE 4 of 5  (MEM)
//=============================================================================
//
// WHAT THIS STAGE DOES
//   Talks to the data memory, and nothing else. Exactly one instruction type
//   reads it (lw), exactly one writes it (sw), and every other instruction just
//   passes straight through untouched.
//
// WHY A WHOLE PIPELINE STAGE FOR SOMETHING MOST INSTRUCTIONS IGNORE
//   Because a pipeline runs at the speed of its SLOWEST stage, and every
//   instruction must visit every stage in the same order. Memory access is one
//   of the slowest operations in the datapath, so it gets its own stage rather
//   than being bolted onto the end of EX and dragging the whole clock period
//   down. add pays a cycle of latency it does not need, but latency is not what
//   a pipeline optimises - THROUGHPUT is. One instruction still finishes every
//   cycle regardless.
//
// ADDRESS VS DATA - THE TWO THINGS ARRIVING HERE
//   ALU_ResultM is the ADDRESS. For lw/sw the ALU spent its cycle in EX adding
//   base register + offset immediate. For everything else the same wire carries
//   the actual arithmetic answer, which is why it continues on to WB.
//   WriteDataM is the DATA to store - the rs2 value, which bypassed the ALU
//   completely back in EX.
//
// A TIMING SUBTLETY WORTH UNDERSTANDING
//   Data_Memory writes on the rising clock edge but reads combinationally. A
//   store commits its write at the edge that ENDS its MEM cycle; a load one
//   instruction behind it does its combinational read DURING the very next
//   cycle - i.e. after that edge. So  sw  followed immediately by  lw  from the
//   same address works with no NOPs between them. It is tight, and it only
//   works because the write happens at the boundary and the read happens across
//   the interval that follows. This is worked through in src/program.hex.
//=============================================================================

module Memory_Cycle (
    input  wire        clk,
    input  wire        rst,          // ACTIVE-LOW

    // ---- forward path in, from the EX/MEM register ------------------------
    input  wire        RegWriteM,
    input  wire        MemWriteM,
    input  wire        ResultSrcM,
    input  wire [31:0] ALU_ResultM,  // the address for lw/sw, else the answer
    input  wire [31:0] WriteDataM,   // rs2 - the value a store writes
    input  wire [4:0]  RdM,

    // ---- forward path out, into write-back (outputs of MEM/WB) ------------
    output reg         RegWriteW,
    output reg         ResultSrcW,
    output reg  [31:0] ALU_ResultW,
    output reg  [31:0] ReadDataW,    // what a load pulled out of memory
    output reg  [4:0]  RdW
);

    //-------------------------------------------------------------------------
    // The only combinational signal produced in this stage.
    //-------------------------------------------------------------------------
    wire [31:0] ReadDataM;

    //-------------------------------------------------------------------------
    // DATA MEMORY - reused unmodified from single_core/.
    //
    // MemWriteM is the store enable, and it is the reason control signals had
    // to be pipelined at all: if this port were wired to the decoder's raw
    // MemWrite output, it would be showing the intent of whatever instruction
    // happened to be in DECODE right now - three instructions too early.
    // Because MemWriteM travelled through two pipeline registers, it lines up
    // perfectly with the address and data of the store it belongs to.
    //
    // Note also that Data_Memory forces RD to 0 whenever WE is high, so a store
    // never produces meaningful read data. That is fine: a store has
    // RegWrite = 0, so nothing downstream ever looks at ReadData for it.
    //-------------------------------------------------------------------------
    Data_Memory Data_Memory (
        .clk (clk),
        .rst (rst),
        .A   (ALU_ResultM),   // address
        .WD  (WriteDataM),    // data in  (stores)
        .WE  (MemWriteM),     // store enable
        .RD  (ReadDataM)      // data out (loads)
    );

    //=========================================================================
    // MEM/WB PIPELINE REGISTER  -  the last one in the pipe
    //
    // MemWriteM dies here: the memory has been written, the signal has no
    // further customers. Everything else moves on.
    //
    // BOTH candidate write-back values are carried forward - ALU_ResultW and
    // ReadDataW - even though write-back will only ever use one of them. That
    // is a deliberate trade: selecting late (in WB) keeps the mux off this
    // stage's critical path, which already contains the memory access. Doing
    // the select here would mean memory-read -> mux -> flip-flop all inside one
    // clock period. Carrying 32 extra flip-flops is the cheaper of the two.
    // ResultSrcW rides along to tell WB which one to pick.
    //
    // RdW and RegWriteW leave this module and loop all the way back to the
    // register file in Decode_Cycle.v. This is the completion of the longest
    // journey in the design: RegWrite was decoded in ID and has now travelled
    // through three pipeline registers to arrive back where it started.
    //=========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            RegWriteW   <= 1'b0;
            ResultSrcW  <= 1'b0;
            ALU_ResultW <= 32'h00000000;
            ReadDataW   <= 32'h00000000;
            RdW         <= 5'b00000;
        end
        else begin
            RegWriteW   <= RegWriteM;
            ResultSrcW  <= ResultSrcM;
            ALU_ResultW <= ALU_ResultM;
            ReadDataW   <= ReadDataM;
            RdW         <= RdM;
        end
    end

endmodule
