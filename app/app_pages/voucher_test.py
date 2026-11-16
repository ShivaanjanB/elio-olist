import altair as alt
import pandas as pd
import streamlit as st

from olist_app import calculator, data, style

bundle = data.load()
campaign = bundle["campaign"]
freights = bundle["freights"]
measured_segment = int(campaign["segment_per_year"])
baseline = float(campaign["baseline_56d"])
avg_items_price = float(campaign["avg_items_price"])

PRESETS = {"Low": 0.25, "Base": 0.50, "High": 1.00}


def apply_preset() -> None:
    chosen = st.session_state.get("preset")
    if chosen in PRESETS:
        st.session_state["uplift"] = PRESETS[chosen]


st.title("What a voucher test could earn, and what it could see")
st.caption(
    "Everything here is item revenue before costs. The data has no margin, so enter yours. The uplift is an assumption: nothing in the "
    "data says what a voucher does, and finding that out is the point of the test."
)

# --- Assumptions
# --------------------------------------------------------------------------------------------------------- Two
# columns of controls across the top (the voucher on the left, your business on the right), so the results below get
# the full width.
st.subheader("Assumptions")
effect_col, people_col = st.columns(2, gap="large")
with effect_col:
    st.segmented_control(
        "Start from a scenario",
        list(PRESETS),
        key="preset",
        on_change=apply_preset,
        help="Low is an apology that only restores normal behaviour (the gap to everyone else). Base and high are bigger assumed effects.",
    )
    uplift_points = st.slider(
        "Extra repeat orders within 8 weeks (percentage points)",
        0.10,
        2.00,
        0.50,
        0.05,
        format="%.2f",
        key="uplift",
        bind="query-params",
        help=f"Today {baseline:.2%} of this segment order again within 8 weeks. This is how much higher the voucher lifts that.",
    )
    cap = st.slider(
        "Voucher cap (reais of free shipping)",
        5,
        30,
        15,
        1,
        key="cap",
        bind="query-params",
        help="The median freight on a later order is about R$17. A lower cap costs less per use.",
    )
with people_col:
    segment = st.number_input(
        "People in the segment per year",
        min_value=1000,
        max_value=100000,
        value=measured_segment,
        step=100,
        key="segment",
        help=f"Measured: {measured_segment:,} first-time buyers a year whose first order was late or reviewed 1–2 stars.",
    )
    margin_points = st.slider(
        "Your margin on an extra order (% of item revenue)",
        0,
        60,
        20,
        1,
        key="margin",
        bind="query-params",
        help="The dataset has no margin. This is a placeholder for yours.",
    )
    months = st.segmented_control(
        "Months of enrolment",
        [3, 6, 12],
        default=12,
        format_func=str,
        key="months",
        help="How long people are enrolled in the test, in months. Longer means more people in each group.",
    ) or 12

avg_voucher_cost = calculator.voucher_cost(freights, cap)
uplift = uplift_points / 100
margin = margin_points / 100
outcome = calculator.outcome(segment, baseline, uplift, avg_items_price, avg_voucher_cost)
profit = outcome.profit_at(margin)

# --- What it earns and costs ---------------------------------------------------------------------------------------------
st.subheader("What a year of vouchers does")
st.markdown(
    f"At **+{uplift_points:.2f} points**, vouchers bring about **{outcome.extra_orders:,.0f} extra orders** and "
    f"R${outcome.extra_revenue:,.0f} of item revenue, and cost R${outcome.voucher_cost:,.0f}. "
    f"Each extra order costs R${outcome.cost_per_extra_order:,.0f} in vouchers, because everyone who would have ordered anyway "
    "uses the voucher too."
)

first, second, third = st.columns(3)
first.metric("Revenue less voucher cost", f"R${outcome.revenue_less_voucher_cost:,.0f}")
pays = profit >= 0
second.metric(
    "Profit at your margin",
    f"R${profit:,.0f}",
    delta="pays for itself" if pays else "loses money",
    delta_color="green" if pays else "red",
    delta_arrow="up" if pays else "down",
)
margin_gap = (margin - outcome.break_even_margin) * 100
third.metric(
    "Break-even margin",
    f"{outcome.break_even_margin:.0%}",
    delta=f"yours is {abs(margin_gap):.0f} pts {'above' if margin_gap >= 0 else 'below'}",
    delta_color="green" if margin_gap >= 0 else "red",
    delta_arrow="up" if margin_gap >= 0 else "down",
    help="The margin on an extra order at which the voucher pays for itself.",
)

grid = pd.DataFrame({"uplift_points": [round(0.10 + 0.05 * k, 2) for k in range(0, 39)]})
curve = []
for points in grid["uplift_points"]:
    scenario = calculator.outcome(segment, baseline, points / 100, avg_items_price, avg_voucher_cost)
    curve.append((points, "Revenue less voucher cost", scenario.revenue_less_voucher_cost))
    curve.append((points, "Profit at your margin", scenario.profit_at(margin)))
curve = pd.DataFrame(curve, columns=["uplift_points", "series", "value"])
here = pd.DataFrame(
    [(uplift_points, "Revenue less voucher cost", outcome.revenue_less_voucher_cost), (uplift_points, "Profit at your margin", profit)],
    columns=["uplift_points", "series", "value"],
)
series_color = alt.Color(
    "series:N",
    scale=alt.Scale(domain=["Revenue less voucher cost", "Profit at your margin"], range=[style.BLUE, style.AMBER]),
    legend=alt.Legend(title=None, orient="top", direction="vertical", labelLimit=320),
)
lines = alt.Chart(curve).mark_line(strokeWidth=2.5).encode(
    x=alt.X("uplift_points:Q", title="Extra repeat orders (percentage points)", axis=alt.Axis(tickMinStep=0.25, format=".2f")),
    y=alt.Y("value:Q", title="Reais a year", axis=alt.Axis(format=",.0f")),
    color=series_color,
    tooltip=[
        alt.Tooltip("uplift_points:Q", title="Uplift (points)", format=".2f"),
        alt.Tooltip("series:N", title=""),
        alt.Tooltip("value:Q", title="Reais a year", format=",.0f"),
    ],
)
dots = alt.Chart(here).mark_circle(size=130, opacity=1).encode(x="uplift_points:Q", y="value:Q", color=series_color)
zero = alt.Chart(pd.DataFrame({"y": [0]})).mark_rule(color=style.MUTED_BAR, strokeDash=[4, 4]).encode(y="y:Q")
scenario_frame = pd.DataFrame({"x": list(PRESETS.values()), "name": list(PRESETS)})
scenario_ticks = alt.Chart(scenario_frame).mark_rule(color=style.MUTED_BAR, opacity=0.6).encode(x="x:Q")
scenario_names = alt.Chart(scenario_frame).mark_text(dy=-6, fontSize=11, color="#5B6675", baseline="bottom", align="center").encode(
    x="x:Q", text="name:N", y=alt.value(12)
)
st.altair_chart(
    (scenario_ticks + zero + lines + dots + scenario_names).properties(height=300),
    alt=f"Yearly revenue less voucher cost and profit at a {margin_points}% margin, by how much the voucher lifts repeat orders. "
    f"At +{uplift_points:.2f} points the voucher earns R${outcome.revenue_less_voucher_cost:,.0f} less voucher cost, "
    f"or R${profit:,.0f} at your margin.",
)

# --- What the test could see ---------------------------------------------------------------------------------------------
st.subheader("Could a test see this?")
needed = outcome.people_per_group_needed
available = calculator.people_per_group_available(segment, months)
can_see = needed <= available

if can_see:
    st.badge("Detectable", icon=":material/check:", color="green")
else:
    st.badge("Too small to see", icon=":material/close:", color="red")
st.markdown(
    f"To see +{uplift_points:.2f} points with 80% power at the 5% level, each group needs **{needed:,} people**. "
    f"{months} months of enrolment, split 50/50, gives **{available:,.0f}** per group. "
    + (
        "That is enough."
        if can_see
        else "That is not enough, so a result of no effect would only mean there is none larger than the smallest effect in the table."
    )
)
st.caption(
    f"Test spend at risk: about R${outcome.test_spend_at_risk:,.0f}, the treated half's voucher cost if the voucher works this well. "
    "Vouchers cost money only when used."
)


def smallest_visible(months_enrolled: int):
    smallest = calculator.smallest_detectable_uplift(baseline, calculator.people_per_group_available(segment, months_enrolled))
    return None if smallest is None else smallest * 100


detect = pd.DataFrame(
    {
        "Months": [3, 6, 12],
        "Per group": [round(calculator.people_per_group_available(segment, m)) for m in (3, 6, 12)],
        "Smallest uplift (pts)": [smallest_visible(m) for m in (3, 6, 12)],
    }
)
st.dataframe(
    detect,
    hide_index=True,
    alt="The smallest uplift a voucher test could detect after 3, 6 and 12 months of enrolment",
    column_config={
        "Per group": st.column_config.NumberColumn("People per group", format="localized"),
        "Smallest uplift (pts)": st.column_config.NumberColumn("Smallest uplift (pts)", format="%.2f", help="The smallest lift in repeat orders, in percentage points, that this much enrolment could detect."),
    },
)
