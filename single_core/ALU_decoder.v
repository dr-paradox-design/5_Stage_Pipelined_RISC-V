module  ALU_decoder(ALUOp,funct7,funct3,op5,ALUControl);
    input op5, funct7;
    input [2:0] funct3;
    input [1:0] ALUOp;
    output [2:0] ALUControl;

    //INTERNAL WIRE
    wire [1:0] concatination;

    assign concatination = {op5,funct7}; //concatination of op5 and funct7 to get a 2 bit signal

    assign ALUControl = (ALUOp == 2'b00) ? 3'b000 :
                        (ALUOp == 2'b01) ? 3'b001 :
      ///               (ALUOp == 2'b10) & (function3 == 3'b000) & (concatination == 2'b00 ^ 2'b01 ^ 2'b10) ? 3'b000 : more optimized is the bottom one 
                        (ALUOp == 2'b10) & (funct3 == 3'b000) & (concatination != 2'b11) ? 3'b000 :
                        (ALUOp == 2'b10) & (funct3 == 3'b000) & (concatination == 2'b11) ? 3'b001 :
                        (ALUOp == 2'b10) & (funct3 == 3'b010) ? 3'b101:
                        (ALUOp == 2'b10) & (funct3 == 3'b110) ? 3'b011:
                        (ALUOp == 2'b10) & (funct3 ==3'b111) ? 3'b010:
                        3'b000;



endmodule