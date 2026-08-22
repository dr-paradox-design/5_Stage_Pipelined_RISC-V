//=============================================================================
// Pipeline_Top_TestBench.v  -  self-checking regression for the 5-stage core
//=============================================================================
//
// HOW TO RUN
//     cd src
//     iverilog -I ../single_core -o out.vvp Pipeline_Top_TestBench.v
//     vvp out.vvp
//     gtkwave Pipeline_Top_TestBench.vcd      (optional)
//
//   The -I flag is required. See the include-strategy note at the top of
//   Pipeline_Top.v for why a plain relative path does not work.
//
// WHAT IT CHECKS
//   The same 12 architectural results as the single-cycle regression, against
//   the same expected values. That equivalence is the whole point: the two
//   cores differ in SCHEDULE, not in what the program computes. If a pipeline
//   bug exists, these 12 numbers are where it shows up.
//
//   The check is a direct hierarchical peek into the register file array
//   rather than a waveform eyeball, so the run reports PASS/FAIL by itself.
//
// A NOTE ON THE $readmemh WARNING
//   vvp prints "Not enough words in the file for the requested range". Expected
//   and harmless - program.hex is 20 words, instruction memory is 1024, and the
//   remainder was already zero-filled (which decodes to a harmless NOP).
//=============================================================================

`include "Pipeline_Top.v"

module Pipeline_Top_TestBench();

    reg clk = 1'b1, rst;
    integer errors = 0;

    Pipeline_Top DUT (
        .clk (clk),
        .rst (rst)
    );

    initial begin
        $dumpfile("Pipeline_Top_TestBench.vcd");
        $dumpvars(0, Pipeline_Top_TestBench);
    end

    // 100 time-unit clock period -> rising edges at t = 100, 200, 300, ...
    always begin
        #50 clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Compares one architectural register against its expected value.
    //
    // The hierarchical path is one level deeper than in the single-cycle
    // testbench: there, the register file was a direct child of the top module.
    // Here it lives inside the DECODE stage, because in a pipeline the register
    // file belongs to ID (it is read there) even though WB drives its write
    // port. Hence  DUT.Decode.Register_file.Register[n].
    //-------------------------------------------------------------------------
    task check_reg;
        input [4:0]  num;
        input [31:0] expected;
        begin
            if (DUT.Decode.Register_file.Register[num] !== expected) begin
                $display("  FAIL: x%0d = %0d (expected %0d)",
                         num, DUT.Decode.Register_file.Register[num], expected);
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

        //---------------------------------------------------------------------
        // HOW LONG TO WAIT - the pipeline needs noticeably longer than the
        // single-cycle core, and it is worth knowing exactly why.
        //
        // rst releases at t=125, so the first real rising edge is t=200 and
        // fetch slot i occupies (100+100i, 200+100i). An instruction's register
        // write commits four stages later, at:
        //
        //        t = 600 + 100*i
        //
        // The last instruction to retire is  addi x12, x0, 7  at address 0x4c.
        // It is FETCH SLOT 18, not 19: the taken branch at slot 15 redirects
        // the PC at t=1900, so slot 18 fetches 0x4c and address 0x48 is never
        // fetched at all. Its write therefore commits at:
        //
        //        t = 600 + 1800 = 2400
        //
        // Two extra costs versus the single-cycle core, both structural:
        //   - PIPELINE FILL: nothing retires until t=600 (4 dead cycles while
        //     the first instruction walks down the pipe).
        //   - THE NOPs: 5 of the 20 program words exist purely to space out
        //     hazards, and each still costs a full cycle.
        // Neither is a throughput loss - one instruction still completes every
        // cycle once the pipe is full.
        //
        // Wait comfortably past 2400 before sampling.
        //---------------------------------------------------------------------
        #2500;   // now t = 2625

        $display("=== 5-stage pipelined RV32I regression (src/program.hex) ===");
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
        check_reg(11,  0); //taken beq + 2 delay slots skipped addi x11, x0, 99
        check_reg(12,  7); //execution resumed at the branch target

        if (errors == 0)
            $display("RESULT: PASS - all 12 checks passed");
        else
            $display("RESULT: FAIL - %0d check(s) failed", errors);

        $finish;
    end

endmodule
