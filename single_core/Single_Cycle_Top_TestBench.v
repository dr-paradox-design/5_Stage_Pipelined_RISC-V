//CHANGED: this include is new. Without it `iverilog Single_Cycle_Top_TestBench.v`
//failed with "Unknown module type: Single_Cycle_Top", because nothing in the
//testbench pulled in the top-level design.
`include "Single_Cycle_Top.v"

module Single_Cycle_Top_TestBench();

    reg clk=1'b1,rst;
    integer errors = 0;

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

    //CHANGED: compares one register against its expected value and counts mismatches,
    //so the run reports PASS/FAIL on its own instead of needing a GTKWave eyeball.
    task check_reg;
        input [4:0]  num;
        input [31:0] expected;
        begin
            if (Single_Cycle_Top.Register_file.Register[num] !== expected) begin
                $display("  FAIL: x%0d = %0d (expected %0d)",
                         num, Single_Cycle_Top.Register_file.Register[num], expected);
                errors = errors + 1;
            end
            else
                $display("  ok  : x%0d = %0d", num, expected);
        end
    endtask

    initial begin
       rst = 1'b0;
       #125;
       rst = 1'b1;

       //Clock period is 100 time units (posedges at t=100,200,...) and rst releases
       //before t=200, so the first instruction retires at t=200 and one more every
       //100 after that. program.hex executes 14 instructions (one is branched over),
       //so the last write commits at t=1500 - wait comfortably past it before checking.
       #1900;

       $display("=== single-cycle RV32I regression (program.hex) ===");
       check_reg(1,   5); //addi x1, x0, 5
       check_reg(2,   3); //addi x2, x0, 3
       check_reg(3,   8); //add  x3, x1, x2
       check_reg(4,   2); //sub  x4, x1, x2
       check_reg(5,   1); //and  x5, x1, x2
       check_reg(6,   7); //or   x6, x1, x2
       check_reg(7,   1); //slt  x7, x2, x1  (3 < 5)
       check_reg(8,   0); //slt  x8, x1, x2  (5 < 3 is false)
       check_reg(9,   8); //lw   x9, 0(x0)   - reads back what sw stored
       check_reg(10,  1); //not-taken beq fell through to addi x10, x0, 1
       check_reg(11,  0); //taken beq skipped addi x11, x0, 99
       check_reg(12,  7); //execution resumed at the branch target

       if (errors == 0)
           $display("RESULT: PASS - all 12 checks passed");
       else
           $display("RESULT: FAIL - %0d check(s) failed", errors);

       $finish;

    end

endmodule
