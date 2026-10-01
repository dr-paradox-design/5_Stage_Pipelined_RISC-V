module Data_Memory(A,WD,clk,rst,WE,RD);

    input [31:0] A,WD;
    input clk,rst;
    input [3:0] WE;   //CHANGED: one write-enable per BYTE lane (was a single bit).
                      //Load_Store_Unit.v turns sb/sh/sw into these enables.

    output [31:0] RD;

    //CREATION OF MEMEORY
    reg [31:0] Mem[1023:0]; //declaring memory of 1024 words of 32 bits each
    integer k;

//CHANGED: added zero-init. Data memory used to start as all X, so any lw from an
//address that had not been written yet returned X and smeared X through the register
//file and the waveform. Starting at 0 matches how the instruction memory now behaves.
initial begin
    for (k = 0; k < 1024; k = k + 1)
        Mem[k] = 32'h00000000;
end

//read - always the whole word; Load_Store_Unit picks out the byte/half it needs
assign RD = (WE == 4'b0000) ? Mem[A[31:2]] : 32'h00000000;

//write - only the enabled byte lanes change, the rest of the word is kept
always @(posedge clk) begin
    if (WE[0]) Mem[A[31:2]][7:0]   <= WD[7:0];
    if (WE[1]) Mem[A[31:2]][15:8]  <= WD[15:8];
    if (WE[2]) Mem[A[31:2]][23:16] <= WD[23:16];
    if (WE[3]) Mem[A[31:2]][31:24] <= WD[31:24];
end

endmodule
