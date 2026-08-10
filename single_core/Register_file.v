module Register_file(A1,A2,A3,WD3,WE3,clk,rst,RD1,RD2);
input clk,rst,WE3;
input[4:0] A1,A2,A3;
input[31:0] WD3;

output[31:0] RD1,RD2;

//creation of memory
reg[31:0] Register[31:0];

// read functionality
assign RD1 = (!rst) ? 32'h00000000 : Register[A1]; //if rst is 0 then RD1=0 else RD1=Register[A1]
assign RD2 = (!rst) ? 32'h00000000 : Register[A2];

always @(posedge clk) begin
    if (!rst) begin

        if(WE3)
        begin
            Register[A3] <= WD3; //if WE3 is 1 then write WD3 to Register[A3]
        end
end
end

endmodule