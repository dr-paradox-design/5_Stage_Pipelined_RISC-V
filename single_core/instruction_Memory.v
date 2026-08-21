module instruction_Memory(A, rst, RD);
    
    input [31:0] A;
    input rst;

    output [31:0] RD;

    //CREATION OF MEMEORY
    //CHANGED: declared ascending [0:1023] rather than [1023:0]. Indexing is identical,
    //but $readmemh warns about ambiguous fill direction on a descending memory.
    reg [31:0] Mem[0:1023]; //declaring memory of 1024 words of 32 bits each
    integer j;

    //a address me padi hui jo bhi value haisko read karna hai
    assign RD = (rst == 1'b0) ? 32'h00000000 : Mem[A[31:2]]; //if rst is 0 then RD=0 else RD=Mem[A[31:2]]; //A[31:2] means we are using the address from 0 to 1023 and each address is of 4 bytes so we are using A[31:2] to get the address of the instruction

    //CHANGED: the test program used to be hardcoded here as a single Mem[0] = ...
    //assignment, so trying a different program meant editing and recompiling the RTL.
    //It is now loaded from program.hex, which keeps test programs out of the design.
    initial begin
        //zero-fill first so untouched locations read as 32'h00000000 (a harmless NOP:
        //opcode 7'b0000000 asserts neither RegWrite nor MemWrite) instead of X
        for (j = 0; j < 1024; j = j + 1)
            Mem[j] = 32'h00000000;

        //iverilog warns "Not enough words in the file for the requested range" here -
        //that is expected and harmless: the program is far shorter than 1024 words and
        //everything past it was already zero-filled above.
        $readmemh("program.hex", Mem);
    end

endmodule