module alu(A,B,ALUControl,Result);
    //declaring inputs and outputs
    input [31:0] A,B;
    input [3:0] ALUControl;
    output [31:0] Result;

    //declaring internal WIRE
    wire [31:0] a_and_b;
    wire [31:0] a_or_b;
    wire [31:0] not_b;

    wire [31:0] mux1;
    wire [31:0] sum;
    wire [31:0] mux2;

    //logic design 
    
    //and operation
    assign a_and_b = A & B;

    //or operation  
    assign a_or_b = A | B;  

    //not operation
    assign not_b = ~B;

    //ternary operator If ALUControl is 1, mux1 gets the value of not_b
    assign mux1 = (ALUControl[0] == 1'b0) ? B : not_b; //ALUControl[0] means it is of 1 bit 

    //addition&subtraction operation
    assign sum = A + mux1 + ALUControl[0]    ;

    //designing 4by1 mux
    assign mux_2 = (ALUControl[1:0] == 2'b00) ? sum : 
                   (ALUControl[1:0] == 2'b01) ? sum : 
                   (ALUControl[1:0] == 2'b10) ? a_and_b : 
                  
    assign Result = mux_2;
endmodule