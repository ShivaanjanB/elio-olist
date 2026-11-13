{#
  Golden numbers: the headline figures of this dataset, worked out independently from the RAW files before the marts
  existed (docs/relationship_checks.sql and docs/type_and_design_checks.sql) and pinned here. If a model change moves
  one of them, the build fails and someone has to decide whether the change or the number is wrong (D45).

  This is a regression guard for a STATIC dataset: the Olist export never changes. On a live source these values would
  move every day and this test would not belong.

  Returns one row per figure that differs; the test passes when nothing is returned.
#}
with actual as (

    select 'revenue (items price, revenue orders)' as measure,
           (select sum(price) from {{ ref('fct_order_items') }} where is_revenue_order) as value
    union all
    select 'revenue orders',
           (select count(*) from {{ ref('fct_orders') }} where is_revenue_order)
    union all
    select 'orders with a measurable delivery',
           (select count(delivered_date) from {{ ref('fct_orders') }})
    union all
    select 'late orders (date grain)',
           (select count_if(is_late) from {{ ref('fct_orders') }})
    union all
    select 'people',
           (select count(*) from {{ ref('dim_customer') }})
    union all
    select 'people who ordered more than once',
           (select count_if(has_multiple_orders) from {{ ref('dim_customer') }})
    union all
    select 'people whose first order is canceled or unavailable',
           (select count(*)
            from {{ ref('dim_customer') }} as customers
            inner join {{ ref('fct_orders') }} as orders on orders.order_id = customers.first_order_id
            where not orders.is_revenue_order)
    union all
    select 'people with a delivered first order',
           (select count_if(repeat_after_first_delivery is not null) from {{ ref('dim_customer') }})
    union all
    select 'of them, who ordered again after the delivery',
           (select count_if(repeat_after_first_delivery) from {{ ref('dim_customer') }})
    union all
    select 'orders with no items',
           (select count_if(item_count = 0) from {{ ref('fct_orders') }})
    union all
    select 'orders with no review',
           (select count_if(review_count = 0) from {{ ref('fct_orders') }})

),

expected as (

    select 'revenue (items price, revenue orders)' as measure, 13494400.74 as value
    union all select 'revenue orders', 98207
    union all select 'orders with a measurable delivery', 96470
    union all select 'late orders (date grain)', 6534
    union all select 'people', 96096
    union all select 'people who ordered more than once', 2997
    union all select 'people whose first order is canceled or unavailable', 1153
    union all select 'people with a delivered first order', 93248
    union all select 'of them, who ordered again after the delivery', 1813
    union all select 'orders with no items', 775
    union all select 'orders with no review', 768

)

select
    expected.measure,
    actual.value   as actual_value,
    expected.value as expected_value
from expected
left join actual on actual.measure = expected.measure
where actual.value is distinct from expected.value
