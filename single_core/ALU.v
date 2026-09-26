module ALU(A,B,ALUControl,Result,Z,N,C,V);
    //declaring inputs and outputs
    input [31:0] A,B;
    input [2:0] ALUControl;
    output [31:0] Result;
    output Z,N,C,V;


    //declaring internal WIRE
    wire [31:0] a_and_b;
    wire [31:0] a_or_b;
    wire [31:0] not_b;

    wire [31:0] mux1;
    wire [31:0] sum;
    wire [31:0] mux_2;
    wire [31:0] slt;


    wire Cout;

    //logic design 
    
    //and operation
    assign a_and_b = A & B;

    //or operation  
    assign a_or_b = A | B;  

    //not operation
    assign not_b = ~B;

    //ternary operator If ALUControl is 1, mux1 gets the value of not_b
    assign mux1 = (ALUControl[0] == 1'b0) ? B : not_b; //ALUControl[0] means it is of 1 bit 

    //addition&subtraction operation then concatination(combine multiple bit or signal into one larger signal using curly braces) of the carry out and sum to get the final result 
    assign {Cout, sum} = A + mux1 + ALUControl[0];

    //SET-LESS-THAN (signed).
    //
    //FIX: this was  {31'b0, sum[31]}  - the raw sign bit of A-B, with no
    //overflow correction. That is right for most operands and WRONG for exactly
    //the ones where the subtraction overflows the signed range, because then
    //the sign bit is the opposite of the true comparison. Example:
    //    A = 0x80000000 (-2147483648), B = 1
    //    A - B overflows and computes 0x7FFFFFFF, whose sign bit is 0,
    //    so the old code answered "not less" when A really is less.
    //
    //XORing in V repairs it: V is set exactly when the subtraction overflowed,
    //which is exactly when the sign bit lies. This is the same N^V expression
    //Branch_Condition.v uses for blt, and it must be - slt and blt ask the
    //identical question and are required to give identical answers. Before this
    //fix a program could see  slt x5,a,b  return 0 while  blt a,b,L  was taken,
    //on the same operands, in the same core.
    //
    //Note V is declared further down the file. Order does not matter for
    //continuous assignments - they are wires, not statements.
    assign slt = {31'b0, sum[31] ^ V};

    //designing 4by1 mux
    assign mux_2 = (ALUControl[2:0] == 3'b000) ? sum : 
                   (ALUControl[2:0] == 3'b001) ? sum : 
                   (ALUControl[2:0] == 3'b010) ? a_and_b : 
                   (ALUControl[2:0] == 3'b011) ? a_or_b :
                   (ALUControl[2:0] == 3'b101) ? slt  : 
                   32'h00000000; //if ALUControl is 000 then sum is selected, if ALUControl is 001 then sum is selected, if ALUControl is 010 then a_and_b is selected, if ALUControl is 011 then a_or_b is selected, if ALUControl is 101 then slt is selected, else 0 is selected              
    assign Result = mux_2;

    //flags asssign
    assign Z = &(~Result); //if result is zero then Z=1 else Z=0 
    assign N = Result[31]; //if result is negative then N=1 else N=0
    assign C = Cout & (~ALUControl[1]);    //if there is a carry out then C=1 else C=0
    assign V =(~ALUControl[1]) & (A[31] ^ sum[31] ) & (~(A[31]^B[31]^ALUControl[0])); //if there is an overflow then V=1 else V=0   

    
    
    
endmodule