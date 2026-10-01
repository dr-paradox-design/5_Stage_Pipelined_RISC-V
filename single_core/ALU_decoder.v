module  ALU_decoder(ALUOp,funct7,funct3,op5,ALUControl);
    input op5, funct7;          //funct7 here is just instr[30], the only funct7 bit RV32I uses
    input [2:0] funct3;
    input [1:0] ALUOp;
    output [3:0] ALUControl;    //WIDENED from [2:0] - see ALU.v for the full encoding

    //INTERNAL WIRE
    wire [1:0] concatination;

    assign concatination = {op5,funct7}; //concatination of op5 and funct7 to get a 2 bit signal

    //ALUOp = 10 covers BOTH R-type (op5=1) and I-type ALU ops (op5=0), because
    //funct3 means the same operation in both. instr[30] is the one awkward bit:
    //
    //  funct3 000 : instr[30] means "sub" ONLY for R-type. In an I-type it is
    //               just an immediate bit (set for any negative imm), so sub
    //               needs {op5,funct7} == 11. addi x1,x1,-2 must stay an add.
    //  funct3 101 : instr[30] picks sra over srl in BOTH forms. srai encodes it
    //               in imm[10], which lands on the same instruction bit 30, so
    //               here op5 must NOT be consulted.
    //
    //Every other funct3 ignores instr[30] entirely.
    assign ALUControl = (ALUOp == 2'b00) ? 4'b0000 :                                      //add  (lw/sw address)
                        (ALUOp == 2'b01) ? 4'b0001 :                                      //sub  (branches)
                        (ALUOp == 2'b10) & (funct3 == 3'b000) & (concatination != 2'b11) ? 4'b0000 : //add  / addi
                        (ALUOp == 2'b10) & (funct3 == 3'b000) & (concatination == 2'b11) ? 4'b0001 : //sub
                        (ALUOp == 2'b10) & (funct3 == 3'b001) ? 4'b1000 :                 //sll  / slli
                        (ALUOp == 2'b10) & (funct3 == 3'b010) ? 4'b0101 :                 //slt  / slti
                        (ALUOp == 2'b10) & (funct3 == 3'b011) ? 4'b0111 :                 //sltu / sltiu
                        (ALUOp == 2'b10) & (funct3 == 3'b100) ? 4'b0100 :                 //xor  / xori
                        (ALUOp == 2'b10) & (funct3 == 3'b101) & ~funct7 ? 4'b1001 :       //srl  / srli
                        (ALUOp == 2'b10) & (funct3 == 3'b101) &  funct7 ? 4'b1010 :       //sra  / srai
                        (ALUOp == 2'b10) & (funct3 == 3'b110) ? 4'b0011 :                 //or   / ori
                        (ALUOp == 2'b10) & (funct3 == 3'b111) ? 4'b0010 :                 //and  / andi
                        4'b0000;

endmodule
