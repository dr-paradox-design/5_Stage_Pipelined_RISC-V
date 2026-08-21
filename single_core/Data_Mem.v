module Data_Memory(A,WD,clk,rst,WE,RD);

    input [31:0] A,WD;
    input clk,rst,WE;

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

//read
assign RD = (WE == 1'b0) ? Mem[A[31:2]] : 32'h00000000;

//write
always @(posedge clk) begin
    if(WE)
    begin
        Mem[A[31:2]] <= WD; //if WE is 1 then write WD to Mem[A]
    end

end

endmodule