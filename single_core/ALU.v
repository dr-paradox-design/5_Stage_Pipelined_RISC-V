module ALU(A,B,ALUControl,Result,Z,N,C,V);
    //declaring inputs and outputs
    input [31:0] A,B;
    input [3:0] ALUControl;   //WIDENED from [2:0]: 5 ops did not leave room for 10
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
    wire [31:0] sltu;
    wire [31:0] a_xor_b;
    wire [31:0] sll_r, srl_r, sra_r;
    wire [4:0]  shamt;


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

    //SET-LESS-THAN UNSIGNED. Same subtraction as slt, different reading of it:
    //for A - B computed as A + ~B + 1, the carry-out is 1 exactly when no
    //borrow happened, i.e. A >= B unsigned. So A < B unsigned is ~Cout. This is
    //the same fact Branch_Condition.v uses for bltu (taken = ~C).
    assign sltu = {31'b0, ~Cout};

    assign a_xor_b = A ^ B;

    //SHIFTER. RV32I only ever uses the low 5 bits of the shift amount, for both
    //the register form (rs2[4:0]) and the immediate form (imm[4:0] - the upper
    //imm bits of slli/srli/srai are an opcode extension, not part of shamt).
    //Using all of B would make  sll x,1,0xFFFFFFFF  give 0 instead of 1<<31.
    assign shamt = B[4:0];
    assign sll_r = A << shamt;
    assign srl_r = A >> shamt;
    assign sra_r = $signed(A) >>> shamt;   //>>> on a SIGNED operand copies the sign bit in

    //RESULT MUX. ALUControl encoding (ALU_decoder.v produces these):
    //   0000 add    0001 sub    0010 and    0011 or
    //   0100 xor    0101 slt    0111 sltu
    //   1000 sll    1001 srl    1010 sra
    //The original five codes are unchanged, so the flag logic below - which
    //keys off bit0 ("subtract") and bit1 ("logical op, no C/V") - still means
    //the same thing. slt and sltu both have bit0 = 1 so the adder subtracts.
    assign mux_2 = (ALUControl == 4'b0000) ? sum :
                   (ALUControl == 4'b0001) ? sum :
                   (ALUControl == 4'b0010) ? a_and_b :
                   (ALUControl == 4'b0011) ? a_or_b :
                   (ALUControl == 4'b0100) ? a_xor_b :
                   (ALUControl == 4'b0101) ? slt :
                   (ALUControl == 4'b0111) ? sltu :
                   (ALUControl == 4'b1000) ? sll_r :
                   (ALUControl == 4'b1001) ? srl_r :
                   (ALUControl == 4'b1010) ? sra_r :
                   32'h00000000;
    assign Result = mux_2;

    //flags asssign
    assign Z = &(~Result); //if result is zero then Z=1 else Z=0 
    assign N = Result[31]; //if result is negative then N=1 else N=0
    assign C = Cout & (~ALUControl[1]);    //if there is a carry out then C=1 else C=0
    assign V =(~ALUControl[1]) & (A[31] ^ sum[31] ) & (~(A[31]^B[31]^ALUControl[0])); //if there is an overflow then V=1 else V=0   

    
    
    
endmodule