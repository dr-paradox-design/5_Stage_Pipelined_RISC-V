module Data_Memory(A,WD,clk,rst,WE,RD);

    input [31:0] A,WD;
    input clk,rst,WE;

    output [31:0] RD;

    //CREATION OF MEMEORY
    reg [31:0] Mem[1023:0]; //declaring memory of 1024 words of 32 bits each

//read
assign RD = (WE ==1'b0) ? Data_MEM[A] : 32'h00000000; 

//write
always @(posedge clk) begin
    if(WE)
    begin
        Mem[A] <= WD; //if WE is 1 then write WD to Mem[A]
    end

endmodule