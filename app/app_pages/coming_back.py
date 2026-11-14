import altair as alt
import pandas as pd
import streamlit as st

from olist_app import data, style

tables = data.load()["tables"]
experience = tables["repeat_by_experience"].set_index("grp")
quarters = tables["repeat_by_quarter"].copy()

LATE = "Late"
BAD_REVIEW = "On time, reviewed 1-2 stars"
FINE = "On time, 3+ stars or no review"
SEGMENT = "Campaign segment (late or 1-2 stars)"
ALL = "All first-time buyers"

cohort_size = int(experience.loc[ALL, "people"])

st.title("Customers whose first order went wrong come back less often")
st.caption(
    f"{cohort_size:,} people whose first order was delivered with at least 180 days of data after it, so everyone had the same time to "
    "come back. Came back means a later non-canceled order, placed on or after the delivery day, within the window you choose."
)

# --- By first-order experience -------------------------------------------------------------------------------------------
WINDOWS = {"8 weeks": "repeat_56d_pct", "90 days": "repeat_90d_pct", "6 months": "repeat_180d_pct"}
window = st.segmented_control("Window after the first delivery", list(WINDOWS), default="6 months", key="window") or "6 months"
column = WINDOWS[window]

rows = [LATE, BAD_REVIEW, FINE, SEGMENT, ALL]
frame = experience.loc[rows, ["people", column]].reset_index()
frame["rate"] = frame[column]
frame["kind"] = frame["grp"].map({LATE: "Late", BAD_REVIEW: "On time, reviewed 1–2 stars", FINE: "On time, 3+ stars or no review", SEGMENT: "Combined", ALL: "Combined"})
frame["label"] = frame["rate"].map(lambda v: f"{v:.2f}%")

kind_domain = ["Late", "On time, reviewed 1–2 stars", "On time, 3+ stars or no review", "Combined"]
kind_range = [style.CRIMSON, style.AMBER, style.BLUE, style.MUTED_BAR]

base = alt.Chart(frame).encode(
    y=alt.Y("grp:N", sort=rows, title=None, axis=alt.Axis(labelLimit=280)),
    x=alt.X("rate:Q", title=f"Repeat order within {window} (% of people)", scale=alt.Scale(domain=[0, max(2.0, frame['rate'].max() * 1.2)]), axis=alt.Axis(tickMinStep=0.5, format='.1f')),
    color=alt.Color("kind:N", scale=alt.Scale(domain=kind_domain, range=kind_range), legend=None),
    tooltip=[
        alt.Tooltip("grp:N", title="First order"),
        alt.Tooltip("people:Q", title="People", format=","),
        alt.Tooltip("rate:Q", title=f"Repeat within {window} (%)", format=".2f"),
    ],
)
chart = (
    base.mark_bar(size=24) + base.mark_text(align="left", dx=6, fontSize=13).encode(text="label:N", color=alt.value("#1B2430"))
).properties(height=230, padding=dict(left=40, right=8, top=5, bottom=5))

late_rate = frame.loc[frame["grp"] == LATE, "rate"].iloc[0]
fine_rate = frame.loc[frame["grp"] == FINE, "rate"].iloc[0]
st.altair_chart(
    chart,
    alt=f"Share of first-time buyers who ordered again within {window}, by first-order experience: {late_rate:.2f}% when the "
    f"first order was late, against {fine_rate:.2f}% when it went fine.",
)
st.caption(
    f"Within {window}, late first orders lead to a repeat order {late_rate:.2f}% of the time against {fine_rate:.2f}% when the first "
    "order went fine. Late and low-rated are drawn in their own colours; the grey rows combine groups."
)

st.info(
    "Late deliveries cluster in states whose customers may differ in other ways, and a bad review can reflect a bad product as much "
    "as a bad delivery. Only a randomised test can show that fixing the experience changes what people do.",
    title="This shows an association, not a cause",
    icon=":material/info:",
)

# --- By quarter ----------------------------------------------------------------------------------------------------------
st.subheader("Is it just when people joined?")
st.caption(
    "Six-month repeat rate for on-time and late first orders, by the quarter of the first delivery. If the late line sits below the "
    "on-time line in each large quarter, the gap is not explained by timing. The size of each dot is the number of people behind it."
)

long = pd.concat(
    [
        quarters.assign(group="On time or early", rate=quarters["on_time_repeat_pct"], people=quarters["on_time_people"]),
        quarters.assign(group="Late", rate=quarters["late_repeat_pct"], people=quarters["late_people"]),
    ]
)
quarter_order = quarters.sort_values("delivery_quarter")["delivery_quarter"].tolist()
color = alt.Color(
    "group:N", scale=alt.Scale(domain=style.ARRIVAL_DOMAIN, range=style.ARRIVAL_RANGE), legend=alt.Legend(title=None, orient="top")
)
lines = alt.Chart(long).mark_line(strokeWidth=2.5).encode(
    x=alt.X("delivery_quarter:N", sort=quarter_order, title="Quarter of the first delivery", axis=alt.Axis(labelAngle=0)),
    y=alt.Y("rate:Q", title="Repeat within 6 months (%)", scale=alt.Scale(zero=True)),
    color=color,
)
points = alt.Chart(long).mark_circle(opacity=1).encode(
    x=alt.X("delivery_quarter:N", sort=quarter_order),
    y="rate:Q",
    color=color,
    size=alt.Size("people:Q", scale=alt.Scale(range=[40, 600]), legend=None),
    tooltip=[
        alt.Tooltip("delivery_quarter:N", title="Quarter"),
        alt.Tooltip("group:N", title="First order"),
        alt.Tooltip("rate:Q", title="Repeat within 6 months (%)", format=".2f"),
        alt.Tooltip("people:Q", title="People", format=","),
    ],
)
st.altair_chart(
    (lines + points).properties(height=300),
    alt="Six-month repeat rate by quarter of first delivery, for on-time and late first orders. Late orders sit below on-time ones "
    "in every quarter from 2017-Q2 onward; the two earliest quarters have very few late orders.",
)
thin = quarters[quarters["late_people"] < 300]["delivery_quarter"].tolist()
if thin:
    st.caption(f"{', '.join(thin)} have fewer than 300 late people, so their points are noisy.")
