#!/usr/bin/env python3
"""
Generates docs/RV32I_Single_Cycle_Core.pdf - the full project documentation for the
single-cycle RV32I core in single_core/.

Run from anywhere:   python docs/generate_pdf.py

Kept in the repo so the PDF is regenerable rather than a binary blob nobody can update.
Only ASCII is emitted: ReportLab's built-in Type-1 fonts have no glyphs for arrows,
box-drawing or emoji, and missing glyphs render as solid black boxes.
"""

import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
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
OUT = os.path.join(HERE, "RV32I_Single_Cycle_Core.pdf")

ACCENT = colors.HexColor("#1f4e79")
LIGHT = colors.HexColor("#dce6f1")
CODE_BG = colors.HexColor("#f4f4f4")
RULE = colors.HexColor("#b0b8c0")

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
TblCell = ParagraphStyle("TblCell", parent=Body, fontSize=8.4, leading=11, spaceAfter=0)
TblHead = ParagraphStyle("TblHead", parent=TblCell, fontName="Helvetica-Bold",
                         textColor=colors.white)
TblMono = ParagraphStyle("TblMono", parent=TblCell, fontName="Courier", fontSize=7.8)


def P(t, s=Body):
    return Paragraph(t, s)


def B(t):
    return Paragraph(t, Bullet, bulletText="-")


def code(t):
    return Preformatted(t.strip("\n"), Code)


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


# ----------------------------------------------------------------- datapath diagram

def datapath_diagram():
    """Hand-laid single-cycle datapath, mirroring the Mermaid diagram in README.md."""
    W, H = 468, 424
    d = Drawing(W, H)

    def box(x, y, w, h, lines, fill=colors.white, fs=7.2, stroke=ACCENT):
        d.add(Rect(x, y, w, h, fillColor=fill, strokeColor=stroke, strokeWidth=0.9))
        n = len(lines)
        for i, ln in enumerate(lines):
            ty = y + h / 2.0 + (n - 1) * (fs + 1.4) / 2.0 - i * (fs + 1.4) - fs * 0.36
            d.add(String(x + w / 2.0, ty, ln, fontName="Helvetica-Bold",
                         fontSize=fs, fillColor=colors.black, textAnchor="middle"))

    def mux(x, y, w, h, label):
        d.add(Rect(x, y, w, h, fillColor=colors.HexColor("#fdf1d6"),
                   strokeColor=colors.HexColor("#b8860b"), strokeWidth=0.9))
        d.add(String(x + w / 2.0, y + h / 2.0 - 2.4, label, fontName="Helvetica-Bold",
                     fontSize=6.2, fillColor=colors.black, textAnchor="middle"))

    def head(x, y, dx, dy, c):
        """Arrowhead at (x,y) pointing along unit direction (dx,dy)."""
        s = 4.0
        px, py = -dy, dx
        d.add(Polygon([x, y,
                       x - dx * s + px * s * 0.5, y - dy * s + py * s * 0.5,
                       x - dx * s - px * s * 0.5, y - dy * s - py * s * 0.5],
                      fillColor=c, strokeColor=c))

    def path(pts, label=None, lx=None, ly=None, dash=None, anchor="middle",
             c=colors.HexColor("#333333"), arrow=True):
        for i in range(len(pts) - 1):
            x1, y1 = pts[i]
            x2, y2 = pts[i + 1]
            ln = Line(x1, y1, x2, y2, strokeColor=c, strokeWidth=0.8)
            if dash:
                ln.strokeDashArray = dash
            d.add(ln)
        if arrow:
            x1, y1 = pts[-2]
            x2, y2 = pts[-1]
            L = max(((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5, 0.001)
            head(x2, y2, (x2 - x1) / L, (y2 - y1) / L, c)
        if label:
            d.add(String(lx, ly, label, fontName="Helvetica", fontSize=5.9,
                         fillColor=c, textAnchor=anchor))

    DASH = colors.HexColor("#a03030")
    GREEN = colors.HexColor("#eaf3ea")

    # ---- blocks
    box(10, 246, 40, 46, ["PC", "PC.v"])
    box(72, 358, 56, 26, ["PC_Adder", "PC + 4"], fill=GREEN)
    box(160, 334, 66, 26, ["Branch_Adder", "PC + Imm_Ext"], fill=GREEN, fs=6.6)
    mux(256, 342, 15, 48, "MUX")
    box(70, 240, 62, 58, ["instruction", "Memory"])
    box(156, 212, 68, 96, ["Register_file", "rs1 / rs2 / rd"])
    box(156, 152, 68, 30, ["Sign_Extend"])
    mux(244, 214, 15, 52, "MUX")
    box(278, 232, 54, 56, ["ALU"])
    box(356, 232, 62, 54, ["Data_Memory"])
    mux(434, 230, 15, 56, "MUX")
    box(46, 34, 380, 30, ["Control_Unit_Top   (main_decoder + ALU_decoder)"],
        fill=colors.HexColor("#fbe9e9"), fs=7.6, stroke=DASH)

    # ---- PC fan-out and next-PC logic
    path([(50, 269), (70, 269)], "PC", 60, 272)
    path([(60, 269), (60, 371), (72, 371)], "PC", 72, 320)
    path([(60, 330), (175, 330), (175, 334)], "PC", 140, 336)
    path([(128, 371), (244, 371), (244, 382), (256, 382)], "PCPlus4", 186, 374)
    path([(226, 347), (244, 347), (244, 352), (256, 352)], "PCTarget", 248, 332, anchor="start")
    path([(271, 366), (290, 366), (290, 406), (30, 406), (30, 292)],
         "PC_Next", 160, 409)

    # ---- fetch / decode
    path([(132, 269), (156, 269)], "instr", 140, 302)
    path([(150, 269), (150, 167), (156, 167)], "instr", 152, 190, anchor="start")

    # ---- immediate: to the ALUSrc mux and to the branch-target adder
    path([(224, 167), (232, 167), (232, 318), (212, 318), (212, 334)],
         "Imm_Ext", 180, 322)
    path([(232, 222), (244, 222)])

    # ---- register file outputs
    path([(224, 278), (278, 278)], "RD1", 250, 282)
    path([(224, 240), (238, 240), (238, 254), (244, 254)], "RD2", 240, 270,
         anchor="start")
    path([(238, 240), (238, 205), (348, 205), (348, 244), (356, 244)],
         "RD2 (store data)", 228, 196, anchor="end")
    path([(259, 240), (278, 240)])

    # ---- execute / memory / write-back
    path([(332, 262), (346, 262), (346, 310), (424, 310), (424, 268), (434, 268)],
         "ALU_Result", 385, 314)
    path([(346, 262), (356, 262)])
    path([(418, 250), (434, 250)], "Read_Data", 430, 216, anchor="end")
    path([(449, 258), (458, 258), (458, 112), (136, 112), (136, 222), (156, 222)],
         "WD3  (write-back)", 240, 116, anchor="end")

    # ---- control (dashed)
    dash = (2, 2)
    path([(96, 240), (96, 64)], "op / funct3 / funct7", 92, 160,
         dash=dash, anchor="end", c=DASH)
    path([(320, 232), (320, 88), (56, 88), (56, 64)], "Z (zero flag)", 324, 150,
         dash=dash, anchor="start", c=DASH)
    path([(170, 64), (170, 212)], "RegWrite / ImmSrc", 174, 130,
         dash=dash, anchor="start", c=DASH)
    path([(248, 64), (248, 214)], "ALUSrc", 244, 150,
         dash=dash, anchor="end", c=DASH)
    path([(305, 64), (305, 232)], "ALUControl", 301, 130,
         dash=dash, anchor="end", c=DASH)
    path([(387, 64), (387, 232)], "MemWrite", 391, 170,
         dash=dash, anchor="start", c=DASH)
    path([(441, 64), (441, 230)], "ResultSrc", 437, 150,
         dash=dash, anchor="end", c=DASH)
    path([(76, 64), (76, 76), (266, 76), (266, 342)], "PCSrc", 270, 300,
         dash=dash, anchor="start", c=DASH)

    d.add(String(W / 2.0, 14, "solid = datapath      dashed = control",
                 fontName="Helvetica-Oblique", fontSize=6.6,
                 fillColor=colors.HexColor("#666666"), textAnchor="middle"))
    return d


# --------------------------------------------------------------------------- layout

def on_page(canvas, doc):
    canvas.saveState()
    n = canvas.getPageNumber()
    if n > 1:
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(colors.HexColor("#777777"))
        canvas.drawString(72, LETTER[1] - 46,
                          "RV32I Single-Cycle Core - Project Documentation")
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
                          title="RV32I Single-Cycle Core - Project Documentation",
                          author="Swastik Aditya Ranjan",
                          subject="RV32I processor core in Verilog: design, "
                                  "debug and verification")
    frame = Frame(72, 60, LETTER[0] - 144, LETTER[1] - 124, id="body")
    doc.addPageTemplates([PageTemplate(id="all", frames=[frame], onPage=on_page)])
    doc.build(story)


# --------------------------------------------------------------------------- content

story = []
A = story.append

# ============================================================== 0. title page
A(Spacer(1, 1.5 * inch))
A(P("RV32I Single-Cycle Processor Core", TitleS))
A(Spacer(1, 4))
A(P("Design, Debug and Verification of a From-Scratch<br/>"
    "RISC-V Datapath in Verilog", SubTitleS))
A(Spacer(1, 0.45 * inch))

A(Table([[Paragraph(
    "<b>Author</b><br/>Swastik Aditya Ranjan (@dr-paradox-design)<br/>"
    "B.Tech Electrical Engineering, NIT Rourkela<br/><br/>"
    "<b>Repository</b><br/>dr-paradox-design/5_Stage_Pipelined_RISC-V<br/><br/>"
    "<b>Status</b><br/>Single-cycle core complete and verified by a self-checking "
    "regression.<br/>5-stage pipeline: not yet started.<br/><br/>"
    "<b>Toolchain</b><br/>Icarus Verilog (iverilog / vvp), GTKWave<br/>"
    "Target board (future): Digilent PYNQ-Z2",
    ParagraphStyle("tp", parent=Body, fontSize=10, leading=16,
                   alignment=TA_CENTER))]],
    colWidths=[4.6 * inch], hAlign="CENTER",
    style=TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.8, ACCENT),
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f7fafd")),
        ("TOPPADDING", (0, 0), (-1, -1), 16),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 16),
    ])))

A(Spacer(1, 0.6 * inch))
A(P("This document describes an RV32I processor core built from scratch in Verilog, "
    "following the Harris &amp; Harris single-cycle organisation. It covers the "
    "datapath, the control unit, every module in the design, the verification "
    "strategy, a detailed post-mortem of the branch-resolution defect that made "
    "<font face='Courier'>beq</font> silently non-functional, and the plan for the "
    "5-stage pipeline that follows.",
    ParagraphStyle("abs", parent=Body, fontSize=9.5, leading=14.5,
                   alignment=TA_CENTER, textColor=colors.HexColor("#444444"))))

A(PageBreak())

# ============================================================== contents
A(P("Contents", H1))
toc = [
    ("1", "Project Overview"),
    ("2", "Architecture and Datapath"),
    ("3", "Module Reference"),
    ("4", "Control Unit Specification"),
    ("5", "Instruction Set Support"),
    ("6", "Case Study: The Branch-Resolution Defect"),
    ("7", "Hardening Changes"),
    ("8", "Verification Strategy"),
    ("9", "Running the Simulation"),
    ("10", "Known Limitations"),
    ("11", "Roadmap: From Single-Cycle to 5-Stage Pipeline"),
    ("A", "Appendix: Top-Level Signal Reference"),
    ("B", "Appendix: Repository Layout"),
]
A(Table([[Paragraph(f"<b>{n}</b>", TblCell), Paragraph(t, TblCell)] for n, t in toc],
        colWidths=[0.4 * inch, 5.1 * inch], hAlign="LEFT",
        style=TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4.5),
            ("TOPPADDING", (0, 0), (-1, -1), 1),
            ("LINEBELOW", (0, 0), (-1, -2), 0.25, colors.HexColor("#e2e6ea")),
        ])))

A(PageBreak())

# ============================================================== 1. overview
A(P("1. Project Overview", H1))
A(P("The goal of this project is to build a working RISC-V processor from first "
    "principles, in stages, with each stage verified before the next begins. "
    "The RV32I base integer ISA was chosen because it is small enough to implement "
    "completely but real enough that the resulting core runs genuine compiled code."))
A(P("The work is deliberately staged:"))
A(B("<b>Stage 1 (complete).</b> A single-cycle datapath: one instruction per clock, "
    "no pipeline registers, no hazards to reason about. This establishes correct "
    "instruction decode, ALU behaviour, memory access and branch resolution in the "
    "simplest possible setting."))
A(B("<b>Stage 2 (next).</b> Split the same datapath across five pipeline stages "
    "(IF, ID, EX, MEM, WB), then add the machinery that a pipeline forces you to "
    "confront: forwarding paths, a hazard-detection unit, load-use stalls and "
    "branch flushing."))
A(B("<b>Stage 3 (future).</b> Synthesise onto a Digilent PYNQ-Z2 and verify the "
    "core on real hardware rather than only in simulation."))

A(P("1.1 Design Principles", H2))
A(B("<b>Nothing is 'done' until a test proves it.</b> Every instruction the core "
    "claims to support is exercised by a committed regression program, and the "
    "testbench asserts the expected architectural state rather than relying on a "
    "human reading a waveform."))
A(B("<b>Test programs live outside the RTL.</b> The instruction memory loads "
    "<font face='Courier'>program.hex</font> through "
    "<font face='Courier'>$readmemh</font>, so changing the program never means "
    "editing or recompiling the design."))
A(B("<b>Every non-obvious change carries a comment.</b> Fixes in the RTL are marked "
    "<font face='Courier'>//FIX:</font> and structural or hygiene changes "
    "<font face='Courier'>//CHANGED:</font>, each explaining what the previous "
    "behaviour was and why it was wrong. The RTL doubles as the change log."))
A(B("<b>Deterministic start-up.</b> Both memories and the register file are "
    "explicitly zeroed, so an unwritten location reads as 0 instead of smearing X "
    "through the register file and the waveform."))

# ============================================================== 2. architecture
A(PageBreak())
A(P("2. Architecture and Datapath", H1))
A(P("The core is a classic single-cycle machine: the program counter, instruction "
    "memory, register file, ALU, data memory and write-back mux are all traversed "
    "combinationally within one clock period, and the only state elements that "
    "update on the clock edge are the PC, the register file and the data memory. "
    "Cycles-per-instruction is exactly 1; the clock period is set by the longest "
    "path, which is the load path "
    "(PC -&gt; instruction memory -&gt; register file -&gt; ALU -&gt; data memory "
    "-&gt; write-back mux -&gt; register file setup)."))

A(Spacer(1, 4))
A(datapath_diagram())
A(P("Figure 1 - Single-cycle RV32I datapath as implemented in "
    "Single_Cycle_Top.v.", Caption))

A(P("2.1 Cycle Walkthrough", H2))
A(P("Within a single clock period the following happens, all combinationally:"))
A(B("<b>Fetch.</b> <font face='Courier'>PC</font> addresses "
    "<font face='Courier'>instruction_Memory</font>, which returns the 32-bit "
    "instruction. In parallel, <font face='Courier'>PC_Adder</font> computes "
    "<font face='Courier'>PC+4</font> and <font face='Courier'>Branch_Adder</font> "
    "computes <font face='Courier'>PC + Imm_Ext</font>."))
A(B("<b>Decode.</b> Instruction fields are sliced directly out of the fetched word: "
    "<font face='Courier'>rs1 = instr[19:15]</font>, "
    "<font face='Courier'>rs2 = instr[24:20]</font>, "
    "<font face='Courier'>rd = instr[11:7]</font>. "
    "<font face='Courier'>Control_Unit_Top</font> decodes "
    "<font face='Courier'>opcode</font>, <font face='Courier'>funct3</font> and "
    "<font face='Courier'>funct7</font> into every control signal, while "
    "<font face='Courier'>Sign_Extend</font> builds the immediate according to "
    "<font face='Courier'>ImmSrc</font>."))
A(B("<b>Execute.</b> The <font face='Courier'>ALUSrc</font> mux picks the second "
    "ALU operand: register <font face='Courier'>RD2</font> for R-type and branches, "
    "the sign-extended immediate for I-type, loads and stores. The ALU produces "
    "<font face='Courier'>ALU_Result</font> and the "
    "<font face='Courier'>Z</font> flag."))
A(B("<b>Memory.</b> For a load, <font face='Courier'>ALU_Result</font> is the "
    "address and <font face='Courier'>Read_Data</font> comes back. For a store, "
    "<font face='Courier'>MemWrite</font> is asserted and "
    "<font face='Courier'>RD2</font> is the data written at the clock edge."))
A(B("<b>Write-back.</b> The <font face='Courier'>ResultSrc</font> mux selects "
    "<font face='Courier'>Read_Data</font> for loads and "
    "<font face='Courier'>ALU_Result</font> otherwise; the result is written to "
    "<font face='Courier'>rd</font> at the clock edge when "
    "<font face='Courier'>RegWrite</font> is asserted."))
A(B("<b>Next PC.</b> <font face='Courier'>PCSrc</font> "
    "(branch opcode AND <font face='Courier'>Z</font>) selects "
    "<font face='Courier'>PCTarget</font> on a taken branch, otherwise "
    "<font face='Courier'>PCPlus4</font>. The chosen value is latched into the PC "
    "at the clock edge."))

A(P("2.2 Register Conventions", H2))
A(P("<font face='Courier'>x0</font> is hardwired to zero: reads of address 0 return "
    "<font face='Courier'>32'h00000000</font> unconditionally, and writes with "
    "<font face='Courier'>A3 == 0</font> are suppressed. Reset is active-low "
    "(<font face='Courier'>rst = 0</font> means in reset) and synchronously clears "
    "all 32 registers and the PC."))

# ============================================================== 3. modules
A(PageBreak())
A(P("3. Module Reference", H1))
A(P("All RTL lives in <font face='Courier'>single_core/</font>. "
    "<font face='Courier'>Single_Cycle_Top.v</font> "
    "<font face='Courier'>`include</font>s every leaf module, and the testbench "
    "<font face='Courier'>`include</font>s the top level, so the whole design "
    "compiles from a single file on the iverilog command line."))

A(table([
    ["Module (file)", "Role", "Ports"],
    ["<b>PC_Module</b><br/>PC.v",
     "Program counter register. Synchronous, active-low reset to 0.",
     "clk, rst, PC_NEXT[31:0] -&gt; PC[31:0]"],
    ["<b>PC_Adder</b><br/>PC_Adder.v",
     "Generic 32-bit adder. Instanced twice: once as PC+4, once as "
     "Branch_Adder for PC+Imm_Ext.",
     "a[31:0], b[31:0] -&gt; c[31:0]"],
    ["<b>instruction_Memory</b><br/>instruction_Memory.v",
     "1024 x 32-bit instruction memory. Zero-filled at time 0, then loaded from "
     "program.hex via $readmemh. Word-addressed using A[31:2].",
     "A[31:0], rst -&gt; RD[31:0]"],
    ["<b>Register_file</b><br/>Register_file.v",
     "32 x 32-bit architectural registers. Two combinational read ports, one "
     "synchronous write port. x0 reads as 0 and is never written.",
     "clk, rst, WE3, A1/A2/A3[4:0], WD3[31:0] -&gt; RD1[31:0], RD2[31:0]"],
    ["<b>Sign_Extend</b><br/>Sign_Extend.v",
     "Builds the 32-bit immediate for I-, S- and B-type instructions, selected "
     "by ImmSrc.",
     "In[31:0], ImmSrc[1:0] -&gt; Imm_Ext[31:0]"],
    ["<b>ALU</b><br/>ALU.v",
     "add, sub, and, or, slt. Shares one adder for add/sub by inverting B and "
     "feeding ALUControl[0] in as carry-in. Produces Z, N, C, V flags.",
     "A/B[31:0], ALUControl[2:0] -&gt; Result[31:0], Z, N, C, V"],
    ["<b>main_decoder</b><br/>main_decoder.v",
     "Decodes the opcode into RegWrite, MemWrite, ALUSrc, ResultSrc, ImmSrc, "
     "ALUOp, and combines the branch signal with the zero flag to form PCSrc.",
     "op[6:0], zero -&gt; RegWrite, MemWrite, ALUSrc, ResultSrc, ImmSrc[1:0], "
     "ALUOp[1:0], PCSrc"],
    ["<b>ALU_decoder</b><br/>ALU_decoder.v",
     "Maps ALUOp plus funct3/funct7/op[5] onto the 3-bit ALUControl code.",
     "ALUOp[1:0], funct3[2:0], funct7, op5 -&gt; ALUControl[2:0]"],
    ["<b>Control_Unit_Top</b><br/>Control_Unit_Top.v",
     "Wraps main_decoder and ALU_decoder and passes the ALU zero flag through to "
     "branch resolution.",
     "Op[6:0], funct3[2:0], funct7[6:0], zero -&gt; all control signals"],
    ["<b>Data_Memory</b><br/>Data_Mem.v",
     "1024 x 32-bit data memory. Zero-filled at time 0. Combinational read, "
     "synchronous write on WE.",
     "clk, rst, WE, A[31:0], WD[31:0] -&gt; RD[31:0]"],
    ["<b>Single_Cycle_Top</b><br/>Single_Cycle_Top.v",
     "Datapath integration: instantiates every module above and wires the "
     "ALUSrc, ResultSrc and PC-source muxes.",
     "clk, rst"],
], widths=[1.25 * inch, 2.85 * inch, 2.4 * inch], mono_cols={2}))

A(P("3.1 A Note on the Shared Adder", H2))
A(P("The ALU does not contain separate adder and subtractor hardware. "
    "<font face='Courier'>ALUControl[0]</font> selects between "
    "<font face='Courier'>B</font> and <font face='Courier'>~B</font> and is "
    "simultaneously fed in as the carry-in, so a single expression covers both "
    "operations - subtraction is two's-complement addition:"))
A(code("""
assign not_b = ~B;
assign mux1  = (ALUControl[0] == 1'b0) ? B : not_b;
assign {Cout, sum} = A + mux1 + ALUControl[0];
"""))
A(P("This is why <font face='Courier'>ALUControl</font> "
    "<font face='Courier'>000</font> (add) and <font face='Courier'>001</font> "
    "(sub) both select <font face='Courier'>sum</font> at the output mux: the "
    "distinction is already baked into how <font face='Courier'>sum</font> was "
    "computed. It is also why <font face='Courier'>beq</font> works at all - the "
    "branch comparison is a subtraction whose "
    "<font face='Courier'>Z</font> flag reports equality."))

# ============================================================== 4. control
A(PageBreak())
A(P("4. Control Unit Specification", H1))
A(P("Control is purely combinational and split in two: "
    "<font face='Courier'>main_decoder</font> looks only at the opcode and produces "
    "the datapath control signals plus a 2-bit "
    "<font face='Courier'>ALUOp</font>; <font face='Courier'>ALU_decoder</font> "
    "then refines <font face='Courier'>ALUOp</font> into a specific ALU operation "
    "using <font face='Courier'>funct3</font>, "
    "<font face='Courier'>funct7[5]</font> and "
    "<font face='Courier'>op[5]</font>. This two-level split keeps the opcode "
    "decode small and localises all R-type arithmetic selection in one place."))

A(P("4.1 Main Decoder", H2))
A(table([
    ["Instruction", "opcode", "RegWrite", "ImmSrc", "ALUSrc", "MemWrite",
     "ResultSrc", "branch", "ALUOp"],
    ["R-type", "0110011", "1", "xx", "0", "0", "0", "0", "10"],
    ["lw (I)", "0000011", "1", "00", "1", "0", "1", "0", "00"],
    ["addi (I)", "0010011", "1", "00", "1", "0", "0", "0", "00"],
    ["sw (S)", "0100011", "0", "01", "1", "1", "x", "0", "00"],
    ["beq (B)", "1100011", "0", "10", "0", "0", "x", "1", "01"],
], widths=[0.85 * inch, 0.72 * inch, 0.6 * inch, 0.48 * inch, 0.48 * inch,
           0.58 * inch, 0.58 * inch, 0.48 * inch, 0.45 * inch],
    mono_cols={1, 2, 3, 4, 5, 6, 7, 8}))
A(P("The final PC-source decision is one gate:", Body))
A(code("assign PCSrc = branch & zero;"))
A(P("A word of warning that cost real debugging time: the port on "
    "<font face='Courier'>main_decoder</font> is named "
    "<font face='Courier'>PCSrc</font>, but "
    "<font face='Courier'>Control_Unit_Top</font> exposes the same signal to the "
    "top level as <font face='Courier'>Branch</font>. It is one signal with two "
    "names, and it already includes the zero-flag term - it is not the raw "
    "'this is a branch instruction' bit."))

A(P("4.2 ALU Decoder", H2))
A(P("<font face='Courier'>concatination = {op5, funct7}</font>, where "
    "<font face='Courier'>funct7</font> here is the single bit "
    "<font face='Courier'>funct7[5]</font> that distinguishes "
    "<font face='Courier'>add</font> from <font face='Courier'>sub</font>. "
    "The <font face='Courier'>concatination != 2'b11</font> test is what stops an "
    "<font face='Courier'>addi</font> with a large immediate from being mistaken "
    "for a <font face='Courier'>sub</font>."))
A(table([
    ["ALUOp", "funct3", "{op5,funct7[5]}", "ALUControl", "Operation", "Used by"],
    ["00", "x", "x", "000", "add", "lw, sw, addi"],
    ["01", "x", "x", "001", "subtract", "beq (for the Z flag)"],
    ["10", "000", "!= 11", "000", "add", "add"],
    ["10", "000", "== 11", "001", "subtract", "sub"],
    ["10", "010", "x", "101", "set less than", "slt"],
    ["10", "110", "x", "011", "or", "or"],
    ["10", "111", "x", "010", "and", "and"],
], widths=[0.55 * inch, 0.6 * inch, 1.05 * inch, 0.8 * inch, 1.0 * inch,
           1.5 * inch], mono_cols={0, 1, 2, 3}))

A(P("4.3 Immediate Generation", H2))
A(P("RISC-V scrambles immediate bits across the instruction word so that each bit "
    "lands in a consistent position regardless of format, which keeps the "
    "multiplexing cheap. <font face='Courier'>Sign_Extend</font> unscrambles them:"))
A(code("""
assign Imm_Ext =
  (ImmSrc == 2'b01) ? {{20{In[31]}}, In[31:25], In[11:7]}                     // S-type
: (ImmSrc == 2'b10) ? {{19{In[31]}}, In[31], In[7], In[30:25], In[11:8], 1'b0} // B-type
:                     {{20{In[31]}}, In[31:20]};                              // I-type
"""))
A(B("<b>I-type</b> takes a contiguous 12-bit field from "
    "<font face='Courier'>In[31:20]</font>."))
A(B("<b>S-type</b> splits the 12 bits between "
    "<font face='Courier'>In[31:25]</font> and "
    "<font face='Courier'>In[11:7]</font>, because "
    "<font face='Courier'>rs2</font> occupies the middle of the word."))
A(B("<b>B-type</b> is the awkward one: the low bit is hardwired to "
    "<font face='Courier'>0</font> (branch targets are always even), and "
    "<font face='Courier'>In[7]</font> holds bit 11 while "
    "<font face='Courier'>In[31]</font> holds the sign bit. This is why a "
    "<font face='Courier'>beq</font> offset of +8 encodes as "
    "<font face='Courier'>0x00208463</font> rather than anything that looks like "
    "an 8."))

# ============================================================== 5. isa
A(PageBreak())
A(P("5. Instruction Set Support", H1))
A(P("The core implements the subset of RV32I needed to run straight-line "
    "arithmetic, memory access and conditional control flow. Every listed "
    "instruction is exercised by the committed regression program - the coverage "
    "claim is checked by the test suite, not asserted by hand."))

A(table([
    ["Format", "Instruction", "Semantics", "Verified by"],
    ["R", "add rd, rs1, rs2", "rd = rs1 + rs2", "x3 = 8"],
    ["R", "sub rd, rs1, rs2", "rd = rs1 - rs2", "x4 = 2"],
    ["R", "and rd, rs1, rs2", "rd = rs1 &amp; rs2", "x5 = 1"],
    ["R", "or rd, rs1, rs2", "rd = rs1 | rs2", "x6 = 7"],
    ["R", "slt rd, rs1, rs2", "rd = (rs1 &lt; rs2) ? 1 : 0", "x7 = 1, x8 = 0"],
    ["I", "addi rd, rs1, imm", "rd = rs1 + sext(imm)", "x1 = 5, x2 = 3"],
    ["I", "lw rd, imm(rs1)", "rd = mem[rs1 + sext(imm)]", "x9 = 8"],
    ["S", "sw rs2, imm(rs1)", "mem[rs1 + sext(imm)] = rs2", "mem[0] = 8, read back"],
    ["B", "beq rs1, rs2, imm",
     "if (rs1 == rs2) pc += sext(imm) else pc += 4",
     "x10 = 1 (not taken), x11 = 0 and x12 = 7 (taken)"],
], widths=[0.5 * inch, 1.35 * inch, 1.9 * inch, 2.75 * inch], mono_cols={1, 2}))

A(P("5.1 Not Implemented", H2))
A(P("The following RV32I instructions are deliberately out of scope for the "
    "single-cycle stage and are candidates for the pipelined version: "
    "<font face='Courier'>bne</font>, <font face='Courier'>blt</font>, "
    "<font face='Courier'>bge</font>, <font face='Courier'>bltu</font>, "
    "<font face='Courier'>bgeu</font>, <font face='Courier'>jal</font>, "
    "<font face='Courier'>jalr</font>, <font face='Courier'>lui</font>, "
    "<font face='Courier'>auipc</font>, the shift instructions "
    "(<font face='Courier'>sll</font>, <font face='Courier'>srl</font>, "
    "<font face='Courier'>sra</font> and their immediate forms), "
    "<font face='Courier'>xor</font>, <font face='Courier'>sltu</font>/"
    "<font face='Courier'>sltiu</font>, and the sub-word memory accesses "
    "(<font face='Courier'>lb</font>, <font face='Courier'>lh</font>, "
    "<font face='Courier'>lbu</font>, <font face='Courier'>lhu</font>, "
    "<font face='Courier'>sb</font>, <font face='Courier'>sh</font>). "
    "Both memories are word-addressed only; there is no byte-enable logic."))

# ============================================================== 6. case study
A(PageBreak())
A(P("6. Case Study: The Branch-Resolution Defect", H1))
A(P("This was the single most instructive bug in the project, and it is worth "
    "documenting in full because of how it hid. The core decoded "
    "<font face='Courier'>beq</font> perfectly: the opcode was recognised, the "
    "B-type immediate was extracted correctly, and the ALU performed the "
    "subtraction. Every module looked right in isolation. But the PC never "
    "redirected, so the branch simply did nothing - and because a not-taken branch "
    "also does nothing, nothing appeared visibly broken until a test specifically "
    "required a branch to be <i>taken</i>."))

A(P("6.1 Three Compounding Defects", H2))
A(P("The failure was not one bug but three, stacked such that fixing any one alone "
    "would have changed nothing observable:"))
A(B("<b>The zero flag was thrown away.</b> In "
    "<font face='Courier'>Single_Cycle_Top.v</font> the ALU was instantiated with "
    "<font face='Courier'>.Z()</font> - an explicitly unconnected port. Verilog "
    "accepts this silently; it is legal to leave an output dangling."))
A(B("<b>The control unit hardcoded the flag to zero.</b> "
    "<font face='Courier'>Control_Unit_Top</font> had no "
    "<font face='Courier'>zero</font> input at all and passed "
    "<font face='Courier'>.zero(1'b0)</font> into "
    "<font face='Courier'>main_decoder</font>. Since "
    "<font face='Courier'>PCSrc = branch &amp; zero</font>, "
    "<font face='Courier'>PCSrc</font> was a constant 0. This is the worst of the "
    "three: the logic was <i>present and correct</i>, just permanently starved of "
    "its input."))
A(B("<b>There was no branch-target path.</b> No adder computed "
    "<font face='Courier'>PC + Imm_Ext</font> and no PC-source mux existed. "
    "<font face='Courier'>PC_Module.PC_NEXT</font> was wired straight to "
    "<font face='Courier'>PCPlus4</font>, so even a correct "
    "<font face='Courier'>PCSrc</font> would have had nothing to select."))

A(P("6.2 Before and After", H2))
A(P("<b>Before</b> - the entire next-PC logic:", Body))
A(code("""
PC_Module PC_Module(
    .clk(clk), .rst(rst), .PC(PC_Top),
    .PC_NEXT(PCPlus4)          // the PC could only ever advance sequentially
);

ALU ALU(
    ... .Z(),                  // zero flag discarded
    .N(), .C(), .V()
);

// inside Control_Unit_Top:
main_decoder main_decoder(
    .op(Op), .zero(1'b0),      // PCSrc = branch & 0 = always 0
    ...
);
"""))

A(P("<b>After</b> - zero flag routed through, branch adder and PC mux added:", Body))
A(code("""
wire [31:0] PCTarget, PC_Next_Top;
wire        Zero_Top;

//FIX: new PC-source mux. Branch is Control_Unit_Top's PCSrc output
//(branch opcode & ALU zero flag) - selects the branch target on a taken
//branch, otherwise PC+4. This is what actually makes beq redirect fetch.
assign PC_Next_Top = Branch ? PCTarget : PCPlus4;

PC_Module PC_Module(
    .clk(clk), .rst(rst), .PC(PC_Top),
    .PC_NEXT(PC_Next_Top)      //FIX: was PCPlus4 directly
);

//FIX: new instance. Reuses PC_Adder as a generic adder to compute the
//branch target (PC + sign-extended branch immediate).
PC_Adder Branch_Adder( .a(PC_Top), .b(Imm_Ext_Top), .c(PCTarget) );

ALU ALU(
    ... .Z(Zero_Top),          //FIX: was .Z() - now feeds Control_Unit_Top
);

Control_Unit_Top Control_Unit(
    ... .zero(Zero_Top),       //FIX: new connection
);
"""))
A(P("And in <font face='Courier'>Control_Unit_Top.v</font>, a new port replacing "
    "the hardcoded constant:", Body))
A(code("""
//FIX: added this input. Previously main_decoder's zero port was hardcoded to 1'b0
//below, so PCSrc (Branch) = branch-opcode & zero was always 0 and beq could never
//take a branch. Now driven by the ALU's real zero flag from Single_Cycle_Top.
input zero;
...
main_decoder main_decoder(
    .op(Op),
    .zero(zero),   //FIX: was hardcoded .zero(1'b0)
    ...
);
"""))

A(P("6.3 Lessons", H2))
A(B("<b>An unconnected output port is a silent failure mode.</b> "
    "<font face='Courier'>.Z()</font> produces no warning in most flows. Reviewing "
    "the instantiation list of the top level for empty port connections is now a "
    "standard check."))
A(B("<b>Constants tied into control logic are worse than missing logic.</b> "
    "Missing logic fails to compile; a hardcoded "
    "<font face='Courier'>1'b0</font> compiles, simulates, and quietly disables a "
    "feature while the surrounding code looks complete."))
A(B("<b>Module-level correctness does not imply system-level correctness.</b> "
    "Every module involved was individually right. The bug lived entirely in the "
    "wiring between them, which is exactly what a top-level regression test "
    "catches and a unit test does not."))
A(B("<b>A test that cannot fail is not a test.</b> Verifying only that a "
    "not-taken branch falls through would have passed against the broken design. "
    "The regression deliberately includes a branch that must be "
    "<i>taken</i>, and the instruction it skips over writes a distinctive "
    "value (99) so a missed skip is unmistakable."))

# ============================================================== 7. hardening
A(PageBreak())
A(P("7. Hardening Changes", H1))
A(P("Beyond the branch fix, several changes were made to remove non-determinism "
    "and to make the design testable. Each is marked "
    "<font face='Courier'>//CHANGED:</font> in the source with the reasoning "
    "inline."))

A(P("7.1 Register File: Reset Now Actually Clears", H2))
A(P("The read ports already forced 0 during reset, which <i>looked</i> like a "
    "working reset. But the underlying array was never written, so the moment "
    "<font face='Courier'>rst</font> deasserted, whatever X or stale values the "
    "array held became visible again. The fix clears the array synchronously:"))
A(code("""
always @(posedge clk) begin
    //FIX: this if/else reset branch is new. Previously only WE3 writes were handled here
    //and RD1/RD2 above merely forced *reads* to 0 during reset - the Register array itself
    //was never actually cleared, so stale values could resurface once rst deasserted.
    if (!rst) begin
        for (i = 0; i < 32; i = i + 1)
            Register[i] <= 32'h00000000;
    end
    else begin
        if (WE3 && (A3 != 5'b00000)) begin
            Register[A3] <= WD3;
        end
    end
end
"""))

A(P("7.2 Instruction Memory: Program Loaded from a File", H2))
A(P("The test program used to be a hardcoded "
    "<font face='Courier'>Mem[0] = ...</font> assignment inside the RTL, so trying "
    "a different program meant editing and recompiling the design. It now loads "
    "from <font face='Courier'>program.hex</font>:"))
A(code("""
//CHANGED: declared ascending [0:1023] rather than [1023:0]. Indexing is identical,
//but $readmemh warns about ambiguous fill direction on a descending memory.
reg [31:0] Mem[0:1023];

initial begin
    //zero-fill first so untouched locations read as 32'h00000000 (a harmless NOP:
    //opcode 7'b0000000 asserts neither RegWrite nor MemWrite) instead of X
    for (j = 0; j < 1024; j = j + 1)
        Mem[j] = 32'h00000000;

    $readmemh("program.hex", Mem);
end
"""))
A(P("Two details worth recording. First, the memory declaration was flipped from "
    "<font face='Courier'>[1023:0]</font> to "
    "<font face='Courier'>[0:1023]</font>; the indexing is identical but "
    "<font face='Courier'>$readmemh</font> warns about ambiguous fill direction on "
    "a descending range. Second, an all-zero word is a benign NOP in this core - "
    "opcode <font face='Courier'>7'b0000000</font> matches no decoder case, so "
    "neither <font face='Courier'>RegWrite</font> nor "
    "<font face='Courier'>MemWrite</font> is asserted and the instruction has no "
    "architectural effect. That is what makes zero-filling safe."))

A(P("7.3 Data Memory: Zero Initialisation", H2))
A(P("Data memory started as all X, so a load from an address that had not yet been "
    "written returned X and propagated it through the register file and the entire "
    "waveform, making the trace unreadable. It is now zero-filled at time 0, "
    "matching the instruction memory."))

A(P("7.4 Testbench: Self-Contained Compilation", H2))
A(P("The compile command documented in the README was broken: nothing pulled the "
    "top-level module into the testbench, so "
    "<font face='Courier'>iverilog -o out.vvp Single_Cycle_Top_TestBench.v</font> "
    "failed with <i>Unknown module type: Single_Cycle_Top</i>. Adding one "
    "<font face='Courier'>`include</font> at the top of the testbench makes the "
    "documented command work as written."))

A(P("7.5 An Expected Warning", H2))
A(P("Running the simulation prints:"))
A(code("$readmemh: Not enough words in the file for the requested range [0:1023]"))
A(P("This is expected and harmless. The program is 15 instructions and the memory "
    "is 1024 words; everything past the program was already zero-filled by the "
    "loop above. A three-argument "
    "<font face='Courier'>$readmemh(\"program.hex\", Mem, 0)</font> was tried and "
    "does not suppress it, so the two-argument form was kept and the warning is "
    "documented instead of being worked around."))

# ============================================================== 8. verification
A(PageBreak())
A(P("8. Verification Strategy", H1))
A(P("Verification rests on three things: a regression program that touches every "
    "supported instruction, a self-checking testbench that asserts the resulting "
    "architectural state, and a negative test that proves the testbench can "
    "actually fail."))

A(P("8.1 The Regression Program", H2))
A(P("<font face='Courier'>single_core/program.hex</font> is 15 instructions, one "
    "32-bit word per line in hex, with <font face='Courier'>//</font> comments "
    "(which <font face='Courier'>$readmemh</font> accepts):"))
A(code("""
// addr  encoding   instruction         | effect
00500093   // 0x00  addi x1, x0, 5      | x1 = 5
00300113   // 0x04  addi x2, x0, 3      | x2 = 3
002081b3   // 0x08  add  x3, x1, x2     | x3 = 8
40208233   // 0x0c  sub  x4, x1, x2     | x4 = 2
0020f2b3   // 0x10  and  x5, x1, x2     | x5 = 5 & 3 = 1
0020e333   // 0x14  or   x6, x1, x2     | x6 = 5 | 3 = 7
001123b3   // 0x18  slt  x7, x2, x1     | x7 = (3 < 5) = 1
0020a433   // 0x1c  slt  x8, x1, x2     | x8 = (5 < 3) = 0
00302023   // 0x20  sw   x3, 0(x0)      | mem[0] = 8
00002483   // 0x24  lw   x9, 0(x0)      | x9 = 8
00208463   // 0x28  beq  x1, x2, +8     | NOT taken (5 != 3)
00100513   // 0x2c  addi x10, x0, 1     | x10 = 1  (proves fall-through)
00108463   // 0x30  beq  x1, x1, +8     | TAKEN (5 == 5)
06300593   // 0x34  addi x11, x0, 99    | MUST be skipped -> x11 stays 0
00700613   // 0x38  addi x12, x0, 7     | x12 = 7  (resumes at target)
"""))
A(P("The program is constructed so that each check isolates one behaviour:"))
A(B("<font face='Courier'>sw</font> then <font face='Courier'>lw</font> at the same "
    "address makes the store observable - a store alone writes to memory the "
    "testbench does not inspect, so it is read back into "
    "<font face='Courier'>x9</font> instead."))
A(B("<font face='Courier'>slt</font> is tested in both directions "
    "(<font face='Courier'>x7</font> true, <font face='Courier'>x8</font> false) so "
    "a stuck-at output cannot pass."))
A(B("Both branch outcomes are covered. The not-taken branch is proved by "
    "<font face='Courier'>x10 = 1</font> (the fall-through instruction ran). The "
    "taken branch is proved twice over: "
    "<font face='Courier'>x11 = 0</font> shows the skipped instruction did "
    "<i>not</i> run, and <font face='Courier'>x12 = 7</font> shows execution "
    "correctly resumed at the target rather than derailing."))

A(P("8.2 The Self-Checking Testbench", H2))
A(P("Rather than dumping a waveform for a human to inspect, the testbench compares "
    "each register against its expected value through a "
    "<font face='Courier'>check_reg</font> task and counts mismatches:"))
A(code("""
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
"""))
A(P("Note the <font face='Courier'>!==</font> rather than "
    "<font face='Courier'>!=</font>. The case-inequality operator treats X as a "
    "distinct value, so an uninitialised register is reported as a failure; "
    "<font face='Courier'>!=</font> would evaluate to X and the "
    "<font face='Courier'>if</font> would not fire, silently passing."))
A(P("The task reaches into the DUT through a hierarchical reference "
    "(<font face='Courier'>Single_Cycle_Top.Register_file.Register[num]</font>), "
    "which is what allows architectural state to be checked without adding debug "
    "ports to the design."))

A(P("8.3 Timing Analysis", H2))
A(P("The clock toggles every 50 time units, so the period is 100 and positive edges "
    "fall at t = 100, 200, 300, ... Reset deasserts at t = 125, before the second "
    "edge, so the first instruction retires at t = 200 and one more every 100 "
    "thereafter. Fifteen instructions are fetched but one is branched over, so 14 "
    "execute and the last write commits at t = 1500. The testbench waits until "
    "t = 2025 before checking - comfortably past the last write, with margin."))

A(P("8.4 The Negative Test", H2))
A(P("A passing test suite only means something if the suite is capable of failing. "
    "To prove that, the branch fix was deliberately re-broken in a scratch copy of "
    "the tree: <font face='Courier'>.zero(Zero_Top)</font> was reverted to "
    "<font face='Courier'>.zero(1'b0)</font> and the regression re-run. It "
    "correctly reported:"))
A(code("""
  FAIL: x11 = 99 (expected 0)
RESULT: FAIL - 1 check(s) failed
"""))
A(P("This confirms both that the fix is load-bearing and that the test has real "
    "teeth. The original working copy was untouched; the experiment ran in a "
    "throwaway directory."))

A(P("8.5 Current Result", H2))
A(code("""
=== single-cycle RV32I regression (program.hex) ===
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

# ============================================================== 9. running
A(PageBreak())
A(P("9. Running the Simulation", H1))
A(P("The design is simulated with Icarus Verilog and waveforms are viewed in "
    "GTKWave. Because the testbench includes the top level and the top level "
    "includes every leaf module, only one file needs to be named on the command "
    "line."))
A(code("""
cd single_core

iverilog -o out.vvp Single_Cycle_Top_TestBench.v   # compile
vvp out.vvp                                        # run the regression
gtkwave Single_Cycle_Top_TestBench.vcd             # inspect waveforms
"""))
A(P("Note that <font face='Courier'>vvp</font> must be run from inside "
    "<font face='Courier'>single_core/</font>: "
    "<font face='Courier'>$readmemh(\"program.hex\", ...)</font> resolves the path "
    "relative to the working directory, not to the source file."))

A(P("9.1 Running a Different Program", H2))
A(P("Because the program is loaded at simulation time rather than compiled in, "
    "swapping programs does not require touching the RTL. Edit "
    "<font face='Courier'>single_core/program.hex</font> - one 32-bit instruction "
    "per line in hex, <font face='Courier'>//</font> comments allowed - and update "
    "the <font face='Courier'>check_reg</font> expectations at the bottom of "
    "<font face='Courier'>Single_Cycle_Top_TestBench.v</font> to match. If the new "
    "program is longer, also extend the "
    "<font face='Courier'>#1900</font> delay so the last write has committed before "
    "the checks run."))

A(P("9.2 Useful Signals in the Waveform", H2))
A(table([
    ["Signal", "Why it matters"],
    ["PC_Top", "Instruction address. A jump that is not +4 is a taken branch."],
    ["RD_Instr", "The fetched instruction word - cross-check against program.hex."],
    ["Zero_Top", "ALU zero flag. Must be 1 on the cycle a beq is taken."],
    ["Branch", "PCSrc. This is the signal that was stuck at 0 before the fix."],
    ["PCTarget", "Computed branch target; compare against PC_Top on the next cycle."],
    ["ALU_Result_Top", "ALU output - doubles as the memory address for lw and sw."],
    ["WriteData", "Value heading into the register file write port."],
], widths=[1.25 * inch, 4.25 * inch], mono_cols={0}))

# ============================================================== 10. limitations
A(P("10. Known Limitations", H1))
A(B("<b>slt is incorrect on signed overflow.</b> The ALU computes "
    "<font face='Courier'>slt = {31'b0, sum[31]}</font> - it takes only the sign "
    "bit of <font face='Courier'>A - B</font>. This is the standard Harris &amp; "
    "Harris simplification and is right for the overwhelming majority of operand "
    "pairs, but when <font face='Courier'>A - B</font> overflows the sign bit lies. "
    "The correct expression is "
    "<font face='Courier'>sum[31] ^ V</font>. The "
    "<font face='Courier'>V</font> flag is already computed by the ALU, so the fix "
    "is one XOR; it is left as-is here to stay faithful to the reference design and "
    "is recorded rather than hidden."))
A(B("<b>Word-addressed memory only.</b> Both memories index with "
    "<font face='Courier'>A[31:2]</font> and have no byte-enable logic, so "
    "<font face='Courier'>lb</font>/<font face='Courier'>lh</font>/"
    "<font face='Courier'>sb</font>/<font face='Courier'>sh</font> cannot be "
    "supported without adding one. Misaligned accesses are silently truncated to "
    "the containing word rather than trapped."))
A(B("<b>Single-cycle timing.</b> The clock period must accommodate the full load "
    "path, so the maximum frequency is set by the slowest instruction even though "
    "most instructions do not need that much time. This is precisely the problem "
    "the pipeline stage of the project exists to solve."))
A(B("<b>No exceptions, no CSRs, no privileged modes.</b> There is no trap "
    "mechanism, no <font face='Courier'>mtvec</font>/"
    "<font face='Courier'>mcause</font>, and no way to signal an illegal "
    "instruction - an unrecognised opcode decodes to all-zero control and is "
    "silently ignored as a NOP."))
A(B("<b>No branch instructions other than beq.</b> "
    "<font face='Courier'>bne</font> and the ordering branches would need "
    "additional funct3 decoding and, for the signed/unsigned comparisons, use of "
    "the <font face='Courier'>N</font> and <font face='Courier'>V</font> flags "
    "that the ALU already produces but the control unit currently ignores."))
A(B("<b>Simulation only.</b> The design has not been synthesised. Constructs such "
    "as the <font face='Courier'>initial</font> blocks that zero-fill memory map "
    "onto FPGA block RAM initialisation but would not exist in an ASIC flow, where "
    "an explicit reset sequence would be required."))

# ============================================================== 11. roadmap
A(PageBreak())
A(P("11. Roadmap: From Single-Cycle to 5-Stage Pipeline", H1))
A(P("The single-cycle core is the reference implementation. The pipelined core must "
    "produce bit-identical architectural state for the same program - which is "
    "exactly why the regression was built first. It becomes the equivalence check "
    "for the pipeline."))

A(P("11.1 Completed", H2))
A(B("Single-cycle RV32I datapath (fetch, decode, execute, memory, write-back)."))
A(B("Branch resolution: zero flag routed to control, PC-source mux, branch-target "
    "adder."))
A(B("Deterministic reset and zero-initialised memories."))
A(B("Program loading from <font face='Courier'>program.hex</font> via "
    "<font face='Courier'>$readmemh</font>."))
A(B("Self-checking regression covering every supported instruction, validated by a "
    "negative test."))

A(P("11.2 Next: Pipeline Stages", H2))
A(P("The plan, in dependency order:"))
A(table([
    ["Step", "Work", "What it forces you to confront"],
    ["1", "Insert the four pipeline registers: IF/ID, ID/EX, EX/MEM, MEM/WB. "
          "Carry control signals forward alongside data.",
     "Control signals must now travel with their instruction rather than being "
     "globally valid."],
    ["2", "Add the forwarding unit: EX/MEM and MEM/WB results routed back to the "
          "ALU input muxes.",
     "RAW hazards. Comparing destination registers in later stages against source "
     "registers in EX."],
    ["3", "Add the hazard-detection unit with load-use stall.",
     "The one hazard forwarding cannot fix - a load result is not available until "
     "MEM, so the dependent instruction must stall one cycle."],
    ["4", "Add branch flush logic.",
     "Control hazards. Instructions fetched after a branch that turns out to be "
     "taken must be squashed."],
    ["5", "Re-run the existing regression unchanged against the pipelined core.",
     "The final architectural state must match the single-cycle core exactly. "
     "Only the cycle count differs."],
    ["6", "Synthesise for PYNQ-Z2 and verify on hardware.",
     "Everything simulation lets you get away with: timing closure, real reset "
     "behaviour, block RAM inference."],
], widths=[0.42 * inch, 2.5 * inch, 2.58 * inch]))

A(P("11.3 Why the Regression Matters More Now", H2))
A(P("In a single-cycle machine, an instruction either works or it does not. In a "
    "pipeline, an instruction can work in isolation and fail only when preceded by "
    "a particular other instruction two slots earlier. That class of bug is nearly "
    "impossible to find by reading a waveform and trivial to find with a "
    "self-checking regression. Extending "
    "<font face='Courier'>program.hex</font> with back-to-back dependent "
    "instructions, load-use pairs and branches followed by side-effecting "
    "instructions is therefore part of the pipeline work, not an afterthought to "
    "it."))

# ============================================================== appendix A
A(PageBreak())
A(P("Appendix A: Top-Level Signal Reference", H1))
A(P("Every wire declared in <font face='Courier'>Single_Cycle_Top.v</font>, for "
    "cross-referencing against the waveform."))
A(table([
    ["Signal", "Width", "Driven by", "Meaning"],
    ["PC_Top", "32", "PC_Module", "Current instruction address"],
    ["PCPlus4", "32", "PC_Adder", "Sequential next address, PC + 4"],
    ["PCTarget", "32", "Branch_Adder", "Branch target, PC + Imm_Ext"],
    ["PC_Next_Top", "32", "PC-source mux", "Address latched into PC at the clock edge"],
    ["RD_Instr", "32", "instruction_Memory", "Fetched instruction word"],
    ["RD1_Top", "32", "Register_file", "rs1 value; first ALU operand"],
    ["RD2_Top", "32", "Register_file", "rs2 value; second ALU operand or store data"],
    ["Imm_Ext_Top", "32", "Sign_Extend", "Sign-extended immediate"],
    ["SrcB_Top", "32", "ALUSrc mux", "Second ALU operand after the mux"],
    ["ALU_Result_Top", "32", "ALU", "ALU output; memory address for lw and sw"],
    ["Read_Data_Top", "32", "Data_Memory", "Value returned by a load"],
    ["WriteData", "32", "ResultSrc mux", "Value written back to the register file"],
    ["ALU_Control_Top", "3", "ALU_decoder", "Selected ALU operation"],
    ["ImmSrc", "2", "main_decoder", "Immediate format select (I / S / B)"],
    ["Zero_Top", "1", "ALU", "ALU zero flag; drives branch resolution"],
    ["RegWrite", "1", "main_decoder", "Register file write enable"],
    ["MemWrite", "1", "main_decoder", "Data memory write enable"],
    ["ALUSrc", "1", "main_decoder", "0 = RD2, 1 = immediate"],
    ["ResultSrc", "1", "main_decoder", "0 = ALU result, 1 = memory read data"],
    ["Branch", "1", "Control_Unit_Top", "PCSrc: branch opcode AND zero flag"],
], widths=[1.15 * inch, 0.45 * inch, 1.15 * inch, 2.75 * inch], mono_cols={0, 1, 2}))

# ============================================================== appendix B
A(P("Appendix B: Repository Layout", H1))
A(code("""
.
+-- docs/
|   +-- RISC-V Project.md                     Design notes / project journal
|   +-- generate_pdf.py                       Generator for this document
|   +-- RV32I_Single_Cycle_Core.pdf           This document
+-- single_core/                              Single-cycle RV32I implementation
|   +-- PC.v                                  Program counter register
|   +-- PC_Adder.v                            Generic adder (PC+4 and branch target)
|   +-- instruction_Memory.v                  Instruction fetch, loads program.hex
|   +-- Register_file.v                       32 x 32-bit register file
|   +-- Sign_Extend.v                         I / S / B immediate extension
|   +-- ALU.v                                 add, sub, and, or, slt + flags
|   +-- ALU_decoder.v                         ALUOp/funct3/funct7 -> ALUControl
|   +-- main_decoder.v                        Opcode -> control signals
|   +-- Control_Unit_Top.v                    Wraps main + ALU decoders
|   +-- Data_Mem.v                            Load/store data memory
|   +-- Single_Cycle_Top.v                    Datapath integration
|   +-- program.hex                           Test program, loaded via $readmemh
|   +-- Single_Cycle_Top_TestBench.v          Self-checking testbench
|   +-- Single_Cycle_Top_TestBench.vcd/.gtkw  Waveform + GTKWave session
+-- src/
|   +-- Fetch_Cycle                           Placeholder for pipeline IF stage
+-- README.md
"""))

A(P("Convention for reading the source: search the RTL for "
    "<font face='Courier'>//FIX:</font> to find every change that repaired broken "
    "behaviour, and <font face='Courier'>//CHANGED:</font> for structural or "
    "hygiene changes. Each comment states what the code did before and why that "
    "was wrong, so the source files carry their own history."))

A(Spacer(1, 0.3 * inch))
A(P("<i>End of document.</i>", Caption))

build(story)
print("wrote", OUT)
