//=============================================================================
// Load_Store_Unit.v  -  byte / halfword / word lanes for loads and stores
//=============================================================================
//
// Data_Memory only knows WORDS: one 32-bit row per address A[31:2], plus four
// byte-enables saying which bytes of that row a store may overwrite. Every
// RV32I access narrower than a word is turned into that form here, so the
// memory itself never needs to know what funct3 is.
//
//   STORE side  rs2 + funct3 + addr[1:0]  ->  byte-enables + lane-aligned data
//     sb : copy rs2[7:0]  into all 4 lanes, enable only lane addr[1:0]
//     sh : copy rs2[15:0] into both halves, enable lanes 1:0 or 3:2
//     sw : rs2 as-is, enable all four lanes
//   Replicating the data into every lane means the store data never needs a
//   shifter - the byte-enables alone pick which copy actually lands.
//
//   LOAD side   word + funct3 + addr[1:0]  ->  the value rd should receive
//     lb / lh  : pick the byte / half, SIGN-extend  (funct3[2] = 0)
//     lbu / lhu: pick the byte / half, ZERO-extend  (funct3[2] = 1)
//     lw       : the whole word
//
// Misaligned accesses (lh/sh at an odd address, lw/sw not on a multiple of 4)
// are NOT supported - RV32I lets an implementation trap on them, and this core
// has no traps. They silently use the aligned lanes instead.
//
// Shared by both cores: Single_Cycle_Top.v and src/Memory_Cycle.v instance the
// same module, so the two cannot disagree about byte order or extension.
//=============================================================================

module Load_Store_Unit (
    input  wire [2:0]  funct3,      // instr[14:12] of the load or store
    input  wire [1:0]  addr_lo,     // byte offset inside the word: A[1:0]
    input  wire        MemWrite,    // 1 = this is a store
    input  wire [31:0] StoreData,   // rs2, as it came out of the register file
    input  wire [31:0] ReadWord,    // the full 32-bit row Data_Memory returned
    output wire [3:0]  ByteEnable,  // to Data_Memory: which lanes to write
    output wire [31:0] WriteData,   // to Data_Memory: rs2 copied into every lane
    output wire [31:0] LoadData     // to write-back: the extended load result
);

    //------------------------------------------------------------------ STORE
    wire [3:0] be_sb = 4'b0001 << addr_lo;
    wire [3:0] be_sh = addr_lo[1] ? 4'b1100 : 4'b0011;

    assign ByteEnable = !MemWrite              ? 4'b0000 :
                        (funct3[1:0] == 2'b00) ? be_sb   :   // sb
                        (funct3[1:0] == 2'b01) ? be_sh   :   // sh
                                                 4'b1111;    // sw

    assign WriteData  = (funct3[1:0] == 2'b00) ? {4{StoreData[7:0]}}  :
                        (funct3[1:0] == 2'b01) ? {2{StoreData[15:0]}} :
                                                 StoreData;

    //------------------------------------------------------------------- LOAD
    wire [7:0]  byte_sel = (addr_lo == 2'b00) ? ReadWord[7:0]   :
                           (addr_lo == 2'b01) ? ReadWord[15:8]  :
                           (addr_lo == 2'b10) ? ReadWord[23:16] :
                                                ReadWord[31:24];
    wire [15:0] half_sel = addr_lo[1] ? ReadWord[31:16] : ReadWord[15:0];

    // funct3[2] = 1 means "unsigned" (lbu, lhu): fill with 0 instead of the sign bit.
    wire byte_fill = ~funct3[2] & byte_sel[7];
    wire half_fill = ~funct3[2] & half_sel[15];

    assign LoadData = (funct3[1:0] == 2'b00) ? {{24{byte_fill}}, byte_sel} :   // lb / lbu
                      (funct3[1:0] == 2'b01) ? {{16{half_fill}}, half_sel} :   // lh / lhu
                                               ReadWord;                       // lw

endmodule
