#!/usr/bin/env python3
"""
Generates docs/RV32I_Pipeline_Stages.pdf - a walkthrough of the 5-stage pipeline
implementation in src/.

Run from anywhere:   python docs/generate_pipeline_pdf.py

Companion to generate_pdf.py, which documents the single-cycle core in single_core/.
Kept in the repo so the PDF is regenerable rather than a binary blob nobody can update.

Only ASCII is emitted: ReportLab's built-in Type-1 fonts have no glyphs for arrows,
box-drawing or emoji, and missing glyphs render as solid black boxes.
"""

import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "RV32I_Pipeline_Stages.pdf")

ACCENT = colors.HexColor("#1f4e79")
LIGHT = colors.HexColor("#dce6f1")
CODE_BG = colors.HexColor("#f4f4f4")
RULE = colors.HexColor("#b0b8c0")
REGBAR = colors.HexColor("#f6d9d0")
REGEDGE = colors.HexColor("#b3543c")
GREEN = colors.HexColor("#e2f0d9")

# --------------------------------------------------------------------------- styles

ss = getSampleStyleSheet()

TitleS = ParagraphStyle("TitleS", parent=ss["Title"], fontSize=24, leading=29,
                        textColor=ACCENT, spaceAfter=6)
SubTitleS = ParagraphStyle("SubTitleS", parent=ss["Normal"], fontSize=13, leading=18,
                           alignment=TA_CENTER, textColor=colors.HexColor("#444444"))
H1 = ParagraphStyle("H1", parent=ss["Heading1"], fontSize=16, leading=20,
                    textColor=ACCENT, spaceBefore=16, spaceAfter=8)
H2 = ParagraphStyle("H2", parent=ss["Heading2"], fontSize=12.5, leading=16,
                    textColor=colors.HexColor("#2e5f8a"), spaceBefore=12, spaceAfter=5)
Body = ParagraphStyle("Body", parent=ss["BodyText"], fontSize=9.8, leading=14,
                      spaceAfter=7)
Bullet = ParagraphStyle("Bullet", parent=Body, leftIndent=14, bulletIndent=4,
                        spaceAfter=4)
Caption = ParagraphStyle("Caption", parent=Body, fontSize=8.5, leading=11,
                         alignment=TA_CENTER, textColor=colors.HexColor("#555555"))
Code = ParagraphStyle("Code", parent=ss["Code"], fontName="Courier", fontSize=7.4,
                      leading=9.2, backColor=CODE_BG, borderPadding=5,
                      leftIndent=2, rightIndent=2, spaceBefore=3, spaceAfter=9)
CodeSm = ParagraphStyle("CodeSm", parent=Code, fontSize=6.5, leading=8.1)
Note = ParagraphStyle("Note", parent=Body, fontSize=9.2, leading=13,
                      leftIndent=10, rightIndent=6, borderPadding=6,
                      backColor=colors.HexColor("#fdf6e3"),
                      borderColor=colors.HexColor("#d9c48a"), borderWidth=0.6,
                      spaceBefore=4, spaceAfter=9)
TblCell = ParagraphStyle("TblCell", parent=Body, fontSize=8.4, leading=11, spaceAfter=0)
TblHead = ParagraphStyle("TblHead", parent=TblCell, fontName="Helvetica-Bold",
                         textColor=colors.white)
TblMono = ParagraphStyle("TblMono", parent=TblCell, fontName="Courier", fontSize=7.8)


def P(t, s=Body):
    return Paragraph(t, s)


def B(t):
    return Paragraph(t, Bullet, bulletText="-")


def code(t, small=False):
    return Preformatted(t.strip("\n"), CodeSm if small else Code)


def table(rows, widths, mono_cols=()):
    """rows[0] is the header. mono_cols is a set of column indices to render monospaced."""
    data = [[Paragraph(c, TblHead) for c in rows[0]]]
    for r in rows[1:]:
        data.append([Paragraph(c, TblMono if i in mono_cols else TblCell)
                     for i, c in enumerate(r)])
    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), ACCENT),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT]),
        ("GRID", (0, 0), (-1, -1), 0.4, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
    ]))
    return t


# ----------------------------------------------------------------- pipeline diagram

def pipeline_diagram():
    """Five stages, four pipeline registers, two backward paths."""
    W, H = 468, 268
    d = Drawing(W, H)

    SB_Y, SB_H = 150, 56          # stage box
    PR_Y, PR_H = 138, 80          # pipeline register bar (taller, straddles the row)

    def stage(x, w, title, sub):
        d.add(Rect(x, SB_Y, w, SB_H, fillColor=GREEN, strokeColor=ACCENT,
                   strokeWidth=1.0))
        d.add(String(x + w / 2.0, SB_Y + SB_H - 18, title, fontName="Helvetica-Bold",
                     fontSize=9.5, fillColor=colors.black, textAnchor="middle"))
        for i, ln in enumerate(sub):
            d.add(String(x + w / 2.0, SB_Y + SB_H - 32 - i * 9, ln,
                         fontName="Helvetica", fontSize=6.3,
                         fillColor=colors.HexColor("#333333"), textAnchor="middle"))

    def preg(x, w, label):
        d.add(Rect(x, PR_Y, w, PR_H, fillColor=REGBAR, strokeColor=REGEDGE,
                   strokeWidth=1.0))
        # label rotated is not worth the complexity; stack the characters instead
        for i, ch in enumerate(label):
            d.add(String(x + w / 2.0, PR_Y + PR_H - 11 - i * 7.6, ch,
                         fontName="Helvetica-Bold", fontSize=6.4,
                         fillColor=REGEDGE, textAnchor="middle"))

    def arrow(x1, y1, x2, y2):
        d.add(Line(x1, y1, x2, y2, strokeColor=colors.HexColor("#333333"),
                   strokeWidth=0.9))

    def head(x, y, direction):
        s = 3.6
        if direction == "r":
            pts = [x, y, x - s, y + s * 0.72, x - s, y - s * 0.72]
        elif direction == "l":
            pts = [x, y, x + s, y + s * 0.72, x + s, y - s * 0.72]
        elif direction == "u":
            pts = [x, y, x - s * 0.72, y - s, x + s * 0.72, y - s]
        else:
            pts = [x, y, x - s * 0.72, y + s, x + s * 0.72, y + s]
        d.add(Polygon(pts, fillColor=colors.HexColor("#333333"),
                      strokeColor=colors.HexColor("#333333")))

    def lbl(x, y, t, anchor="middle", c="#333333", fs=5.9):
        d.add(String(x, y, t, fontName="Helvetica", fontSize=fs,
                     fillColor=colors.HexColor(c), textAnchor=anchor))

    SW, RW, GAP = 66, 13, 6
    xs = []
    x = 6
    for i in range(5):
        xs.append(x)
        x += SW + GAP
        if i < 4:
            x += RW + GAP

    stage(xs[0], SW, "1. IF", ["PC, PC+4", "instruction", "memory"])
    stage(xs[1], SW, "2. ID", ["control unit", "register file", "sign extend"])
    stage(xs[2], SW, "3. EX", ["ALU", "branch adder", "branch decision"])
    stage(xs[3], SW, "4. MEM", ["data memory", "load / store"])
    stage(xs[4], SW, "5. WB", ["result mux", "back to the", "register file"])

    rxs = [xs[i] + SW + GAP for i in range(4)]
    for rx, nm in zip(rxs, ["IF/ID", "ID/EX", "EX/MEM", "MEM/WB"]):
        preg(rx, RW, nm)

    # forward arrows between blocks
    ymid = SB_Y + SB_H / 2.0
    for i in range(4):
        arrow(xs[i] + SW, ymid, rxs[i], ymid)
        head(rxs[i], ymid, "r")
        arrow(rxs[i] + RW, ymid, xs[i + 1], ymid)
        head(xs[i + 1], ymid, "r")

    d.add(String(W / 2.0, SB_Y + SB_H + 14,
                 "forward: one instruction moves one stage to the right every clock edge",
                 fontName="Helvetica-Oblique", fontSize=6.8,
                 fillColor=colors.HexColor("#555555"), textAnchor="middle"))

    # ---- backward path 1: branch redirect, EX -> IF ----
    BR_Y = 104
    cx_ex = xs[2] + SW / 2.0
    cx_if = xs[0] + SW / 2.0
    arrow(cx_ex, SB_Y, cx_ex, BR_Y)
    arrow(cx_ex, BR_Y, cx_if, BR_Y)
    arrow(cx_if, BR_Y, cx_if, SB_Y)
    head(cx_if, SB_Y, "u")
    lbl((cx_ex + cx_if) / 2.0, BR_Y - 9,
        "BACKWARD 1:  PCSrcE, PCTargetE   (branch resolved in EX, PC lives in IF)",
        c="#b3543c")
    lbl(cx_ex + 4, BR_Y + 16, "cost: 2 delay slots", anchor="start", c="#b3543c")

    # ---- backward path 2: write-back, WB -> ID ----
    WB_Y = 56
    cx_wb = xs[4] + SW / 2.0
    cx_id = xs[1] + SW / 2.0
    arrow(cx_wb, SB_Y, cx_wb, WB_Y)
    arrow(cx_wb, WB_Y, cx_id, WB_Y)
    arrow(cx_id, WB_Y, cx_id, SB_Y)
    head(cx_id, SB_Y, "u")
    lbl((cx_wb + cx_id) / 2.0, WB_Y - 9,
        "BACKWARD 2:  RegWriteW, RdW, ResultW   (register file read in ID, written from WB)",
        c="#b3543c")
    lbl(cx_wb - 4, WB_Y + 16, "cost: 3 NOPs between dependent instructions",
        anchor="end", c="#b3543c")

    # ---- caption strip ----
    lbl(W / 2.0, 22,
        "Every gate lives inside a stage. The four bars are the pipeline registers - "
        "the only thing this build adds.",
        c="#555555", fs=6.6)
    lbl(W / 2.0, 10,
        "Both backward paths are unprotected here: no forwarding, no stalling, no flushing.",
        c="#555555", fs=6.6)

    return d


# --------------------------------------------------------------------------- layout

def on_page(canvas, doc):
    canvas.saveState()
    n = canvas.getPageNumber()
    if n > 1:
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(colors.HexColor("#777777"))
        canvas.drawString(72, LETTER[1] - 46,
                          "RV32I 5-Stage Pipeline - Implementation Walkthrough")
        canvas.drawRightString(LETTER[0] - 72, LETTER[1] - 46, "Swastik Aditya Ranjan")
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        canvas.line(72, LETTER[1] - 52, LETTER[0] - 72, LETTER[1] - 52)
        canvas.drawCentredString(LETTER[0] / 2.0, 40, str(n))
    canvas.restoreState()


def build(story):
    doc = BaseDocTemplate(OUT, pagesize=LETTER,
                          leftMargin=72, rightMargin=72,
                          topMargin=64, bottomMargin=60,
                          title="RV32I 5-Stage Pipeline - Implementation Walkthrough",
                          author="Swastik Aditya Ranjan",
                          subject="Pipelining an RV32I core in Verilog: pipeline "
                                  "registers, stage split and hazard scheduling")
    frame = Frame(72, 60, LETTER[0] - 144, LETTER[1] - 124, id="body")
    doc.addPageTemplates([PageTemplate(id="all", frames=[frame], onPage=on_page)])
    doc.build(story)


# --------------------------------------------------------------------------- content

s = []
A = s.append

# ============================================================== title page
A(Spacer(1, 92))
A(P("RV32I 5-Stage Pipeline", TitleS))
A(P("Implementation Walkthrough of <b>src/</b>", SubTitleS))
A(Spacer(1, 16))
A(P("How the single-cycle datapath was split into IF / ID / EX / MEM / WB, "
    "what each of the four pipeline registers carries, and why this build "
    "schedules its hazards in software instead of hardware.", SubTitleS))
A(Spacer(1, 42))
A(table([
    ["Item", "Detail"],
    ["Scope of this document", "The pipeline-register split only. Hazard detection, "
     "forwarding, stalling and flushing are deliberately not implemented yet."],
    ["New RTL", "src/Fetch_Cycle.v, Decode_Cycle.v, Execute_Cycle.v, "
     "Memory_Cycle.v, Writeback_Cycle.v, Pipeline_Top.v"],
    ["Reused unchanged", "All eight functional units in single_core/ - not one line edited"],
    ["Verification", "src/Pipeline_Top_TestBench.v - 12/12 self-checking assertions PASS"],
    ["Companion document", "docs/RV32I_Single_Cycle_Core.pdf (the single-cycle core)"],
], [1.55 * 72, 4.35 * 72]))
A(Spacer(1, 30))
A(P("Swastik Aditya Ranjan<br/>B.Tech Electrical Engineering, NIT Rourkela",
    SubTitleS))
A(PageBreak())

# ============================================================== 1
A(P("1. What This Document Covers", H1))
A(P("The single-cycle core in <b>single_core/</b> works and passes a 12-check "
    "regression. It has one structural problem: every instruction must complete "
    "fetch, decode, register read, ALU, memory access and write-back inside a "
    "single clock period. The clock can therefore be no faster than the slowest "
    "instruction's entire journey, and while the ALU is working the instruction "
    "memory sits idle, and vice versa. Most of the hardware is doing nothing most "
    "of the time."))
A(P("Pipelining fixes the utilisation problem by cutting that journey into five "
    "shorter stages and letting five different instructions occupy them "
    "simultaneously. This document explains exactly how that cut was made in "
    "<b>src/</b>."))

A(P("What you will find here", H2))
A(B("The structure of the pipeline, and the naming convention that makes "
    "pipelined RTL readable (sections 3-4)."))
A(B("A stage-by-stage tour of the five new modules (section 5)."))
A(B("What each pipeline register carries, and - just as importantly - what it "
    "deliberately does not carry (section 6)."))
A(B("The two backward signal paths, which are the entire source of difficulty "
    "in pipelining (section 7)."))
A(B("Three design decisions that look odd out of context, and the reasoning "
    "behind each (section 8)."))
A(B("Hazards: the arithmetic that produces the 3-NOP and 2-delay-slot rules, "
    "and an experiment confirming the hardware really behaves that way "
    "(section 9)."))

A(P("What is deliberately out of scope", H2))
A(P("This build has <b>no hazard detection unit, no forwarding network, no "
    "stalling and no flushing</b>. That is not an oversight or an unfinished "
    "corner - it is the defined scope of this stage of the project. Leaving the "
    "hazard hardware out makes the pipeline registers themselves, which are the "
    "actual subject of the work, easy to see and easy to reason about. The "
    "hazards are real and they are handled honestly, by scheduling NOPs in "
    "software and documenting precisely why each one is needed."))
A(P("<b>Read section 9 before concluding anything is broken.</b> Every NOP in "
    "src/program.hex is there for a derived, measured reason.", Note))

# ============================================================== 2
A(P("2. What Changed, and What Deliberately Did Not", H1))
A(P("The most important fact about this implementation is how little of the "
    "existing design it touched."))
A(table([
    ["Category", "Files", "Status"],
    ["Functional units", "PC.v, PC_Adder.v, instruction_Memory.v, Register_file.v, "
     "Sign_Extend.v, ALU.v, ALU_decoder.v, main_decoder.v, Control_Unit_Top.v, "
     "Data_Mem.v", "Reused <b>verbatim</b>. Zero edits."],
    ["Single-cycle top", "Single_Cycle_Top.v, its testbench and program.hex",
     "Untouched and still passing."],
    ["New pipeline RTL", "Fetch_Cycle.v, Decode_Cycle.v, Execute_Cycle.v, "
     "Memory_Cycle.v, Writeback_Cycle.v, Pipeline_Top.v", "New in src/."],
    ["New verification", "src/program.hex, src/Pipeline_Top_TestBench.v",
     "New in src/."],
], [1.05 * 72, 2.65 * 72, 2.2 * 72]))

A(P("Why the functional units were shared rather than copied", H2))
A(P("Because <b>pipelining a processor does not change its functional units</b>. "
    "An ALU is an ALU. A register file is a register file. What pipelining "
    "changes is that you put registers <i>between</i> them and let several "
    "instructions be in flight at once. Sharing the modules makes that point "
    "structurally rather than just asserting it in prose."))
A(P("There is also a practical debugging benefit. Because single_core/ is frozen "
    "and demonstrably passing its own regression, any failure in the pipeline is "
    "provably a pipelining bug. If the shared modules had been forked and edited, "
    "every failure would start with the question \"did I break the ALU, or did I "
    "wire the pipeline wrong?\" That question never has to be asked here."))
A(P("The cost of this choice shows up in section 8: two of the three design "
    "decisions documented there exist purely to avoid editing a verified file."))

# ============================================================== 3
A(P("3. The Structure of the Pipeline", H1))
A(pipeline_diagram())
A(P("Figure 1 - The 5-stage pipeline as implemented in src/. Green blocks are "
    "the five stage modules; the four salmon bars are the pipeline registers "
    "that give the design its name.", Caption))
A(Spacer(1, 8))
A(P("Read the figure left to right for the forward path: on every rising clock "
    "edge, each instruction advances exactly one stage. Once the pipe is full, "
    "five instructions are being worked on simultaneously and one instruction "
    "completes per cycle."))
A(P("The two paths drawn <i>below</i> the stages are the interesting part. They "
    "run backwards - right to left - and they are where all the difficulty in "
    "pipelining comes from. Section 7 covers them in detail."))

A(P("The four pipeline registers", H2))
A(P("Each pipeline register is a bank of flip-flops written by one "
    "<font face='Courier'>always @(posedge clk)</font> block. There is nothing "
    "clever in any of them - they simply freeze their stage's results so the "
    "next stage can work on them next cycle while the current stage moves on to "
    "a new instruction."))
A(table([
    ["Register", "Written by", "Purpose"],
    ["IF/ID", "bottom of Fetch_Cycle.v", "Hands the fetched instruction word and "
     "its address to decode."],
    ["ID/EX", "bottom of Decode_Cycle.v", "Hands control bits, both register "
     "operands, the immediate, the PC and the destination register number to execute."],
    ["EX/MEM", "bottom of Execute_Cycle.v", "Hands the ALU result (the address, "
     "for a load or store), the store data and the surviving control bits to memory."],
    ["MEM/WB", "bottom of Memory_Cycle.v", "Hands both write-back candidates - "
     "ALU result and load data - to write-back."],
], [0.85 * 72, 1.65 * 72, 3.4 * 72]))
A(P("Note that <b>Writeback_Cycle.v contains no pipeline register</b>. There is "
    "no sixth stage to hand anything to. Its output loops backwards to the "
    "register file instead, which is why WB is purely combinational."))

A(P("Why non-blocking assignment is mandatory", H2))
A(P("Every pipeline register uses <font face='Courier'>&lt;=</font>, never "
    "<font face='Courier'>=</font>. This is not a style preference."))
A(P("All four registers update on the same clock edge. With non-blocking "
    "assignment, every one of them samples its <i>old</i> input and they all "
    "update together - which is exactly what real flip-flops do. With blocking "
    "assignment, the result would depend on the order the simulator happened to "
    "evaluate the four always blocks, and a value could race through two or "
    "three stages in a single cycle. The simulation would then disagree with the "
    "synthesised hardware, which is the worst possible class of bug."))


# ============================================================== 4
A(P("4. The Naming Convention", H1))
A(P("Pipelined RTL is unreadable without a discipline for naming, because the "
    "same logical value exists in several places at once, at different ages. "
    "Every signal in src/ therefore ends in a letter naming the stage it lives in:"))
A(code("""
    F = Fetch      D = Decode     E = Execute
    M = Memory     W = Write-back

    PCF   the program counter, as seen in the fetch stage
    PCD   the same value one cycle later, after the IF/ID register latched it
    PCE   the same value one cycle later again, after ID/EX latched it
"""))
A(P("<b>The moment a signal crosses a pipeline register, its letter changes.</b> "
    "That single habit is what makes this style of code navigable: if you see "
    "<font face='Courier'>RD2E</font> in one file and "
    "<font face='Courier'>RD2M</font> in another, you instantly know they are "
    "the same wire, one cycle apart, and you know which pipeline register "
    "connects them."))
A(P("The convention also catches a whole class of bug by inspection. If an "
    "expression mixes suffixes - say it ANDs something ending in "
    "<font face='Courier'>E</font> with something ending in "
    "<font face='Courier'>M</font> - it is combining data from two different "
    "instructions, and it is almost certainly wrong. There is exactly one place "
    "in this design where mixed suffixes are legitimate: the register file's "
    "write port in Decode_Cycle.v, which is driven by "
    "<font face='Courier'>W</font>-suffixed signals on purpose. That is the "
    "backward write-back path, and it is heavily commented for precisely this "
    "reason."))

# ============================================================== 5
A(P("5. Stage-by-Stage Reference", H1))

A(P("5.1 Fetch - src/Fetch_Cycle.v", H2))
A(P("Reads the instruction the PC points at, and works out which address to read "
    "next. It never looks at the instruction it fetched - decoding is the next "
    "stage's job."))
A(P("Contains PC_Module, PC_Adder (for PC+4), instruction_Memory, the PC-source "
    "mux, and the IF/ID register. The mux is the single-cycle core's mux "
    "unchanged, but note where its select signal comes from:"))
A(code("""
    assign PCNextF = PCSrcE ? PCTargetE : PCPlus4F;
                     ^^^^^^
                     E suffix: produced two stages downstream
"""))
A(P("There is deliberately <b>no branch adder in this stage</b>, unlike the "
    "single-cycle core. The branch target is the branch's own address plus its "
    "immediate, and the immediate does not exist until Sign_Extend runs in "
    "decode. The adder therefore had to move downstream; section 8.2 explains "
    "why it landed in execute specifically."))

A(P("5.2 Decode - src/Decode_Cycle.v", H2))
A(P("Turns the 32-bit instruction word into three things: control signals, the "
    "two register operands, and the sign-extended immediate. Contains "
    "Control_Unit_Top, Register_file, Sign_Extend and the ID/EX register."))
A(P("This stage is where the single biggest conceptual shift from the "
    "single-cycle core happens:"))
A(P("<b>Control signals are pipelined data.</b> In the single-cycle core, the "
    "decoder's outputs went straight to the units that used them, because "
    "everything happened in one clock period. Here, "
    "<font face='Courier'>MemWrite</font> is decoded in ID but the data memory "
    "does not run until MEM, three cycles later. Wiring the decoder's "
    "<font face='Courier'>MemWrite</font> straight to the memory would make the "
    "memory obey whatever instruction happens to be sitting in decode at that "
    "moment - not the store that actually wants to write.", Note))
A(P("So control bits travel through the same pipeline registers as the data. "
    "The mental model worth carrying: <i>each instruction drags a little "
    "backpack of control bits down the pipe with it, and each stage reaches into "
    "the backpack for the bits it needs right now.</i> "
    "<font face='Courier'>RegWrite</font> has the longest journey of all - "
    "decoded in ID, used in WB, so it rides through three registers as "
    "<font face='Courier'>RegWriteE -&gt; RegWriteM -&gt; RegWriteW</font>."))
A(P("The register file physically lives in this stage, but its <i>write</i> side "
    "is driven from write-back. That is why textbook diagrams draw the register "
    "file straddling ID and WB: it is one piece of hardware, read by one stage "
    "and written by another four cycles later."))

A(P("5.3 Execute - src/Execute_Cycle.v", H2))
A(P("Two independent calculations happen here in parallel: the ALU does the "
    "instruction's real work, and a second adder computes the branch target. "
    "This stage also makes the only decision in the core that reaches backwards."))
A(code("""
    assign PCSrcE = BranchE & ZeroE;
                    ^^^^^^^   ^^^^^
                    |         the ALU's zero flag, produced in THIS cycle
                    a control bit that travelled one register from decode
"""))
A(P("Both terms describe the same instruction, so this AND is exactly the "
    "single-cycle branch equation - just evaluated one stage later. Section 8.1 "
    "explains how the two halves came to be split across two stages."))

A(P("5.4 Memory - src/Memory_Cycle.v", H2))
A(P("Talks to the data memory, and nothing else. Exactly one instruction type "
    "reads it (<font face='Courier'>lw</font>), one writes it "
    "(<font face='Courier'>sw</font>), and every other instruction passes "
    "straight through untouched."))
A(P("It is fair to ask why something most instructions ignore gets a whole "
    "stage. The answer is that a pipeline runs at the speed of its slowest "
    "stage, and every instruction must visit every stage in the same order. "
    "Memory access is among the slowest operations in the datapath, so it gets "
    "its own stage rather than being bolted onto the end of EX and dragging the "
    "whole clock period down. <font face='Courier'>add</font> pays a cycle of "
    "latency it does not need - but latency is not what a pipeline optimises. "
    "Throughput is, and one instruction still finishes every cycle."))
A(P("Two values arrive here and it is worth keeping them straight: "
    "<font face='Courier'>ALU_ResultM</font> is the <b>address</b> (for lw/sw "
    "the ALU spent its cycle adding base register + offset), while "
    "<font face='Courier'>WriteDataM</font> is the <b>data</b> to store - the "
    "rs2 value, which bypassed the ALU completely back in execute."))

A(P("5.5 Write-back - src/Writeback_Cycle.v", H2))
A(P("One 32-bit 2-to-1 mux. That is the entire stage."))
A(code("""
    assign ResultW = ResultSrcW ? ReadDataW : ALU_ResultW;
"""))
A(P("It decides only <b>what</b> to write. It does not decide <i>whether</i> - "
    "<font face='Courier'>RegWriteW</font> does that - nor <i>where</i> - "
    "<font face='Courier'>RdW</font> does that. Those two go straight from the "
    "MEM/WB register to the register file without passing through this module, "
    "because they need no further processing."))
A(P("Why is the mux down here rather than back in MEM, where both inputs are "
    "already available? Because putting it in MEM would stack <i>memory read, "
    "then mux, then flip-flop</i> into a single clock period, on a stage that is "
    "already one of the slowest. Carrying both candidates through MEM/WB costs "
    "32 extra flip-flops and buys a shorter critical path. That is a trade worth "
    "making, and it is the standard choice."))


# ============================================================== 6
A(P("6. What Each Pipeline Register Carries", H1))
A(P("A pipeline register should carry only what a later stage genuinely still "
    "needs. Anything else is flip-flops and power spent for nothing. The table "
    "below tracks every signal across all four boundaries."))
A(table([
    ["Signal", "IF/ID", "ID/EX", "EX/MEM", "MEM/WB", "Consumed by"],
    ["Instr", "yes", "-", "-", "-", "the decoder, in ID"],
    ["PC", "yes", "yes", "-", "-", "the branch adder, in EX"],
    ["RegWrite", "-", "yes", "yes", "yes", "the register file, in WB"],
    ["ResultSrc", "-", "yes", "yes", "yes", "the result mux, in WB"],
    ["MemWrite", "-", "yes", "yes", "-", "the data memory, in MEM"],
    ["ALUSrc", "-", "yes", "-", "-", "the SrcB mux, in EX"],
    ["Branch", "-", "yes", "-", "-", "the PCSrcE AND gate, in EX"],
    ["ALUControl", "-", "yes", "-", "-", "the ALU, in EX"],
    ["RD1 (rs1)", "-", "yes", "-", "-", "the ALU, in EX"],
    ["RD2 (rs2)", "-", "yes", "yes", "-", "SrcB mux in EX; store data in MEM"],
    ["ImmExt", "-", "yes", "-", "-", "SrcB mux and branch adder, in EX"],
    ["ALU_Result", "-", "-", "yes", "yes", "memory address in MEM; result in WB"],
    ["ReadData", "-", "-", "-", "yes", "the result mux, in WB"],
    ["Rd", "-", "yes", "yes", "yes", "the register file write address, in WB"],
], [0.95 * 72, 0.5 * 72, 0.5 * 72, 0.62 * 72, 0.62 * 72, 2.61 * 72], mono_cols={0}))

A(P("The bundle narrows as it goes", H2))
A(P("Look down the columns and you can watch signals die off as their last "
    "consumer runs. <font face='Courier'>ImmExt</font>, "
    "<font face='Courier'>ALUControl</font>, <font face='Courier'>ALUSrc</font>, "
    "<font face='Courier'>Branch</font>, <font face='Courier'>RD1</font> and "
    "<font face='Courier'>PC</font> all stop at the EX/MEM boundary, because "
    "everything that needed them ran in execute. "
    "<font face='Courier'>MemWrite</font> stops at MEM/WB. That narrowing is "
    "normal and healthy."))
A(P("Two entries deserve individual comment."))
A(B("<b>ImmSrc never enters a pipeline register at all.</b> It is a 2-bit "
    "selector needed only to <i>produce</i> ImmExt, which happens in decode. "
    "Once the 32-bit immediate exists, the selector has served its purpose and "
    "is thrown away. Only signals a later stage consumes deserve a seat."))
A(B("<b>PC+4 is not carried anywhere.</b> Textbook pipelines pipe it all the "
    "way to WB, because <font face='Courier'>jal</font> writes the return "
    "address into rd. This core does not implement jal, so PC+4 has exactly one "
    "consumer - the PC mux back in fetch - and never needs to leave that stage. "
    "Carrying it would be four registers of dead silicon. It goes in the moment "
    "jal does."))
A(P("Note also that <font face='Courier'>RD2</font> is renamed to "
    "<font face='Courier'>WriteDataM</font> as it crosses EX/MEM. Same wire, but "
    "the rename documents the role it is about to play: for a store, rs2 is the "
    "value being written to memory."))

# ============================================================== 7
A(P("7. The Two Backward Paths", H1))
A(P("Forward data flow is the easy part of a pipeline - it is just registers in "
    "a row. Every genuine difficulty comes from the two paths that run "
    "<i>backwards</i>, because a backward path means a later stage is telling an "
    "earlier stage something it needed to know several cycles ago."))

A(P("7.1 Branch redirect: EX to IF", H2))
A(P("Signals: <font face='Courier'>PCSrcE</font>, "
    "<font face='Courier'>PCTargetE</font>."))
A(P("A branch is resolved in execute, but the PC lives in fetch. By the time the "
    "answer arrives, fetch has already read the two instructions that physically "
    "follow the branch in memory, and they are sitting in IF/ID and ID/EX. A "
    "complete pipeline kills them with flush logic. <b>This build has no flush "
    "logic, so those two instructions will execute.</b>"))
A(P("<b>Consequence: two delay slots after every taken branch.</b> "
    "src/program.hex puts NOPs there so that what executes is harmless. This is "
    "a real historical technique, not a hack invented to paper over a gap - "
    "early MIPS exposed the branch delay slot in its ISA for exactly this "
    "reason, and let compilers fill it with useful work.", Note))
A(P("A not-taken branch costs nothing: the two instructions after it were going "
    "to run anyway."))

A(P("7.2 Register write-back: WB to ID", H2))
A(P("Signals: <font face='Courier'>RegWriteW</font>, "
    "<font face='Courier'>RdW</font>, <font face='Courier'>ResultW</font>."))
A(P("The register file is read in decode but written from write-back, four "
    "stages later. Worse, Register_file.v writes on the rising edge and has no "
    "write-through bypass, so a read issued in the same cycle as a write returns "
    "the <i>old</i> value."))
A(P("<b>Consequence: three NOPs between a producer and its consumer.</b> The "
    "arithmetic behind that number is derived in section 9.1 and confirmed "
    "experimentally in section 9.2.", Note))


# ============================================================== 8
A(P("8. Three Design Decisions Worth Defending", H1))
A(P("Three choices in src/ look odd without context. Each is deliberate."))

A(P("8.1 Control_Unit_Top is instantiated with .zero(1'b1)", H2))
A(P("In Decode_Cycle.v the control unit's zero input is tied to a constant one. "
    "This superficially resembles a genuine bug that once existed in the "
    "single-cycle core - documented in section 6 of the companion PDF - where "
    "the same port was hardcoded to <font face='Courier'>1'b0</font>. The two "
    "are opposites, and the difference matters."))
A(P("Control_Unit_Top was written for a core where the ALU's zero flag was "
    "available in the same clock period as decoding. Internally it computes:"))
A(code("""
    Branch (a.k.a. PCSrc) = <opcode is a branch> & zero
"""))
A(P("In a pipeline that equation cannot be evaluated in decode. The comparison "
    "producing the zero flag does not happen until the ALU runs in execute, one "
    "cycle later - the flag simply does not exist yet at that point in time."))
A(P("What decode actually needs from the decoder is only the left half of that "
    "AND: the raw <i>\"is this a branch instruction?\"</i> bit. Tying zero to "
    "one extracts exactly that, because one is the identity element of AND:"))
A(code("""
    BranchD = <opcode is a branch> & 1 = <opcode is a branch>
"""))
A(P("The other half is then performed in Execute_Cycle.v, where the real flag "
    "exists, as <font face='Courier'>PCSrcE = BranchE &amp; ZeroE</font>. The "
    "logic is not weakened or discarded - it is <b>split across two stages</b>, "
    "which is the whole point of pipelining."))
A(P("Contrast with the old defect: hardcoding zero to <b>0</b> was fatal because "
    "<font face='Courier'>x &amp; 0 == 0</font> always, which destroyed the "
    "branch condition and made <font face='Courier'>beq</font> permanently "
    "not-taken. Hardcoding it to <b>1</b> destroys nothing and merely defers the "
    "real test by one stage.", Note))
A(P("The tidier alternative would be to add a clean "
    "<font face='Courier'>branch_op</font> output to main_decoder. That was "
    "rejected because it means editing main_decoder.v, Control_Unit_Top.v and "
    "Single_Cycle_Top.v - three files belonging to a core that currently passes "
    "its regression. The comment block in Decode_Cycle.v is roughly thirty lines "
    "long precisely because this line would otherwise look like the bug it is not."))

A(P("8.2 The branch adder moved from fetch to execute", H2))
A(P("In the single-cycle core, Branch_Adder sat next to the PC. In a pipeline it "
    "cannot: the branch target is PC + immediate, and the immediate does not "
    "exist until Sign_Extend runs in decode. So the adder had to move at least "
    "as far down as ID."))
A(P("It was placed in EX rather than ID for a routing reason. EX is where the "
    "branch condition is resolved, so keeping the target and the decision in the "
    "same stage means only <b>one</b> backward bundle has to be routed up to "
    "fetch, instead of two signals originating in two different stages. Fewer "
    "long backward wires is the right instinct in any pipeline."))
A(P("The knock-on effect is that PC must be carried IF to ID to EX, purely so "
    "that execute has the branch's own address to add to. That is what the "
    "<font face='Courier'>PC</font> row in the section 6 table is recording."))

A(P("8.3 The single_core/ modules are included via -I, not by relative path", H2))
A(P("The build requires an include search path:"))
A(code("""
    cd src
    iverilog -I ../single_core -o out.vvp Pipeline_Top_TestBench.v
    vvp out.vvp
"""))
A(P("The obvious alternative - "
    "<font face='Courier'>`include \"../single_core/Control_Unit_Top.v\"</font> "
    "- does not work, and the failure is worth knowing about because it is not "
    "obvious. That file itself contains "
    "<font face='Courier'>`include \"main_decoder.v\"</font>, and <b>a nested "
    "include is resolved relative to the current working directory, not relative "
    "to the file doing the including</b>. So the outer include succeeds and the "
    "inner one fails with <i>\"Include file main_decoder.v not found\"</i>. The "
    "<font face='Courier'>-I</font> search path resolves correctly at every "
    "level of nesting."))


# ============================================================== 9
A(P("9. Hazards, and Why This Build Solves Them in Software", H1))
A(P("A hazard is what happens when the pipeline's assumption - that instructions "
    "are independent - turns out to be false. This core has no hardware to "
    "detect them, so the test program is scheduled to avoid them. Every NOP in "
    "src/program.hex is derived below."))

A(P("9.1 The data hazard, and where the number 3 comes from", H2))
A(P("Number each instruction by the slot it is fetched into. With one "
    "instruction issued per cycle, a 100 ns clock, and reset releasing before "
    "the first real rising edge:"))
A(code("""
    instruction i occupies   IF   during  (100i + 100, 100i + 200)
                             ID   during  (100i + 200, 100i + 300)
                             EX   during  (100i + 300, 100i + 400)
                             MEM  during  (100i + 400, 100i + 500)
                             WB   during  (100i + 500, 100i + 600)
"""))
A(P("Register_file.v commits its write on the rising edge that <i>ends</i> WB, "
    "and reads are latched into the ID/EX register on the edge that ends ID:"))
A(code("""
    producer p commits its write at    t = 100p + 600
    consumer c samples its reads at    t = 100c + 300

    the consumer must sample strictly after the write lands:

        100p + 600  <  100c + 300
                 c  >  p + 3
                 c  >=  p + 4
"""))
A(P("<font face='Courier'>c = p + 4</font> means three instruction slots sit "
    "between producer and consumer. <b>Hence three NOPs.</b>"))
A(P("Why not two? Because Register_file.v has no write-through bypass. If the "
    "write were moved to the falling edge, or a read/write bypass added, this "
    "would shrink to two. Neither was done, because single_core/ is frozen and "
    "passing - see section 2."))
A(P("Once forwarding is built, this gap collapses to <b>zero</b>, because the "
    "consumer grabs the value directly off the EX/MEM or MEM/WB wires instead of "
    "waiting for it to travel all the way to the register file and back."))

A(P("9.2 Confirming the rule against real hardware", H2))
A(P("A derivation is a claim about the hardware, not a measurement of it. The "
    "rule was therefore tested: a scratch copy of the program was built with "
    "only <b>two</b> NOPs where the derivation demands three."))
A(code("""
    00500093    // slot 0   addi x1, x0, 5
    00300113    // slot 1   addi x2, x0, 3
    00000013    // slot 2   nop
    00000013    // slot 3   nop        <-- only two NOPs, not three
    002081b3    // slot 4   add  x3, x1, x2

    result:   ok  : x1 = 5
              ok  : x2 = 3
              FAIL: x3 = 5 (expected 8)
"""))
A(P("The failure is not merely present, it is <i>exactly the failure the "
    "arithmetic predicts</i>, which is much stronger evidence than a bare "
    "pass/fail:"))
A(B("x1 is produced in slot 0, consumed in slot 4. "
    "<font face='Courier'>4 &gt;= 0 + 4</font> holds, so x1 reads correctly as 5."))
A(B("x2 is produced in slot 1, consumed in slot 4. "
    "<font face='Courier'>4 &gt;= 1 + 4</font> fails, so x2 still reads as its "
    "reset value 0."))
A(B("The ALU therefore computes <font face='Courier'>5 + 0 = 5</font>, and x3 "
    "lands on 5 rather than 8. Precisely the observed value."))
A(P("One instruction being correct while the other is stale, in the same "
    "instruction, is a signature that no amount of hand-waving produces by "
    "accident. The 3-NOP rule describes this hardware exactly.", Note))

A(P("9.3 The control hazard, and where the number 2 comes from", H2))
A(P("The branch at slot i resolves during its EX interval, so the PC only "
    "accepts <font face='Courier'>PCTargetE</font> at "
    "<font face='Courier'>t = 100i + 400</font>. Fetch never stopped: slots i+1 "
    "and i+2 have already been read from memory. With no flush logic, both "
    "execute. <b>Hence two delay slots.</b>"))
A(P("This is why the taken branch in src/program.hex uses an offset of +16 where "
    "the single-cycle version used +8 - the two delay slots sit between the "
    "branch and the instruction being skipped:"))
A(code("""
    0x3c   beq x1, x1, +16        the branch
    0x40   nop                    delay slot 1 - runs anyway
    0x44   nop                    delay slot 2 - runs anyway
    0x48   addi x11, x0, 99       the instruction we actually want to skip
    0x4c   addi x12, x0, 7        target:  0x4c - 0x3c = 16
"""))
A(P("The encoding was verified by hand against Sign_Extend.v's B-type "
    "unscrambling "
    "<font face='Courier'>{{19{In[31]}}, In[31], In[7], In[30:25], In[11:8], "
    "1'b0}</font>. For <font face='Courier'>0x00108863</font>: In[31]=0, In[7]=1, "
    "In[30:25]=000000, In[11:8]=0000, giving "
    "<font face='Courier'>0_1_000000_0000_0</font> = 16. Correct."))

A(P("9.4 The hazard that needs no NOP at all", H2))
A(P("It would be easy to assume a store followed immediately by a load from the "
    "same address also needs padding. It does not, and the reason is worth "
    "following because it is genuinely tight."))
A(P("Data_Memory writes on the rising clock edge but reads combinationally. The "
    "store at slot 11 commits its write at the edge that <i>ends</i> its MEM "
    "interval, t = 1600. The load at slot 12 has its MEM interval running from "
    "t = 1600 to t = 1700, and its read is combinational across that whole "
    "window - so it sees memory <i>after</i> the store landed. Its result is "
    "latched into MEM/WB at t = 1700."))
A(P("So <font face='Courier'>sw</font> immediately followed by "
    "<font face='Courier'>lw</font> works with zero NOPs. It works only because "
    "the write happens at the boundary and the read happens across the interval "
    "that follows. The regression exercises this deliberately: x9 = 8 in the "
    "check list is what proves it."))


# ============================================================== 10
A(P("10. The Test Program", H1))
A(P("src/program.hex computes exactly the same twelve results, into the same "
    "registers, as single_core/program.hex. That equivalence is deliberate: the "
    "two cores must reach an <b>identical architectural outcome</b>, so the same "
    "twelve assertions can be used on both. What differs is the schedule."))
A(code("""
 idx  addr   encoding   instruction          | why it is here
  0   0x00   00500093   addi x1, x0, 5       | x1 = 5
  1   0x04   00300113   addi x2, x0, 3       | x2 = 3
  2   0x08   00000013   nop                  | \\
  3   0x0c   00000013   nop                  |  > 3 NOPs: let x1 and x2 commit
  4   0x10   00000013   nop                  | /
  5   0x14   002081b3   add  x3, x1, x2      | x3 = 8   (5>=0+4 ok, 5>=1+4 ok)
  6   0x18   40208233   sub  x4, x1, x2      | x4 = 2
  7   0x1c   0020f2b3   and  x5, x1, x2      | x5 = 1
  8   0x20   0020e333   or   x6, x1, x2      | x6 = 7
  9   0x24   001123b3   slt  x7, x2, x1      | x7 = 1
 10   0x28   0020a433   slt  x8, x1, x2      | x8 = 0
 11   0x2c   00302023   sw   x3, 0(x0)       | mem[0] = 8. x3 from idx 5:
      |                                      |   11 >= 5+4, so the six
      |                                      |   independent ops above double
      |                                      |   as the required spacing
 12   0x30   00002483   lw   x9, 0(x0)       | x9 = 8. No NOP needed - see 9.4
 13   0x34   00208463   beq  x1, x2, +8      | NOT taken (5 != 3), no slots needed
 14   0x38   00100513   addi x10, x0, 1      | x10 = 1 - proves fall-through
 15   0x3c   00108863   beq  x1, x1, +16     | TAKEN (5 == 5) -> 0x4c
 16   0x40   00000013   nop                  | delay slot 1
 17   0x44   00000013   nop                  | delay slot 2
 18   0x48   06300593   addi x11, x0, 99     | MUST be skipped -> x11 stays 0
 19   0x4c   00700613   addi x12, x0, 7      | x12 = 7 - the branch target
"""))
A(P("Notice that the six independent R-type instructions at slots 5-10 are doing "
    "double duty: they are the instructions under test, <i>and</i> they provide "
    "the spacing the store at slot 11 needs before it can read x3. Real "
    "schedulers do this constantly - filling hazard gaps with useful work rather "
    "than NOPs is most of what an instruction scheduler is for."))
A(P("Five of the twenty words are NOPs. That is a 25% overhead, and it is the "
    "honest price of having no hazard hardware. Forwarding would eliminate the "
    "three data-hazard NOPs entirely; flush logic would eliminate the two delay "
    "slots.", Note))

A(P("Why x11 is the most important check", H2))
A(P("x11 is never written by this program, and reads back as 0 because "
    "Register_file.v clears all 32 registers on reset. If the branch silently "
    "failed to redirect the PC, slot 18 would run and x11 would become 99. "
    "Together with x12 = 7, that pair is what makes this a real test of branch "
    "behaviour rather than a test that passes by accident - a check that can only "
    "pass for the right reason."))

# ============================================================== 11
A(P("11. Verification", H1))
A(code("""
    cd src
    iverilog -I ../single_core -o out.vvp Pipeline_Top_TestBench.v
    vvp out.vvp
    gtkwave Pipeline_Top_TestBench.vcd        # optional
"""))
A(P("The testbench is self-checking - it peeks into the register file "
    "hierarchically and asserts twelve expected values, rather than relying on a "
    "manual waveform read:"))
A(code("""
    === 5-stage pipelined RV32I regression (src/program.hex) ===
      ok  : x1 = 5
      ok  : x2 = 3
      ok  : x3 = 8
      ok  : x4 = 2
      ok  : x5 = 1
      ok  : x6 = 7
      ok  : x7 = 1
      ok  : x8 = 0
      ok  : x9 = 8
      ok  : x10 = 1
      ok  : x11 = 0
      ok  : x12 = 7
    RESULT: PASS - all 12 checks passed
"""))
A(P("The hierarchical path is one level deeper than in the single-cycle "
    "testbench - <font face='Courier'>DUT.Decode.Register_file.Register[n]</font> "
    "- because in a pipeline the register file belongs to the decode stage, even "
    "though write-back drives its write port."))
A(P("<font face='Courier'>vvp</font> also prints a "
    "<font face='Courier'>$readmemh: Not enough words in the file for the "
    "requested range</font> warning. Expected and harmless: program.hex is 20 "
    "words, instruction memory is 1024, and the remainder was already "
    "zero-filled - which decodes to a harmless NOP."))

A(P("How long the run takes, and why", H2))
A(P("The last instruction to retire is <font face='Courier'>addi x12, x0, 7</font> "
    "at 0x4c. It is <b>fetch slot 18, not 19</b>: the taken branch at slot 15 "
    "redirects the PC at t = 1900, so slot 18 fetches 0x4c and address 0x48 is "
    "never fetched at all. Its write commits at t = 600 + 1800 = 2400, and the "
    "testbench samples at t = 2625."))
A(P("Two costs versus the single-cycle core, both structural rather than "
    "accidental:"))
A(B("<b>Pipeline fill.</b> Nothing retires until t = 600 - four dead cycles "
    "while the first instruction walks down the pipe."))
A(B("<b>The NOPs.</b> Five of the twenty words exist purely to space out "
    "hazards, and each still costs a full cycle."))
A(P("Neither is a throughput loss. Once the pipe is full, one instruction still "
    "completes every cycle - which is the entire point of the exercise."))


# ============================================================== 12
A(P("12. What Is Not Implemented Yet", H1))
A(P("Stated plainly, so nothing here is mistaken for a claim it does not make:"))
A(table([
    ["Not implemented", "What it would do", "What it would remove"],
    ["Forwarding / bypass network", "Route EX/MEM and MEM/WB results directly "
     "back to the ALU inputs, so a consumer never waits for the register file.",
     "All three data-hazard NOPs."],
    ["Hazard detection unit", "Compare RdE/RdM/RdW against the rs1/rs2 fields "
     "in decode and drive the forwarding muxes.",
     "The need to hand-schedule dependent instructions."],
    ["Load-use stall", "Detect the one case forwarding cannot fix - a load "
     "feeding the very next instruction - and hold IF/ID and ID/EX for one cycle.",
     "The remaining correctness gap after forwarding."],
    ["Branch flush", "Clear IF/ID and ID/EX when PCSrcE asserts, turning the two "
     "wrongly-fetched instructions into bubbles.",
     "Both delay-slot NOPs."],
], [1.35 * 72, 2.75 * 72, 1.8 * 72]))
A(P("These are the next stage of the project, and the order above is roughly the "
    "order they should be built in: forwarding first, because it removes the most "
    "NOPs for the least logic; then the load-use stall, because it is the one "
    "case forwarding provably cannot solve; then flushing."))
A(P("A useful property of the current build is that it gives all four features a "
    "<b>regression to be measured against</b>. When forwarding lands, the three "
    "data-hazard NOPs can be deleted from program.hex and the same twelve "
    "assertions must still pass. When flushing lands, the two delay slots can go "
    "and the branch offset returns to +8. Each feature has a concrete, falsifiable "
    "definition of done, expressed as NOPs removed while the twelve results stay "
    "identical.", Note))

# ============================================================== appendix A
A(P("Appendix A. File Map", H1))
A(table([
    ["File", "Contains", "Stage"],
    ["src/Fetch_Cycle.v", "PC_Module, PC_Adder, instruction_Memory, PC-source "
     "mux, IF/ID register", "1 - IF"],
    ["src/Decode_Cycle.v", "Control_Unit_Top, Register_file, Sign_Extend, "
     "ID/EX register", "2 - ID"],
    ["src/Execute_Cycle.v", "ALU, Branch_Adder, SrcB mux, PCSrcE AND gate, "
     "EX/MEM register", "3 - EX"],
    ["src/Memory_Cycle.v", "Data_Memory, MEM/WB register", "4 - MEM"],
    ["src/Writeback_Cycle.v", "Result mux only - no pipeline register", "5 - WB"],
    ["src/Pipeline_Top.v", "Wiring and includes only. No logic.", "all"],
    ["src/program.hex", "20-instruction regression program with derived NOP "
     "scheduling", "-"],
    ["src/Pipeline_Top_TestBench.v", "Self-checking regression, 12 assertions", "-"],
], [1.75 * 72, 3.05 * 72, 1.1 * 72], mono_cols={0}))

# ============================================================== appendix B
A(P("Appendix B. Signal Reference", H1))
A(table([
    ["Signal", "Width", "Meaning"],
    ["PCF / PCD / PCE", "32", "The instruction's own address, as it travels IF, "
     "ID, EX. Needed in EX by the branch adder."],
    ["PCPlus4F", "32", "PCF + 4. Never leaves the fetch stage - see section 6."],
    ["PCNextF", "32", "Output of the PC-source mux; the address fetched next cycle."],
    ["InstrF / InstrD", "32", "The instruction word. Dies at the ID/EX boundary, "
     "fully translated into control bits and operands."],
    ["PCSrcE", "1", "<b>Backward path 1.</b> BranchE &amp; ZeroE - 1 means a "
     "branch in EX resolved as taken."],
    ["PCTargetE", "32", "<b>Backward path 1.</b> PCE + ImmExtE, where a taken "
     "branch wants to go."],
    ["BranchE", "1", "Raw branch-opcode bit. <b>Not</b> \"branch taken\" - see "
     "section 8.1."],
    ["ZeroE", "1", "ALU zero flag. For beq the ALU subtracts, so this is high "
     "exactly when rs1 == rs2."],
    ["RD1E / RD2E", "32", "The rs1 and rs2 register values read in decode."],
    ["ImmExtE", "32", "Sign-extended immediate. Feeds both the SrcB mux and the "
     "branch adder, both in EX."],
    ["SrcBE", "32", "Second ALU operand after the ALUSrc mux: rs2 or the immediate."],
    ["ALU_ResultM", "32", "The address for a load or store; the answer for "
     "everything else."],
    ["WriteDataM", "32", "rs2, renamed at the EX/MEM boundary to document its "
     "role as store data."],
    ["ReadDataW", "32", "The word a load pulled out of data memory."],
    ["RegWriteW", "1", "<b>Backward path 2.</b> Register file write enable. The "
     "longest journey in the design: decoded in ID, used in WB."],
    ["RdW", "5", "<b>Backward path 2.</b> Destination register number."],
    ["ResultW", "32", "<b>Backward path 2.</b> The value written into RdW."],
], [1.2 * 72, 0.5 * 72, 4.2 * 72], mono_cols={0}))

build(s)
print("wrote", OUT)
