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
       //100 after that.
       //
       //program.hex is now 42 instructions long. SIX of them are branched over
       //and never execute:
       //    0x34 (addi x11, 99)  skipped by the taken beq  at 0x30
       //    0x48 (addi x20, 55)  skipped by the taken bne  at 0x44
       //    0x5c (addi x23, 77)  skipped by the taken blt  at 0x58
       //    0x6c (addi x25, 66)  skipped by the taken bge  at 0x68
       //    0x74 (addi x26, 88)  skipped by the taken bgeu at 0x70
       //    0xa0 (addi x31, 99)  skipped by the taken blt  at 0x9c
       //
       //and the loop at 0x90..0x98 runs its 3-instruction body 31 times. So the
       //retired instruction count is
       //    36 straight-line  +  31*3 loop body  -  3 already counted  =  126
       //and the last write commits at
       //    t = 200 + 100*125 = 12700.
       //
       //Unlike the pipelined core there is no fill time, no stall and no flush to
       //account for - one instruction per cycle, always, and a taken branch costs
       //NOTHING. That last point is worth dwelling on now that a loop exists: the
       //same 3-instruction loop body costs 3 cycles per iteration here and 5 in
       //the pipeline, because every taken backward branch there flushes two
       //slots. The pipelined core is still far faster overall (its clock period
       //is a fraction of this one's), but on tight loops it gives back a chunk of
       //that win - which is precisely the gap branch prediction exists to close.
       //Compare this arithmetic with the fetch-slot trace in
       //src/Pipeline_Top_TestBench.v to see the trade in full.
       //
       //Wait comfortably past 12700 before checking.
       #13000;

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

       //Every check below FAILS on the pre-Branch_Condition build, where all six
       //B-type branches decoded as beq. See the PART 2 header in program.hex.
       $display("-- branch conditions (all would fail when bne/blt/... acted as beq)");
       check_reg(18, -1); //setup: 0xFFFFFFFF, the signed/unsigned discriminator
       check_reg(19,  1); //setup
       check_reg(20,  0); //bne  TAKEN     : as beq it would fall through -> 55
       check_reg(21,  1); //...and landed on the right target
       check_reg(22,  1); //bne  NOT taken : as beq it would branch -> 0
       check_reg(23,  0); //blt  TAKEN     : -1 < 1 signed, needs N^V -> else 77
       check_reg(24,  1); //bltu NOT taken : same bits unsigned, opposite answer
       check_reg(25,  0); //bge  TAKEN     : 1 >= -1 signed -> else 66
       check_reg(26,  0); //bgeu TAKEN     : 0xFFFFFFFF >= 1 unsigned -> else 88
       check_reg(27,  1); //...and landed on the right target
       check_reg(29,  1); //branch operands read correctly from the register file

       $display("-- loop + signed overflow (the only checks that can catch N vs N^V)");
       check_reg(30, 32'h80000000); //31 iterations of a real backward-branch loop
       check_reg(31,  0);           //blt on an OVERFLOWING subtraction was taken
       check_reg(28,  1);           //slt agrees with blt on the overflow case

       if (errors == 0)
           $display("RESULT: PASS - all 26 checks passed");
       else
           $display("RESULT: FAIL - %0d check(s) failed", errors);

       $finish;

    end

endmodule
