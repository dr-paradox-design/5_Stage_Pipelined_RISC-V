module Single_Cycle_Top_TestBench();

    reg clk=1'b1,rst;

    Single_Cycle_Top Single_Cycle_Top(
        .clk(clk),
        .rst(rst)
    );

    initial begin
        $dumpfile("Single_Cycle_Top_TestBench.vcd");
        $dumpvars(0, Single_Cycle_Top_TestBench);
    end

    always
    begin
        #50 clk = ~clk;
    end

    initial begin
       rst = 1'b0;
       #125;
       rst = 1'b1;
       #500;
       $finish;
    
    end

endmodule