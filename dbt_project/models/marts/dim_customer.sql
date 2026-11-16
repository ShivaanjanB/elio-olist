{#
  One row per PERSON (customer_unique_id), not per customer_id, which is new on every order (D12).
#}
with person_orders as (

    select
        customer_orders.customer_unique_id,
        customer_orders.order_id,
        customer_orders.order_number,
        customer_orders.customer_zip_code_prefix,
        customer_orders.customer_city,
        customer_orders.customer_state,
        orders.purchase_date,
        orders.delivered_date,
        orders.is_revenue_order
    from {{ ref('int_customer_orders') }} as customer_orders
    inner join {{ ref('fct_orders') }} as orders
        on orders.order_id = customer_orders.order_id

),

totals as (

    select
        customer_unique_id,
        count(*) as order_count
    from person_orders
    group by customer_unique_id

),

first_order as (

    select
        customer_unique_id,
        order_id                    as first_order_id,
        purchase_date               as first_order_date,
        delivered_date              as first_order_delivered_date,
        customer_zip_code_prefix    as first_order_zip_code_prefix,
        customer_city               as first_order_city,
        customer_state              as first_order_state
    from person_orders
    where order_number = 1

),

returned as (

    select distinct
        later.customer_unique_id
    from person_orders as later
    inner join first_order
        on first_order.customer_unique_id = later.customer_unique_id
    where later.order_number > 1
      and later.is_revenue_order
      and first_order.first_order_delivered_date is not null
      and later.purchase_date >= first_order.first_order_delivered_date

)

select
    cast({{ generate_surrogate_key(['first_order.customer_unique_id']) }} as varchar(32))   as customer_sk,
    cast(first_order.customer_unique_id as varchar(32))                                      as customer_unique_id,
    cast(first_order.first_order_id as varchar(32))                                          as first_order_id,
    cast(first_order.first_order_date as date)                                               as first_order_date,
    cast(first_order.first_order_delivered_date as date)                                     as first_order_delivered_date,
    cast(totals.order_count as number(10,0))                                                 as order_count,
    cast(totals.order_count > 1 as boolean)                                                  as has_multiple_orders,
    cast(
        case
            when first_order.first_order_delivered_date is null then null
            else returned.customer_unique_id is not null
        end as boolean
    )                                                                                        as repeat_after_first_delivery,
    cast(first_order.first_order_state as varchar(2))                                        as first_order_state,
    cast(first_order.first_order_city as varchar)                                            as first_order_city,
    cast(first_order.first_order_zip_code_prefix as varchar(5))                              as first_order_zip_code_prefix

from first_order
inner join totals on totals.customer_unique_id = first_order.customer_unique_id
left join returned on returned.customer_unique_id = first_order.customer_unique_id
