# RV32I Core — Single-Cycle → 5-Stage Pipeline

A from-scratch RV32I processor core in Verilog, built up in stages: a working single-cycle
datapath first, with a 5-stage pipelined version (hazard detection, forwarding, stalling,
flushing) in active development.

> **Status:** ✅ Single-cycle core implemented and simulated · 🚧 5-stage pipeline in progress
>
> This repo is being developed and documented openly as I build it, so the pipeline stages
> will land incrementally rather than all at once.

## Overview

This project implements the classic RISC-V RV32I datapath (Harris & Harris–style
single-cycle architecture) as a foundation, before extending it into a 5-stage pipeline
(IF → ID → EX → MEM → WB). The end goal is a pipelined core with forwarding/hazard
resolution, verified in simulation and on a PYNQ-Z2 FPGA.

## Current Progress

### ✅ Single-Cycle Core (`single_core/`)
A complete, simulated single-cycle RV32I datapath supporting core R-type, I-type,
load/store, and branch instructions.

| Module | File | Function |
|---|---|---|
| `PC_Module` | `PC.v` | Program counter register |
| `PC_Adder` | `PC_Adder.v` | PC+4 / branch target adder |
| `instruction_Memory` | `instruction_Memory.v` | Instruction fetch memory |
| `Register_file` | `Register_file.v` | 32×32-bit register file, dual read / single write |
| `Sign_Extend` | `Sign_Extend.v` | Immediate sign extension |
| `ALU` | `ALU.v` | Arithmetic/logic unit (add, sub, and, or, slt, +flags) |
| `ALU_decoder` | `ALU_decoder.v` | Generates ALU control signal from opcode/funct3/funct7 |
| `main_decoder` | `main_decoder.v` | Top-level control signal generation |
| `Control_Unit_Top` | `Control_Unit_Top.v` | Wraps main + ALU decoders |
| `Data_Memory` | `Data_Mem.v` | Load/store data memory |
| `Single_Cycle_Top` | `Single_Cycle_Top.v` | Top-level datapath integration |
| `Single_Cycle_Top_TestBench` | `Single_Cycle_Top_TestBench.v` | Clock/reset-driven testbench |

**Instructions supported:** R-type (`add`, `sub`, `and`, `or`, `slt`), I-type (`addi`, `lw`),
S-type (`sw`), B-type (`beq`).

#### Datapath Diagram

```mermaid
flowchart TD
    PC["PC_Module\n(PC.v)"] -->|PC| PCADD["PC_Adder\nPC + 4"]
    PC -->|PC| BADD["Branch_Adder\nPC + Imm_Ext"]
    PC -->|PC| IMEM["instruction_Memory\n(instruction_Memory.v)"]
    PCADD -->|PCPlus4| PCMUX{{"PC-source Mux\n(Branch ? target : +4)"}}
    BADD -->|PCTarget| PCMUX
    PCMUX -->|PC_Next| PC

    IMEM -->|instr| REGFILE["Register_file\n(Register_file.v)\nrs1 / rs2 / rd"]
    IMEM -->|instr| SEXT["Sign_Extend\n(Sign_Extend.v)"]
    IMEM -->|opcode / funct3 / funct7| CTRL["Control_Unit_Top\n(main_decoder + ALU_decoder)"]

    REGFILE -->|RD1| ALU["ALU\n(ALU.v)"]
    REGFILE -->|RD2| SRCB{{ALUSrc Mux}}
    SEXT -->|Imm_Ext| SRCB
    SEXT -->|Imm_Ext| BADD
    SRCB -->|SrcB| ALU

    ALU -.Z (zero flag).-> CTRL
    CTRL -.ALUControl.-> ALU
    CTRL -.ALUSrc.-> SRCB
    CTRL -.RegWrite.-> REGFILE
    CTRL -.MemWrite.-> DMEM
    CTRL -.ResultSrc.-> WDMUX
    CTRL -.Branch (branch-op & Z).-> PCMUX

    ALU -->|ALU_Result| DMEM["Data_Memory\n(Data_Mem.v)"]
    REGFILE -->|RD2| DMEM
    ALU -->|ALU_Result| WDMUX{{ResultSrc Mux}}
    DMEM -->|Read_Data| WDMUX
    WDMUX -->|WriteData / WD3| REGFILE
```

### 🚧 5-Stage Pipeline (`src/`)
Work in progress. Target architecture:

- **IF** – Fetch
- **ID** – Decode / register read
- **EX** – ALU / branch resolution
- **MEM** – Data memory access
- **WB** – Register writeback

Planned features as pipeline registers go in: data hazard **forwarding** (EX/MEM → EX),
**load-use stalling**, and **control hazard flushing** on taken branches, followed by
FPGA verification on a **PYNQ-Z2**.

## Repository Structure

```
.
├── docs/
│   └── RISC-V Project.md   # Design notes / project journal
├── single_core/            # Complete single-cycle RV32I implementation + testbench
│   ├── *.v                  # Datapath and control modules
│   ├── program.hex          # Test program loaded via $readmemh
│   ├── Single_Cycle_Top_TestBench.v            # Self-checking regression testbench
│   └── Single_Cycle_Top_TestBench.vcd(.gtkw)  # Simulation waveform + GTKWave session
└── src/
    └── Fetch_Cycle          # Placeholder for pipeline IF-stage work (not started yet)
```

## Simulation

Modules are built with [Icarus Verilog](http://iverilog.icarus.com/) and viewed with
[GTKWave](http://gtkwave.sourceforge.net/).

```bash
cd single_core

# Compile
iverilog -o out.vvp Single_Cycle_Top_TestBench.v

# Run
vvp out.vvp

# View waveforms
gtkwave Single_Cycle_Top_TestBench.vcd
```

The testbench is **self-checking** — it runs `program.hex` and asserts the expected final
register state, so a run either prints `RESULT: PASS` or names the register that went wrong:

```
=== single-cycle RV32I regression (program.hex) ===
  ok  : x1 = 5
  ...
  ok  : x12 = 7
RESULT: PASS - all 12 checks passed
```

`vvp` also prints a `$readmemh: Not enough words in the file for the requested range`
warning — that one is expected and harmless (the program is much shorter than the 1024-word
instruction memory, and the remainder is deliberately zero-filled with NOPs).

### Test program

Programs live in [`single_core/program.hex`](single_core/program.hex) — one 32-bit
instruction per line in hex, `//` comments allowed — and are loaded with `$readmemh`, so
**you no longer have to edit and recompile the RTL to run a different program.** The
committed program exercises every supported instruction:

| Instruction | Covered by |
|---|---|
| `addi` | `x1 = 5`, `x2 = 3` |
| `add` / `sub` | `x3 = 8`, `x4 = 2` |
| `and` / `or` | `x5 = 1`, `x6 = 7` |
| `slt` | `x7 = 1` (true), `x8 = 0` (false) |
| `sw` / `lw` | stores `x3` to `mem[0]`, reads it back into `x9` |
| `beq` not taken | falls through, so `x10 = 1` |
| `beq` taken | skips `addi x11, x0, 99`, so `x11` stays `0` and `x12 = 7` |

If you change the program, update the `check_reg` expectations at the bottom of
`Single_Cycle_Top_TestBench.v` to match.

## Recent Fixes

- **Branch resolution now works.** Previously `beq` was decoded but never redirected fetch:
  the ALU's `Z` (zero) flag was left unconnected and `Control_Unit_Top` hardcoded `zero = 0`,
  and there was no branch-target adder or PC-source mux at all — `PC_Module` only ever
  received `PC + 4`. Fixed by:
  - Wiring `ALU.Z` → `Control_Unit_Top`'s new `zero` input (`Single_Cycle_Top.v`,
    `Control_Unit_Top.v`)
  - Adding a second `PC_Adder` instance computing `PC + Imm_Ext` (the branch target)
  - Adding a mux on `PC_Module`'s `PC_NEXT` input selecting the branch target vs. `PC+4`,
    driven by `Branch` (`Control_Unit_Top`'s `PCSrc = branch-op & zero`)
  - Verified with a scratch regression program (`addi x1,5` / `addi x2,5` / `beq x1,x2,+8` /
    `addi x3,99` / `addi x4,7`) confirming the branch is taken, the instruction after it is
    skipped, and execution resumes correctly at the target.
- **Register file reset now actually clears registers.** `Register_file.v` previously only
  forced *reads* to zero while `rst` was asserted, without ever clearing the underlying
  `Register` array. It now synchronously zeroes all 32 registers on reset.
- **Verification is now self-checking.** The testbench previously just dumped a waveform for
  manual GTKWave inspection while instruction memory held a single hardcoded instruction.
  It now runs a 15-instruction program covering every supported opcode and asserts the final
  register state, reporting `PASS`/`FAIL`. Verified to actually catch regressions by
  re-introducing the branch bug and confirming the run fails on `x11`.
- **Programs are loaded from a file.** `instruction_Memory.v` now uses
  `$readmemh("program.hex", Mem)` instead of hardcoded `Mem[0] = ...` assignments, so
  swapping test programs no longer means editing and recompiling the RTL.
- **The documented build command actually works.** `iverilog -o out.vvp
  Single_Cycle_Top_TestBench.v` used to fail with `Unknown module type: Single_Cycle_Top`,
  because nothing pulled the top level into the testbench. Added the missing `` `include ``.
- **Memories start at zero instead of X.** Both instruction and data memory are zero-filled
  at time 0, so unwritten locations read as `0` (a harmless NOP in instruction memory)
  rather than smearing X through the register file and waveform.

## Roadmap

- [x] Single-cycle RV32I datapath (fetch, decode, execute, memory, writeback in one cycle)
- [x] Testbench + waveform verification
- [x] Branch resolution (zero flag → PC-source mux → branch target)
- [x] Self-checking regression covering every supported instruction
- [ ] Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
- [ ] Hazard detection unit + load-use stall logic
- [ ] EX/MEM and MEM/WB forwarding paths
- [ ] Branch flush logic.  
- [ ] PYNQ-Z2 FPGA synthesis and on-board verification

## Author

**Swastik** ([@dr-paradox-design](https://github.com/dr-paradox-design)) — B.Tech Electrical
Engineering, NIT Rourkela. Built as part of an ongoing push into digital/ASIC design
fundamentals.

## License

No license file yet — add one (MIT is a common choice for educational cores) if you want
others to freely reuse this.
