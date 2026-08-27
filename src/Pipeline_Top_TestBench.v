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
//   17 architectural results. The first 12 are the same values the single-
//   cycle regression checks, so the two cores can still be compared directly -
//   they differ in SCHEDULE, not in what the program computes.
//
//   The 5 additional registers (x13..x17) exist purely to test hazard
//   hardware that the single-cycle core does not have and cannot need. Each
//   one is written by an instruction that would produce a different, specific
//   wrong value if one hazard mechanism were broken - see the table in
//   src/program.hex. That is what makes this a hazard regression rather than
//   an arithmetic one.
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
        // HOW LONG TO WAIT
        //
        // rst releases at t=125, so the first real rising edge is t=200 and
        // FETCH SLOT s occupies the interval (100+100s, 200+100s). An
        // instruction fetched in slot s commits its register write four stages
        // later, at:
        //
        //        t = 600 + 100*s
        //
        // FETCH SLOT IS NOT THE SAME AS ADDRESS INDEX, and this program makes
        // them diverge twice - once in each direction:
        //
        //   THE STALL (+1 slot).  The load-use pair at idx4/idx5 costs one
        //   cycle. During interval 6 the lw is in EX and the dependent addi is
        //   in ID, so Hazard_Unit asserts lwStall: the PC holds, IF/ID holds,
        //   and a bubble enters ID/EX. Address 0x18 (idx6) is presented in
        //   interval 6 but NOT latched, then re-presented and latched in
        //   interval 7. So from idx6 onward, slot = idx + 1.
        //
        //   THE BRANCH (-2 slots).  idx13 (0x34) is therefore fetched in slot
        //   14, is in EX during interval 16, and asserts PCSrcE there. At the
        //   edge ending interval 16 the PC is redirected to 0x40 and both
        //   wrong-path instructions are flushed. Interval 17 fetches 0x40
        //   (idx16). So from idx16 onward, slot = idx + 1 again - the two
        //   flushed slots were consumed by instructions that never committed,
        //   not skipped.
        //
        // Putting it together, the LAST instruction to retire is
        //   idx19  add x17, x12, x0   at 0x4c, fetched in SLOT 20:
        //
        //        t = 600 + 100*20 = 2600
        //
        // Three costs versus the single-cycle core, all structural, none of
        // them a throughput loss once the pipe is full:
        //   - PIPELINE FILL : nothing retires until t=600 (4 dead cycles).
        //   - ONE STALL     : the single load-use pair, 1 cycle.
        //   - ONE BRANCH    : 2 flushed cycles on the one taken branch.
        // Note what is NOT on that list any more: hand-scheduled NOPs. The
        // previous version of this program spent 5 whole cycles on them.
        //
        // Wait comfortably past 2600 before sampling.
        //---------------------------------------------------------------------
        #2700;   // now t = 2825

        $display("=== 5-stage pipelined RV32I regression (src/program.hex) ===");

        $display("-- baseline arithmetic (same 12 values as the single-cycle core)");
        check_reg(1,   5); //addi x1, x0, 5
        check_reg(2,   3); //addi x2, x0, 3
        check_reg(3,   8); //add  x3, x1, x2  - needs BOTH forwarding paths
        check_reg(4,   2); //sub  x4, x1, x2
        check_reg(5,   1); //and  x5, x1, x2
        check_reg(6,   7); //or   x6, x1, x2
        check_reg(7,   1); //slt  x7, x2, x1  (3 < 5)
        check_reg(8,   0); //slt  x8, x1, x2  (5 < 3 is false)
        check_reg(9,   8); //lw   x9, 0(x0)   - needs store-data forwarding
        check_reg(10,  1); //not-taken beq fell through to addi x10, x0, 1
        check_reg(11,  0); //taken beq flushed addi x11, x0, 99 out of ID/EX
        check_reg(12,  7); //execution resumed at the branch target

        $display("-- hazard hardware (would fail on the pre-hazard-unit build)");
        check_reg(13,  9); //LOAD-USE STALL   : addi x13, x9, 1 right after lw
        check_reg(14,  0); //BRANCH FLUSH IF/ID: addi x14, x0, 88 never ran
        check_reg(15,  1); //addi x15, x0, 1  (spacer)
        check_reg(16,  2); //addi x16, x0, 2  (spacer)
        check_reg(17,  7); //DECODE BYPASS    : add x17, x12, x0 at distance 3

        if (errors == 0)
            $display("RESULT: PASS - all 17 checks passed");
        else
            $display("RESULT: FAIL - %0d check(s) failed", errors);

        $finish;
    end

endmodule
