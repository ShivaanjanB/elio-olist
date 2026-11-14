import altair as alt
import pandas as pd
import streamlit as st

from olist_app import data, style

tables = data.load()["tables"]
summary = tables["arrival_summary"].set_index("arrival")
late, on_time = summary.loc["late"], summary.loc["on time or early"]

st.title(f"Late orders average {late.avg_score:.2f} stars, on-time orders {on_time.avg_score:.2f}")
st.caption("Delivered orders that have a review. Late means delivered after the date the customer was promised.")

# --- How much a late order costs in reviews -----------------------------------------------------------------------------
st.subheader("How much a late order costs in reviews")

MEASURES = {
    "Average score": ("avg_score", "Average review score (1 to 5 stars)", ".2f", [0, 5]),  # bars start at zero so their length is honest
    "Share giving 1–2 stars": ("pct_1_2_stars", "Orders reviewed 1 or 2 stars (%)", ".0f", [0, 100]),
    "Share giving 5 stars": ("pct_5_stars", "Orders reviewed 5 stars (%)", ".0f", [0, 100]),
}
choice = (
    st.segmented_control("Measure", list(MEASURES), default="Average score", key="band_measure", label_visibility="collapsed")
    or "Average score"
)
column, axis_title, label_format, domain = MEASURES[choice]

bands = tables["arrival_bands"].copy()
bands["group"] = bands["sort_key"].map(lambda key: "Late" if key >= 3 else "On time or early")
band_order = bands.sort_values("sort_key")["arrival"].tolist()

base = alt.Chart(bands).encode(
    y=alt.Y("arrival:N", sort=band_order, title=None),
    x=alt.X(f"{column}:Q", title=axis_title, scale=alt.Scale(domain=domain), axis=alt.Axis(tickMinStep=1)),
    color=alt.Color(
        "group:N",
        scale=alt.Scale(domain=style.ARRIVAL_DOMAIN, range=style.ARRIVAL_RANGE),
        legend=alt.Legend(title=None, orient="top"),
    ),
    tooltip=[
        alt.Tooltip("arrival:N", title="Arrival"),
        alt.Tooltip("reviewed_orders:Q", title="Reviewed orders", format=","),
        alt.Tooltip("avg_score:Q", title="Average score", format=".2f"),
        alt.Tooltip("pct_1_2_stars:Q", title="Give 1–2 stars (%)", format=".1f"),
        alt.Tooltip("pct_5_stars:Q", title="Give 5 stars (%)", format=".1f"),
    ],
)
chart = (
    base.mark_bar(size=26)
    + base.mark_text(align="left", dx=6, fontSize=13).encode(text=alt.Text(f"{column}:Q", format=label_format), color=alt.value("#1B2430"))
).properties(height=250, padding=dict(left=24, right=8, top=5, bottom=5))

one_to_three = bands.loc[bands["arrival"] == "Late 1-3 days", "avg_score"].iloc[0]
st.altair_chart(
    chart,
    alt=f"{axis_title} by how early or late the order arrived. On-time orders average about {on_time.avg_score:.1f} stars; "
    f"one to three days late averages {one_to_three:.2f}, and a week or more late is under 2.",
)
st.caption("Early orders score about the same as orders that arrive on the day, so the damage comes from a broken promise, not from slowness.")

# --- Is it just geography? -----------------------------------------------------------------------------------------------
st.subheader("Is it just where the customer lives?")

by_state = tables["review_by_state"].copy()
by_state["gap"] = by_state["on_time_avg"] - by_state["late_avg"]
state_order = by_state.sort_values("gap", ascending=False)["state"].tolist()
st.caption(
    f"Late and on-time review averages inside each of the {len(by_state)} states with at least 100 late reviewed orders. "
    f"The gap is {by_state.gap.min():.1f} to {by_state.gap.max():.1f} stars in every one."
)

long = pd.concat(
    [
        by_state.assign(group="On time or early", avg=by_state["on_time_avg"], reviewed=by_state["on_time_reviewed"]),
        by_state.assign(group="Late", avg=by_state["late_avg"], reviewed=by_state["late_reviewed"]),
    ]
)
rules = alt.Chart(by_state).mark_rule(color=style.MUTED_BAR, strokeWidth=3).encode(
    y=alt.Y("state:N", sort=state_order, title=None), x=alt.X("late_avg:Q", scale=alt.Scale(domain=[1, 5])), x2="on_time_avg:Q"
)
dots = alt.Chart(long).mark_circle(size=150, opacity=1).encode(
    y=alt.Y("state:N", sort=state_order, title=None),
    x=alt.X("avg:Q", title="Average review score", scale=alt.Scale(domain=[1, 5]), axis=alt.Axis(tickMinStep=0.5, format=".1f")),
    color=alt.Color(
        "group:N",
        scale=alt.Scale(domain=style.ARRIVAL_DOMAIN, range=style.ARRIVAL_RANGE),
        legend=alt.Legend(title=None, orient="top"),
    ),
    tooltip=[
        alt.Tooltip("state:N", title="State"),
        alt.Tooltip("group:N", title="Arrival"),
        alt.Tooltip("avg:Q", title="Average score", format=".2f"),
        alt.Tooltip("reviewed:Q", title="Reviewed orders", format=","),
    ],
)
st.altair_chart(
    (rules + dots).properties(height=26 * len(by_state) + 50),
    alt=f"Late and on-time average review score in each of {len(by_state)} states. In every state late orders score "
    f"between {by_state.gap.min():.1f} and {by_state.gap.max():.1f} stars lower.",
)

# --- Where deliveries run late -------------------------------------------------------------------------------------------
st.subheader("Where deliveries run late")

STATE_MEASURES = {
    "Late deliveries": ("late_pct", "Delivered orders that arrived late (%)", lambda v: f"{v:.1f}%", False),
    "Days to deliver": ("avg_days_to_deliver", "Average days from purchase to delivery", lambda v: f"{v:.1f}", False),
    "Review score": ("avg_review_score", "Average review score", lambda v: f"{v:.2f}", True),
    "Freight ratio": ("freight_ratio", "Freight as a share of item price", lambda v: f"{v:.0%}", False),
}

measure = (
    st.segmented_control("Measure", list(STATE_MEASURES), default="Late deliveries", key="state_measure", label_visibility="collapsed")
    or "Late deliveries"
)
hide_small = st.toggle("Hide states with fewer than 100 delivered orders", value=True, key="hide_small")

column, axis_title, label_fn, low_is_worse = STATE_MEASURES[measure]
states = tables["states"].copy()
shown = states[states["enough_data"]] if hide_small else states
shown = shown.sort_values(column, ascending=low_is_worse).reset_index(drop=True)
shown["label"] = shown[column].map(label_fn)

chart_col, detail_col = st.columns([3, 2], gap="large")

pick = alt.selection_point(name="pick", fields=["state"])
state_base = alt.Chart(shown).encode(
    y=alt.Y("state:N", sort=shown["state"].tolist(), title=None),
    x=alt.X(f"{column}:Q", title=axis_title),
    tooltip=[
        alt.Tooltip("state:N", title="State"),
        alt.Tooltip("late_pct:Q", title="Late (%)", format=".1f"),
        alt.Tooltip("avg_days_to_deliver:Q", title="Days to deliver", format=".1f"),
        alt.Tooltip("avg_review_score:Q", title="Review score", format=".2f"),
        alt.Tooltip("freight_ratio:Q", title="Freight ratio", format=".0%"),
        alt.Tooltip("delivered_orders:Q", title="Delivered orders", format=","),
    ],
)
state_chart = (
    state_base.mark_bar(size=15)
    .add_params(pick)
    .encode(color=alt.condition(pick, alt.value(style.CRIMSON), alt.value(style.BLUE), empty=False))
    + state_base.mark_text(align="left", dx=5, fontSize=12).encode(text="label:N", color=alt.value("#1B2430"))
).properties(height=22 * len(shown) + 40)

with chart_col:
    event = st.altair_chart(
        state_chart,
        on_select="rerun",
        key="state_chart",
        alt=f"{axis_title} for {len(shown)} states, from {shown.iloc[0]['state']} to {shown.iloc[-1]['state']}. Select a bar for that state's numbers.",
    )

chosen = []
if "pick" in event.selection:
    known_states = set(states["state"])
    chosen = [item["state"] for item in event.selection["pick"] if item.get("state") in known_states]

with detail_col:
    if chosen:
        row = states[states["state"] == chosen[0]].iloc[0]
        gap_row = by_state[by_state["state"] == chosen[0]]
        st.subheader(f"State {row['state']}")
        first, second = st.columns(2)
        first.metric("Late deliveries", f"{row.late_pct:.1f}%")
        second.metric("Days to deliver", f"{row.avg_days_to_deliver:.1f}")
        first.metric("Review score", f"{row.avg_review_score:.2f}")
        second.metric("Freight ratio", f"{row.freight_ratio:.0%}")
        st.caption(f"{int(row.delivered_orders):,} delivered orders of {int(row.orders):,}. Revenue R${row.revenue:,.0f}.")
        if not gap_row.empty:
            g = gap_row.iloc[0]
            st.caption(f"Late orders here score {g.late_avg:.2f} against {g.on_time_avg:.2f} on time.")
        if not row.enough_data:
            st.caption("Fewer than 100 delivered orders, so read this one with care.")
    else:
        st.caption("Select a bar to see that state's numbers.")

with st.expander("Show the numbers", icon=":material/table_chart:"):
    st.dataframe(
        shown.drop(columns=["label"]),
        hide_index=True,
        alt="Delivery and review figures for each state shown in the chart",
        column_config={
            "state": "State",
            "orders": st.column_config.NumberColumn("Orders", format="localized"),
            "delivered_orders": st.column_config.NumberColumn("Delivered", format="localized"),
            "avg_days_to_deliver": st.column_config.NumberColumn("Days to deliver", format="%.1f"),
            "late_pct": st.column_config.NumberColumn("Late (%)", format="%.1f"),
            "avg_review_score": st.column_config.NumberColumn("Review score", format="%.2f"),
            "freight_ratio": st.column_config.NumberColumn("Freight ratio", format="percent"),
            "revenue": st.column_config.NumberColumn("Revenue (R$)", format="localized"),
            "enough_data": st.column_config.CheckboxColumn("100+ delivered"),
        },
    )
