module instruction_Memory(A, rst, RD);
    
    input [31:0] A;
    input rst;

    output [31:0] RD;

    //CREATION OF MEMEORY
    reg [31:0] Mem[1023:0]; //declaring memory of 1024 words of 32 bits each


    //a address me padi hui jo bhi value haisko read karna hai
    assign RD = (rst == 1'b0) ? 32'h00000000 : Mem[A[31:2]]; //if rst is 0 then RD=0 else RD=Mem[A[31:2]]; //A[31:2] means we are using the address from 0 to 1023 and each address is of 4 bytes so we are using A[31:2] to get the address of the instruction 
    
    initial begin
        //Mem[0] = 32'hFFC4A303; 
        //Mem[1] = 32'h00832383;  
        Mem[0] = 32'h0064A423;
        //        Mem[0] = 32'h00000000; 

    end

endmodule