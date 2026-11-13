{#
  One row per ORDER, tagged with the PERSON who placed it and which of their orders it was. customer_id is new on every
  order, so only customer_unique_id identifies a person (D12). Both dim_customer and fct_orders need this ranking, which
  is why it is its own model and not repeated (D29).

  order_number: 1 for the person's earliest purchase, ties broken by order_id so the first order cannot change
  between runs (D13; 276 people have their first order tied on the timestamp). It counts every order whatever its
  status: 55 repeat customers had a canceled or unavailable first order, which is kept as a known caveat (D39).

  The address columns are the ones used on THIS order, so dim_customer can take the location of the first order (D12).
#}
with orders as (

    select
        order_id,
        customer_id,
        order_purchase_timestamp
    from {{ ref('stg_olist__orders') }}

),

customers as (

    select
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    from {{ ref('stg_olist__customers') }}

)

select
    orders.order_id,
    orders.customer_id,
    customers.customer_unique_id,
    orders.order_purchase_timestamp,
    row_number() over (
        partition by customers.customer_unique_id
        order by orders.order_purchase_timestamp, orders.order_id
    )                                       as order_number,
    customers.customer_zip_code_prefix,
    customers.customer_city,
    customers.customer_state

from orders
left join customers on customers.customer_id = orders.customer_id
