{#
  One row per PERSON (customer_unique_id), not per customer_id, which is new on every order (D12).
  The location is the one used on the person's FIRST order, so it cannot change between runs (D13).
  order_count counts every order of the person whatever its status, and the first order may itself be a canceled or
  unavailable one (1,153 people; 55 of them ordered again), a known caveat (D39).
#}
with person_orders as (

    select * from {{ ref('int_customer_orders') }}

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
        order_id                                  as first_order_id,
        cast(order_purchase_timestamp as date)    as first_order_date,
        customer_zip_code_prefix                  as first_order_zip_code_prefix,
        customer_city                             as first_order_city,
        customer_state                            as first_order_state
    from person_orders
    where order_number = 1

)

select
    cast({{ generate_surrogate_key(['first_order.customer_unique_id']) }} as varchar(32))   as customer_sk,
    cast(first_order.customer_unique_id as varchar(32))                                      as customer_unique_id,
    cast(first_order.first_order_id as varchar(32))                                          as first_order_id,
    cast(first_order.first_order_date as date)                                               as first_order_date,
    cast(totals.order_count as number(10,0))                                                 as order_count,
    cast(totals.order_count > 1 as boolean)                                                  as is_repeat_customer,
    cast(first_order.first_order_state as varchar(2))                                        as first_order_state,
    cast(first_order.first_order_city as varchar)                                            as first_order_city,
    cast(first_order.first_order_zip_code_prefix as varchar(5))                              as first_order_zip_code_prefix

from first_order
inner join totals on totals.customer_unique_id = first_order.customer_unique_id
