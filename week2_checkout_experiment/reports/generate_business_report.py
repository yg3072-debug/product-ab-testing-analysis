"""Generate the two-page Checkout A/B Testing Business Report.

The report is intentionally built from frozen portfolio results so the PDF,
experiment readout, dashboards, and reproducible SQL checks share one decision
story. Run this file directly; the default output is written beside the script.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import reportlab
from reportlab.lib.colors import Color, HexColor
from reportlab.lib.pagesizes import letter
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


PAGE_W, PAGE_H = letter
MARGIN = 36

FONT_DIR = Path(reportlab.__file__).resolve().parent / "fonts"
pdfmetrics.registerFont(TTFont("ReportSans", FONT_DIR / "Vera.ttf"))
pdfmetrics.registerFont(TTFont("ReportSans-Bold", FONT_DIR / "VeraBd.ttf"))

NAVY = HexColor("#111827")
SLATE = HexColor("#374151")
MUTED = HexColor("#667085")
CONTROL = HexColor("#6B7280")
TREATMENT = HexColor("#2563EB")
TREATMENT_DARK = HexColor("#1D4ED8")
BLUE_BG = HexColor("#EAF2FF")
AMBER = HexColor("#D97706")
AMBER_BG = HexColor("#FFF8E1")
GREEN = HexColor("#059669")
PAGE_BG = HexColor("#F5F7FA")
PANEL = HexColor("#FFFFFF")
LINE = HexColor("#D8DEE8")
SOFT_GRAY = HexColor("#EEF1F5")


def set_fill(c: canvas.Canvas, color: Color) -> None:
    c.setFillColor(color)


def text_width(text: str, font: str, size: float) -> float:
    return stringWidth(text, font, size)


def wrap_text(text: str, font: str, size: float, width: float) -> list[str]:
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words = paragraph.split()
        if not words:
            lines.append("")
            continue
        current = words[0]
        for word in words[1:]:
            candidate = f"{current} {word}"
            if text_width(candidate, font, size) <= width:
                current = candidate
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return lines


def draw_wrapped(
    c: canvas.Canvas,
    text: str,
    x: float,
    y_top: float,
    width: float,
    *,
    font: str = "ReportSans",
    size: float = 8.5,
    color: Color = SLATE,
    leading: float | None = None,
    max_lines: int | None = None,
) -> float:
    leading = leading or size * 1.35
    lines = wrap_text(text, font, size, width)
    if max_lines is not None and len(lines) > max_lines:
        lines = lines[:max_lines]
        last = lines[-1]
        while last and text_width(last + "...", font, size) > width:
            last = last[:-1]
        lines[-1] = last.rstrip() + "..."
    c.setFont(font, size)
    set_fill(c, color)
    y = y_top
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y


def draw_bullets(
    c: canvas.Canvas,
    items: list[str],
    x: float,
    y_top: float,
    width: float,
    *,
    size: float = 8.2,
    leading: float = 11.0,
    color: Color = SLATE,
    gap: float = 4.5,
) -> float:
    y = y_top
    for item in items:
        c.setFillColor(TREATMENT)
        c.circle(x + 2.5, y - 2.8, 1.7, fill=1, stroke=0)
        lines = wrap_text(item, "ReportSans", size, width - 13)
        c.setFont("ReportSans", size)
        set_fill(c, color)
        for line in lines:
            c.drawString(x + 12, y, line)
            y -= leading
        y -= gap
    return y


def round_rect(
    c: canvas.Canvas,
    x: float,
    y: float,
    w: float,
    h: float,
    *,
    fill: Color = PANEL,
    stroke: Color = LINE,
    radius: float = 8,
    line_width: float = 0.7,
) -> None:
    c.setLineWidth(line_width)
    c.setStrokeColor(stroke)
    c.setFillColor(fill)
    c.roundRect(x, y, w, h, radius, fill=1, stroke=1)


def draw_footer(c: canvas.Canvas, page_number: int) -> None:
    c.setStrokeColor(LINE)
    c.setLineWidth(0.6)
    c.line(MARGIN, 36, PAGE_W - MARGIN, 36)
    c.setFont("ReportSans", 7.5)
    set_fill(c, MUTED)
    c.drawString(MARGIN, 22, "Yucheng Gao | Product Analytics Portfolio | Simulated data")
    label = f"Page {page_number} of 2"
    c.drawRightString(PAGE_W - MARGIN, 22, label)


def draw_variant_legend(c: canvas.Canvas, x: float, y: float) -> None:
    c.setFillColor(CONTROL)
    c.roundRect(x, y - 7, 10, 10, 2, fill=1, stroke=0)
    c.setFont("ReportSans-Bold", 8)
    set_fill(c, SLATE)
    c.drawString(x + 15, y - 5, "Control")
    c.setFillColor(TREATMENT)
    c.roundRect(x + 68, y - 7, 10, 10, 2, fill=1, stroke=0)
    set_fill(c, SLATE)
    c.drawString(x + 83, y - 5, "Treatment")


def draw_report_header(
    c: canvas.Canvas,
    page_label: str,
    title: str,
    subtitle: str,
    *,
    title_size: float = 24,
) -> None:
    c.setFillColor(PAGE_BG)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    c.setFont("ReportSans-Bold", 8)
    set_fill(c, TREATMENT_DARK)
    c.drawString(MARGIN, 766, page_label.upper())
    c.setFont("ReportSans-Bold", title_size)
    set_fill(c, NAVY)
    c.drawString(MARGIN, 735, title)
    c.setFont("ReportSans", 8.8)
    set_fill(c, MUTED)
    c.drawString(MARGIN, 716, subtitle)
    draw_variant_legend(c, PAGE_W - MARGIN - 139, 766)


def draw_kpi_card(
    c: canvas.Canvas,
    x: float,
    y: float,
    w: float,
    title: str,
    value: str,
    note: str,
    *,
    value_color: Color = NAVY,
    value_size: float = 18,
) -> None:
    round_rect(c, x, y, w, 80)
    c.setFont("ReportSans", 7.5)
    set_fill(c, MUTED)
    c.drawString(x + 12, y + 59, title)
    c.setFont("ReportSans-Bold", value_size)
    set_fill(c, value_color)
    c.drawString(x + 12, y + 34, value)
    c.setFont("ReportSans", 7.0)
    set_fill(c, MUTED)
    c.drawString(x + 12, y + 13, note)


def draw_funnel(c: canvas.Canvas, x: float, y: float, w: float, h: float) -> None:
    round_rect(c, x, y, w, h)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(x + 14, y + h - 22, "Ordered checkout funnel")
    c.setFont("ReportSans", 7.2)
    set_fill(c, MUTED)
    c.drawString(x + 14, y + h - 35, "Cumulative users completing each ordered step")

    stages = [
        ("Checkout view", 7754, 7713),
        ("Payment attempt", 5844, 6004),
        ("Purchase", 2130, 2285),
    ]
    label_w = 78
    chart_x = x + 14 + label_w
    chart_w = w - label_w - 70
    max_value = 8000
    row_y = y + h - 61
    for stage, control, treatment in stages:
        c.setFont("ReportSans-Bold", 7.2)
        set_fill(c, SLATE)
        c.drawString(x + 14, row_y - 4, stage)
        for offset, value, color in [(0, control, CONTROL), (-12, treatment, TREATMENT)]:
            bar_y = row_y + offset - 3
            c.setFillColor(SOFT_GRAY)
            c.roundRect(chart_x, bar_y, chart_w, 7, 2, fill=1, stroke=0)
            c.setFillColor(color)
            bar_w = chart_w * value / max_value
            c.roundRect(chart_x, bar_y, bar_w, 7, 2, fill=1, stroke=0)
            c.setFont("ReportSans-Bold", 6.8)
            set_fill(c, SLATE)
            c.drawRightString(x + w - 12, bar_y + 0.2, f"{value:,}")
        row_y -= 36


def draw_device_table(c: canvas.Canvas, x: float, y: float, w: float, h: float) -> None:
    round_rect(c, x, y, w, h)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(x + 14, y + h - 22, "Conversion by device")
    c.setFont("ReportSans", 7.2)
    set_fill(c, MUTED)
    c.drawString(x + 14, y + h - 35, "Positive point estimates across exposure devices")

    col_x = [x + 14, x + 86, x + 139, x + w - 13]
    header_y = y + h - 58
    headers = ["Device", "Control", "Treatment", "Delta"]
    c.setFont("ReportSans-Bold", 6.8)
    set_fill(c, MUTED)
    c.drawString(col_x[0], header_y, headers[0])
    for cx, header in zip(col_x[1:], headers[1:]):
        c.drawRightString(cx, header_y, header)
    c.setStrokeColor(LINE)
    c.line(x + 14, header_y - 7, x + w - 14, header_y - 7)

    rows = [
        ("Desktop", "27.99%", "29.66%", "+1.67 pp"),
        ("Mobile", "27.03%", "29.49%", "+2.46 pp"),
        ("Tablet", "28.48%", "30.72%", "+2.24 pp"),
    ]
    row_y = header_y - 25
    for device, control, treatment, delta in rows:
        c.setFont("ReportSans", 7.3)
        set_fill(c, SLATE)
        c.drawString(col_x[0], row_y, device)
        c.drawRightString(col_x[1], row_y, control)
        c.setFont("ReportSans-Bold", 7.3)
        set_fill(c, TREATMENT_DARK)
        c.drawRightString(col_x[2], row_y, treatment)
        set_fill(c, GREEN)
        c.drawRightString(col_x[3], row_y, delta)
        row_y -= 25

    c.setFont("ReportSans", 6.7)
    set_fill(c, MUTED)
    c.drawString(x + 14, y + 12, "Descriptive consistency; not proof of device heterogeneity.")


def draw_page_one(c: canvas.Canvas) -> None:
    draw_report_header(
        c,
        "Product experiment | Business report",
        "Checkout Simplification A/B Test",
        "Existing multi-step checkout vs. simplified single-page flow | July 1-14, 2026 | 24-hour purchase attribution",
    )

    round_rect(c, MARGIN, 602, PAGE_W - 2 * MARGIN, 94, fill=BLUE_BG, stroke=HexColor("#B8D0FF"))
    c.setFont("ReportSans-Bold", 7.4)
    set_fill(c, TREATMENT_DARK)
    c.drawString(MARGIN + 14, 678, "EXECUTIVE SUMMARY")
    c.setFont("ReportSans-Bold", 12.2)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 14, 653, "Conversion improved, but full-launch safety is not yet established.")
    summary = (
        "Treatment increased 24-hour purchase conversion by 2.16 percentage points and raised retained revenue per exposed "
        "user. The primary effect is statistically significant; however, uncertainty around checkout error and refund/cancellation "
        "still permits practically relevant harm. Recommendation: continue controlled testing before a full launch."
    )
    draw_wrapped(c, summary, MARGIN + 14, 632, PAGE_W - 2 * MARGIN - 28, size=8.2, leading=11.2)

    gap = 8
    card_w = (PAGE_W - 2 * MARGIN - 3 * gap) / 4
    card_y = 510
    draw_kpi_card(c, MARGIN, card_y, card_w, "Mature exposed users", "15,467", "7,754 Control | 7,713 Treatment")
    draw_kpi_card(c, MARGIN + card_w + gap, card_y, card_w, "Purchase conversion", "27.47%  >  29.63%", "Control to Treatment", value_color=TREATMENT_DARK, value_size=10.4)
    draw_kpi_card(c, MARGIN + 2 * (card_w + gap), card_y, card_w, "Absolute effect", "+2.16 pp", "+7.85% relative lift", value_color=TREATMENT_DARK)
    draw_kpi_card(c, MARGIN + 3 * (card_w + gap), card_y, card_w, "Statistical evidence", "p = 0.0030", "95% CI: +0.73 to +3.58 pp", value_size=15)

    round_rect(c, MARGIN, 400, 344, 96)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 14, 476, "Experiment context and hypothesis")
    context = (
        "The product team tested whether a single-page checkout increases completed purchases without materially worsening "
        "payment reliability, technical stability, order quality, or customer value. The two-sided primary hypothesis compared "
        "24-hour purchase conversion between persistent user-level assignments."
    )
    draw_wrapped(c, context, MARGIN + 14, 458, 316, size=7.8, leading=10.7)

    round_rect(c, 392, 400, 184, 96)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(406, 476, "Population and metric")
    draw_bullets(
        c,
        [
            "Eligible users with first valid checkout exposure and a complete 24-hour window",
            "One row per mature exposed user",
            "Purchase after qualifying payment attempt and within 24 hours",
        ],
        406,
        457,
        154,
        size=7.2,
        leading=9.3,
        gap=2.2,
    )

    c.setFont("ReportSans-Bold", 8)
    set_fill(c, TREATMENT_DARK)
    c.drawString(MARGIN, 379, "SUPPORTING EVIDENCE")
    draw_funnel(c, MARGIN, 202, 304, 165)
    draw_device_table(c, 352, 202, 224, 165)

    round_rect(c, MARGIN, 52, PAGE_W - 2 * MARGIN, 134)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 14, 166, "What the primary result supports")
    interpretation = (
        "The randomized comparison estimates a +2.16 pp average effect among mature exposed users under the defined eligibility "
        "and attribution rules. Funnel progression strengthens at payment attempt and purchase, and device-level point estimates "
        "are positive in all three reported categories. The 95% interval excludes zero, supporting a real positive effect in this "
        "simulated experiment."
    )
    draw_wrapped(c, interpretation, MARGIN + 14, 148, PAGE_W - 2 * MARGIN - 28, size=8.0, leading=10.8)
    c.setStrokeColor(LINE)
    c.line(MARGIN + 14, 101, PAGE_W - MARGIN - 14, 101)
    c.setFont("ReportSans-Bold", 7.5)
    set_fill(c, AMBER)
    c.drawString(MARGIN + 14, 87, "DECISION CAVEAT")
    caveat = (
        "Primary-metric significance does not establish guardrail safety, and the conversion interval still includes effects below "
        "the +1.0 pp business threshold."
    )
    draw_wrapped(c, caveat, MARGIN + 99, 87, PAGE_W - 2 * MARGIN - 113, size=7.5, leading=9.6)
    draw_footer(c, 1)


def draw_revenue_panel(c: canvas.Canvas, x: float, y: float, w: float, h: float) -> None:
    round_rect(c, x, y, w, h)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(x + 14, y + h - 22, "Retained revenue")
    c.setFont("ReportSans", 7.2)
    set_fill(c, MUTED)
    c.drawString(x + 14, y + h - 35, "Per mature exposed user")

    base_y = y + 43
    max_h = 72
    bar_w = 43
    values = [("Control", 24.52, CONTROL), ("Treatment", 26.33, TREATMENT)]
    positions = [x + 37, x + 101]
    for (label, value, color), bar_x in zip(values, positions):
        bar_h = max_h * value / 30
        c.setFillColor(color)
        c.roundRect(bar_x, base_y, bar_w, bar_h, 3, fill=1, stroke=0)
        c.setFont("ReportSans-Bold", 8)
        set_fill(c, SLATE)
        c.drawCentredString(bar_x + bar_w / 2, base_y + bar_h + 7, f"${value:.2f}")
        c.setFont("ReportSans", 7)
        c.drawCentredString(bar_x + bar_w / 2, base_y - 13, label)
    c.setFont("ReportSans-Bold", 6.7)
    set_fill(c, GREEN)
    c.drawCentredString(x + w / 2, y + 16, "+$1.81 per user (+7.40%)")
    c.drawCentredString(x + w / 2, y + 6, "95% CI: +$0.30 to +$3.33")


def draw_guardrail_panel(c: canvas.Canvas, x: float, y: float, w: float, h: float) -> None:
    round_rect(c, x, y, w, h)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(x + 14, y + h - 22, "Guardrail comparison")
    c.setFont("ReportSans", 7.2)
    set_fill(c, MUTED)
    c.drawString(x + 14, y + h - 35, "Metric-specific denominators; Treatment minus Control")

    columns = [x + 14, x + 150, x + 201, x + 252, x + w - 14]
    header_y = y + h - 57
    headers = ["Metric", "Control", "Treatment", "Delta", "95% CI"]
    c.setFont("ReportSans-Bold", 6.7)
    set_fill(c, MUTED)
    c.drawString(columns[0], header_y, headers[0])
    for cx, header in zip(columns[1:], headers[1:]):
        c.drawRightString(cx, header_y, header)
    c.setStrokeColor(LINE)
    c.line(x + 14, header_y - 7, x + w - 14, header_y - 7)

    rows = [
        ("Payment failure", "5.36%", "5.13%", "-0.23 pp", "Not reported", GREEN),
        ("Checkout error", "3.07%", "3.49%", "+0.42 pp", "-0.14 to +0.98 pp", AMBER),
        ("Refund / cancellation", "5.68%", "6.48%", "+0.80 pp", "-0.61 to +2.21 pp", AMBER),
    ]
    row_y = header_y - 26
    for metric, control, treatment, delta, interval, signal in rows:
        c.setFont("ReportSans", 7.0)
        set_fill(c, SLATE)
        c.drawString(columns[0], row_y, metric)
        c.drawRightString(columns[1], row_y, control)
        c.setFont("ReportSans-Bold", 7.0)
        set_fill(c, TREATMENT_DARK)
        c.drawRightString(columns[2], row_y, treatment)
        set_fill(c, signal)
        c.drawRightString(columns[3], row_y, delta)
        c.setFont("ReportSans", 6.6)
        set_fill(c, SLATE)
        c.drawRightString(columns[4], row_y, interval)
        row_y -= 27

    c.setFont("ReportSans", 6.2)
    set_fill(c, MUTED)
    c.drawString(x + 14, y + 6, "Non-significance is not evidence of equivalence or acceptable risk.")


def draw_numbered_step(
    c: canvas.Canvas,
    number: int,
    title: str,
    body: str,
    x: float,
    y: float,
    width: float,
) -> None:
    c.setFillColor(TREATMENT)
    c.circle(x + 11, y - 2, 10, fill=1, stroke=0)
    c.setFont("ReportSans-Bold", 8)
    c.setFillColor(PANEL)
    c.drawCentredString(x + 11, y - 5, str(number))
    c.setFont("ReportSans-Bold", 8.3)
    set_fill(c, NAVY)
    c.drawString(x + 30, y + 3, title)
    draw_wrapped(c, body, x + 30, y - 10, width - 30, size=7.2, leading=9.3, max_lines=2)


def draw_page_two(c: canvas.Canvas) -> None:
    draw_report_header(
        c,
        "Decision and next step",
        "Evidence Synthesis and Launch Recommendation",
        "Primary success is promising; commercial value is higher; guardrail uncertainty remains decision-relevant.",
        title_size=18,
    )

    c.setFont("ReportSans-Bold", 8)
    set_fill(c, TREATMENT_DARK)
    c.drawString(MARGIN, 690, "COMMERCIAL SIGNAL AND RISK TRADE-OFFS")
    draw_revenue_panel(c, MARGIN, 520, 182, 156)
    draw_guardrail_panel(c, 230, 520, 346, 156)

    round_rect(c, MARGIN, 410, PAGE_W - 2 * MARGIN, 96, fill=AMBER_BG, stroke=HexColor("#F3CD74"))
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 14, 486, "Why a statistically significant conversion win is not enough")
    draw_bullets(
        c,
        [
            "The p-value tests equality of purchase conversion; it does not test whether every guardrail is acceptably safe.",
            "Checkout-error and refund/cancellation intervals include increases that could be practically meaningful.",
            "No non-inferiority margins were pre-specified, so non-significant guardrail results cannot prove equivalence.",
        ],
        MARGIN + 14,
        466,
        PAGE_W - 2 * MARGIN - 28,
        size=7.6,
        leading=9.5,
        gap=2.3,
    )

    round_rect(c, MARGIN, 304, PAGE_W - 2 * MARGIN, 92, fill=BLUE_BG, stroke=HexColor("#B8D0FF"))
    c.setFont("ReportSans-Bold", 7.4)
    set_fill(c, TREATMENT_DARK)
    c.drawString(MARGIN + 14, 378, "PRODUCT RECOMMENDATION")
    c.setFont("ReportSans-Bold", 17)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 14, 352, "Need more data before full launch")
    recommendation = (
        "Keep the simplified checkout as the leading candidate and continue controlled exposure in a confirmatory extension. "
        "Do not target a specific segment: no user-type, device, or traffic-source dimension showed confirmed heterogeneity after correction."
    )
    draw_wrapped(c, recommendation, MARGIN + 14, 333, PAGE_W - 2 * MARGIN - 28, size=8.0, leading=10.8)

    round_rect(c, MARGIN, 126, PAGE_W - 2 * MARGIN, 164)
    c.setFont("ReportSans-Bold", 10.5)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 14, 270, "Proposed confirmatory extension")
    c.setFont("ReportSans", 7.3)
    set_fill(c, MUTED)
    c.drawString(MARGIN + 14, 256, "Additional evidence required before a full-launch decision")

    half = (PAGE_W - 2 * MARGIN - 42) / 2
    draw_numbered_step(
        c,
        1,
        "Define safety margins",
        "Pre-specify acceptable harm limits for checkout error and refund/cancellation.",
        MARGIN + 14,
        230,
        half,
    )
    draw_numbered_step(
        c,
        2,
        "Power for guardrail precision",
        "Size the extension to evaluate those margins, not only the conversion effect.",
        MARGIN + 28 + half,
        230,
        half,
    )
    draw_numbered_step(
        c,
        3,
        "Preserve outcome windows",
        "Maintain 24-hour purchase attribution and complete seven-day order follow-up.",
        MARGIN + 14,
        181,
        half,
    )
    draw_numbered_step(
        c,
        4,
        "Pre-commit the launch gate",
        "Require conversion support plus guardrail intervals that exclude the agreed harm margins.",
        MARGIN + 28 + half,
        181,
        half,
    )
    c.setStrokeColor(LINE)
    c.line(MARGIN + 14, 151, PAGE_W - MARGIN - 14, 151)
    c.setFont("ReportSans-Bold", 7.3)
    set_fill(c, GREEN)
    monitor_label = "CONTINUE TO MONITOR"
    monitor_x = MARGIN + 14
    c.drawString(monitor_x, 137, monitor_label)
    c.setFont("ReportSans", 7.3)
    set_fill(c, SLATE)
    body_x = monitor_x + text_width(monitor_label, "ReportSans-Bold", 7.3) + 12
    c.drawString(body_x, 137, "Retained revenue, payment reliability, telemetry quality, interference, and sequential peeking.")

    round_rect(c, MARGIN, 49, PAGE_W - 2 * MARGIN, 63, fill=SOFT_GRAY, stroke=LINE)
    c.setFont("ReportSans-Bold", 8)
    set_fill(c, NAVY)
    c.drawString(MARGIN + 12, 94, "Interpretation boundaries")
    limits = (
        "Simulated data; exposed-user estimand rather than all assigned users; segment analyses are exploratory; completion time is "
        "conditioned on purchase. A live test would require production telemetry and operational monitoring."
    )
    draw_wrapped(c, limits, MARGIN + 12, 79, PAGE_W - 2 * MARGIN - 24, size=7.2, leading=9.2)
    draw_footer(c, 2)


def build_report(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(output_path), pagesize=letter, pageCompression=1)
    c.setTitle("Checkout A/B Testing Business Report")
    c.setAuthor("Yucheng Gao")
    c.setSubject("Product experiment business decision report")
    draw_page_one(c)
    c.showPage()
    draw_page_two(c)
    c.showPage()
    c.save()


def parse_args() -> argparse.Namespace:
    default_output = Path(__file__).resolve().parent / "checkout_ab_test_business_report.pdf"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=default_output)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    build_report(arguments.output.resolve())
    print(f"Wrote {arguments.output.resolve()}")
