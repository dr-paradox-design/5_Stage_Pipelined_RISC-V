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

    //-------------------------------------------------------------------------
    // Same idea for one data-memory WORD (index = byte address / 4). Needed
    // once the register file filled up: newer tests store their results.
    //-------------------------------------------------------------------------
    task check_mem;
        input [9:0]  word;
        input [31:0] expected;
        begin
            if (DUT.Memory.Data_Memory.Mem[word] !== expected) begin
                $display("  FAIL: mem[%0d] = 0x%h (expected 0x%h)",
                         word, DUT.Memory.Data_Memory.Mem[word], expected);
                errors = errors + 1;
            end
            else
                $display("  ok  : mem[%0d] = 0x%h", word, expected);
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
        // PART 2 EXTENDS THE TRACE. The branch tests at idx20..38 add four more
        // TAKEN branches, each costing 2 flushed slots. Rather than re-deriving
        // the formula, here is the full fetch-slot trace of the tail, using the
        // rule established above: a branch fetched in slot s is in EX during
        // interval s+2, so slots s+1 and s+2 are killed and slot s+3 fetches
        // the target.
        //
        //   slot 20  0x4c  idx19
        //   slot 21  0x50  idx20  addi x18,-1
        //   slot 22  0x54  idx21  addi x19,1
        //   slot 23  0x58  idx22  bne x1,x2  TAKEN -> 0x60
        //   slot 24  0x5c  idx23  KILLED (FlushE)
        //   slot 25  0x60  idx24  KILLED (FlushD)   <- the target itself
        //   slot 26  0x60  idx24  re-fetched, runs
        //   slot 27  0x64  idx25  bne x1,x1  not taken
        //   slot 28  0x68  idx26
        //   slot 29  0x6c  idx27  blt  TAKEN -> 0x74
        //   slot 30  0x70  idx28  KILLED
        //   slot 31  0x74  idx29  KILLED
        //   slot 32  0x74  idx29  re-fetched, bltu not taken
        //   slot 33  0x78  idx30
        //   slot 34  0x7c  idx31  bge  TAKEN -> 0x84
        //   slot 35  0x80  idx32  KILLED
        //   slot 36  0x84  idx33  KILLED
        //   slot 37  0x84  idx33  re-fetched, bgeu TAKEN -> 0x8c
        //   slot 38  0x88  idx34  KILLED
        //   slot 39  0x8c  idx35  KILLED
        //   slot 40  0x8c  idx35  re-fetched, runs
        //   slot 41  0x90  idx36
        //   slot 42  0x94  idx37  bne x28,x2  not taken
        //   slot 43  0x98  idx38
        //
        // PART 3 adds the loop, and counting it is a nice exercise in what a
        // taken branch actually costs:
        //
        //   slot 44  0x9c  idx39  addi x30,1
        //   slot 45  0xa0  idx40  addi x31,31
        //   slot 46  0xa4  idx41  <- iteration 1 begins
        //
        // Each iteration that LOOPS occupies 5 slots, not 3: the three real
        // instructions plus the two wrong-path slots the taken backward branch
        // flushes. So a 3-instruction loop body runs at 5 cycles per iteration,
        // a 67% overhead, entirely because the branch is resolved in EX. This
        // is the single most convincing argument for branch prediction in the
        // whole project, and it only became measurable once the core could
        // loop at all.
        //
        //   iteration k (k = 1..30, all taken):  add at slot 46 + 5*(k-1)
        //   iteration 31 exits, so its bne is not taken and costs no flush:
        //     slot 196  0xa4  add        (46 + 5*30)
        //     slot 197  0xa8  addi
        //     slot 198  0xac  bne  x31,x0  NOT taken (counter reached 0)
        //     slot 199  0xb0  idx44  blt  TAKEN -> 0xb8
        //     slot 200  0xb4  idx45  KILLED
        //     slot 201  0xb8  idx46  KILLED
        //     slot 202  0xb8  idx46  re-fetched, runs   <- LAST INSTRUCTION
        //
        //        t = 600 + 100*202 = 20800
        //
        // Note the recurring pattern in every +8 branch: the target is fetched
        // TWICE - once speculatively down the wrong path where it is flushed,
        // then again from the redirected PC where it actually runs. It executes
        // exactly once. That is not a bug and not wasted work beyond the 2
        // cycles a taken branch always costs; it is just what "flush everything
        // younger than the branch" means when the target happens to be one of
        // the things younger than the branch.
        //
        // PART 4 (I-type ALU ops) is straight-line code - no branches, and the
        // closing lw has no consumer, so no stall. 14 instructions, 1 slot each:
        //
        //     slot 203..216  0xbc..0xf0  idx47..idx60
        //
        //        t = 600 + 100*216 = 22200
        //
        // PART 5 (xor / sltu / shifts) is the same shape: straight-line, no
        // stalls, 25 instructions:
        //
        //     slot 217..241  0xf4..0x154  idx61..idx85
        //
        //        t = 600 + 100*241 = 24700
        //
        // PART 6 (lui / auipc) is straight-line too. 12 instructions:
        //
        //     slot 242..253  0x158..0x184  idx86..idx97
        //
        //        t = 600 + 100*253 = 25900
        //
        // PART 7 (jal / jalr) has 5 taken jumps; each costs its 2 flushed slots,
        // exactly like a taken branch:
        //
        //   slot 254  0x188  jal          slot 267  0x1a4  jal x0
        //   255-256   KILLED              268-269   KILLED
        //   slot 257  0x194  sw           slot 270  0x1b4  addi
        //   slot 258  0x198  jal (call)   slot 271  0x1b8  jalr
        //   259-260   KILLED              272-273   KILLED
        //   slot 261  0x1a8  sw           slot 274  0x1c4  sw
        //   slot 262  0x1ac  jalr (ret)   slot 275  0x1c8  auipc
        //   263-264   KILLED              slot 276  0x1cc  sw
        //   slot 265  0x19c  addi         slot 277  0x1d0  lw  <- LAST
        //   slot 266  0x1a0  sw
        //
        //        t = 600 + 100*277 = 28300
        //
        // Wait comfortably past 28300 before sampling.
        //---------------------------------------------------------------------
        #28600;   // now t = 28725

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

        //---------------------------------------------------------------------
        // Every check below fails on the pre-Branch_Condition build, because
        // that build decoded all six B-type branches as beq. These are ISA
        // correctness checks, not pipeline checks - they would fail on the
        // single-cycle core too, which is why single_core/program.hex now
        // carries the same tests.
        //---------------------------------------------------------------------
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
        check_reg(29,  1); //FORWARDING into the new branch condition logic

        $display("-- loop + signed overflow (the only checks that can catch N vs N^V)");
        check_reg(30, 32'h80000000); //31 iterations of a real backward-branch loop
        check_reg(31,  0);           //blt on an OVERFLOWING subtraction was taken
        check_reg(28,  1);           //slt agrees with blt on the overflow case

        $display("-- I-type ALU ops (all but addi executed as add before the ALUOp fix)");
        check_mem(17, 32'h000000f0); //andi x15, x18, 0x0f0
        check_mem(18, 32'h000000f5); //ori  x15, x1, 0x0f5
        check_mem(19, 32'h00000001); //slti x15, x18, 0
        check_mem(20, 32'h00000000); //slti x15, x1, -1
        check_mem(21, 32'h00000005); //andi x15, x1, -1   - sign-extended imm
        check_mem(22, 32'h00000003); //addi x15, x1, -2   - must NOT become sub
        check_reg(15,  1);           //x15 restored by the closing lw

        $display("-- xor / sltu / shifts (all executed as add before the 4-bit ALUControl)");
        check_mem(23, 32'h00000002); //xor   x15, x1, x6
        check_mem(24, 32'h00000001); //sltu  x15, x19, x18  - 1 < 0xFFFFFFFF unsigned
        check_mem(25, 32'h00000000); //sltu  x15, x1, x2
        check_mem(26, 32'd40);       //sll   x15, x1, x2
        check_mem(27, 32'h80000000); //sll   x15, x19, x18  - shamt is rs2[4:0] only
        check_mem(28, 32'h10000000); //srl   x15, x30, x2   - zero fill
        check_mem(29, 32'hF0000000); //sra   x15, x30, x2   - sign fill
        check_mem(30, 32'hFFFFFFFA); //xori  x15, x1, -1
        check_mem(31, 32'h00000001); //sltiu x15, x19, -1   - imm sign-extends first
        check_mem(32, 32'd80);       //slli  x15, x1, 4
        check_mem(33, 32'h08000000); //srli  x15, x30, 4
        check_mem(34, 32'hF8000000); //srai  x15, x30, 4    - instr[30] selects sra

        $display("-- lui / auipc (both were silent no-ops before U-type support)");
        check_mem(35, 32'h12345000); //lui   x15, 0x12345
        check_mem(36, 32'hFFFFF000); //lui   x15, 0xfffff
        check_mem(37, 32'h00000168); //auipc x15, 0   at 0x168
        check_mem(38, 32'h00001170); //auipc x15, 1   at 0x170
        check_mem(39, 32'h00078000); //lui   x15, 0x78 - rs1 field matches RdM; must NOT forward

        $display("-- jal / jalr (both were silent no-ops before)");
        check_mem(40, 32'h0000018c); //jal  link = PC+4, wrong-path addis flushed
        check_mem(41, 32'd55);       //code after the call ran once the function returned
        check_mem(42, 32'h0000019c); //link value seen inside the function
        check_mem(43, 32'h00000000); //POISON: store after `ret` was flushed
        check_mem(44, 32'h00000000); //POISON: stores after jalr were flushed
        check_mem(45, 32'h000001bc); //jalr rd == rs1: link written, target used old rs1
        check_mem(46, 32'h000001c8); //jalr cleared bit 0 of the target (else 0x1c9)
        check_reg(15,  1);           //x15 restored again at the very end

        if (errors == 0)
            $display("RESULT: PASS - all 63 checks passed");
        else
            $display("RESULT: FAIL - %0d check(s) failed", errors);

        $finish;
    end

endmodule
