"""The economics of the voucher test, as plain functions with no Streamlit in them."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Sequence

Z_ALPHA = 1.96    # 5% significance level, two-sided
Z_POWER = 0.8416  # 80% power


def voucher_cost(freights: Sequence[float], cap: float) -> float:
    """Average cost of one redeemed voucher: free shipping, capped at `cap`, over the freight of later orders."""
    if not freights:
        raise ValueError("no freight values to average")
    return sum(min(f, cap) for f in freights) / len(freights)


def people_per_group_needed(baseline: float, uplift: float) -> int:
    """People needed in each group to see `uplift` over `baseline` with 80% power at the 5% level (two-sided)."""
    if uplift <= 0:
        raise ValueError("uplift must be positive")
    treated = baseline + uplift
    if not 0 <= baseline < 1 or treated >= 1:
        raise ValueError("rates must stay below 100%")
    needed = (Z_ALPHA + Z_POWER) ** 2 * (baseline * (1 - baseline) + treated * (1 - treated)) / uplift**2
    return math.ceil(needed)


def smallest_detectable_uplift(baseline: float, people_per_group: float, step: float = 0.0001, ceiling: float = 0.03) -> float | None:
    """The smallest uplift, in steps of 0.01 points up to 3 points, that `people_per_group` can detect. None if none."""
    for k in range(1, int(round(ceiling / step)) + 1):
        uplift = k * step
        if people_per_group_needed(baseline, uplift) <= people_per_group:
            return round(uplift, 6)
    return None


@dataclass(frozen=True)
class Outcome:
    """What one voucher scenario earns and costs over a year, if rolled out to the whole segment."""

    uplift: float
    extra_orders: float
    extra_revenue: float          # item revenue on the extra orders, not profit
    redemptions: float            # everyone who orders within the window uses the voucher, baseline buyers included
    voucher_cost: float
    revenue_less_voucher_cost: float
    cost_per_extra_order: float
    break_even_margin: float      # the margin on an extra order at which the voucher pays for itself
    test_spend_at_risk: float     # the treated half's voucher cost, if a test ran at this scenario
    people_per_group_needed: int

    def profit_at(self, margin: float) -> float:
        """Profit on the extra orders at a given margin (a fraction of item revenue), after the voucher cost."""
        return self.extra_revenue * margin - self.voucher_cost


def outcome(segment_per_year: float, baseline: float, uplift: float, avg_items_price: float, avg_voucher_cost: float) -> Outcome:
    extra_orders = segment_per_year * uplift
    extra_revenue = extra_orders * avg_items_price
    redemptions = segment_per_year * (baseline + uplift)
    cost = redemptions * avg_voucher_cost
    cost_per_extra = cost / extra_orders
    return Outcome(
        uplift=uplift,
        extra_orders=extra_orders,
        extra_revenue=extra_revenue,
        redemptions=redemptions,
        voucher_cost=cost,
        revenue_less_voucher_cost=extra_revenue - cost,
        cost_per_extra_order=cost_per_extra,
        break_even_margin=cost_per_extra / avg_items_price,
        test_spend_at_risk=0.5 * cost,
        people_per_group_needed=people_per_group_needed(baseline, uplift),
    )


def people_per_group_available(segment_per_year: float, months: float) -> float:
    """People per group when `months` of enrolment are split 50/50."""
    return segment_per_year * months / 12 / 2
