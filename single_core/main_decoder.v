module main_decoder(op,zero,RegWrite,MemWrite,ImmSrc,ALUSrc,ResultSrc,PCSrc,ALUOp);
    //input and output declaration
    input [6:0] op;
    input zero;
    output RegWrite,MemWrite,ALUSrc,PCSrc,ResultSrc ;
    output [1:0] ImmSrc,ALUOp;

    //internal write
    wire branch;

    assign RegWrite = (op == 7'b0110011) | (op == 7'b0000011) | (op == 7'b0010011) ? 1'b1 : 1'b0; //if op is 0110011 or 0000011 or 0010011 then RegWrite=1 else RegWrite=0
    assign MemWrite = (op == 7'b0100011) ? 1'b1 : 1'b0;
    assign ALUSrc = (op == 7'b0000011) | (op == 7'b0010011) ? 1'b1 : 1'b0; //if op is 0000011 or 0010011 or 0100011 then ALUSrc=1 else ALUSrc=0
    assign ResultSrc = (op == 7'b0000011) ? 1'b1 : 1'b0; //if op is 0000011 then ResultSrc=1 else ResultSrc=0
    assign branch= (op == 7'b1100011) ? 1'b1 : 1'b0   ; //if op is 1100011 and zero is 1 then Branch=1 else Branch=0
    assign ImmSrc = (op == 7'b0100011) ? 2'b01 :( op == 7'b1100011) ? 2'b10 : 2'b0;
    assign ALUOp = (op == 7'b0110011) ? 2'b10 : (op == 7'b1100011) ? 2'b01 : 2'b00;
    assign PCSrc = branch & zero; //if branch is 1 and zero is

    

endmodule