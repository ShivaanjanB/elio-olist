{#
  One row per ORDER: the spine of the star (D21).
#}
with orders as (

    select * from {{ ref('stg_olist__orders') }}

),

customer_orders as (

    select * from {{ ref('int_customer_orders') }}

),

items as (

    select * from {{ ref('int_order_items_rollup') }}

),

payments as (

    select * from {{ ref('int_order_payments') }}

),

reviews as (

    select * from {{ ref('int_order_reviews') }}

),

joined as (

    select
        orders.order_id,
        customer_orders.customer_unique_id,
        orders.order_status,
        orders.order_purchase_timestamp,
        cast(orders.order_purchase_timestamp as date)         as purchase_date,
        cast(orders.order_estimated_delivery_date as date)    as estimated_delivery_date,
        case
            when orders.order_status = 'delivered'
                then cast(orders.order_delivered_customer_date as date)
        end                                                   as delivered_date,
        customer_orders.customer_state,
        customer_orders.order_number                          as customer_order_number,
        coalesce(items.item_count, 0)                         as item_count,
        coalesce(items.seller_count, 0)                       as seller_count,
        coalesce(items.items_price_total, 0)                  as items_price_total,
        coalesce(items.freight_total, 0)                      as freight_total,
        coalesce(payments.payment_total, 0)                   as payment_total,
        coalesce(payments.payment_count, 0)                   as payment_count,
        payments.installments_max,
        payments.primary_payment_type,
        reviews.review_score,
        coalesce(reviews.review_count, 0)                     as review_count

    from orders
    left join customer_orders on customer_orders.order_id = orders.order_id
    left join items           on items.order_id           = orders.order_id
    left join payments        on payments.order_id        = orders.order_id
    left join reviews         on reviews.order_id         = orders.order_id

),

measured as (

    select
        *,
        datediff(day, purchase_date, delivered_date)             as days_to_deliver,
        datediff(day, estimated_delivery_date, delivered_date)   as days_vs_estimate
    from joined

)

select
    cast(order_id as varchar(32))                                                      as order_id,
    cast({{ generate_surrogate_key(['customer_unique_id']) }} as varchar(32))          as customer_sk,
    cast(purchase_date as date)                                                        as purchase_date,
    cast(order_purchase_timestamp as timestamp_ntz)                                    as purchase_timestamp,
    cast(order_status as varchar)                                                      as order_status,
    cast(order_status not in ('canceled', 'unavailable') as boolean)                   as is_revenue_order,
    cast(customer_state as varchar(2))                                                 as customer_state,
    cast(customer_order_number as number(10,0))                                        as customer_order_number,
    cast(customer_order_number = 1 as boolean)                                         as is_first_order,
    cast(estimated_delivery_date as date)                                              as estimated_delivery_date,
    cast(delivered_date as date)                                                       as delivered_date,
    cast(days_to_deliver as number(10,0))                                              as days_to_deliver,
    cast(days_vs_estimate as number(10,0))                                             as days_vs_estimate,
    cast(days_vs_estimate > 0 as boolean)                                              as is_late,
    cast(item_count as number(10,0))                                                   as item_count,
    cast(seller_count as number(10,0))                                                 as seller_count,
    cast(items_price_total as number(12,2))                                            as items_price_total,
    cast(freight_total as number(12,2))                                                as freight_total,
    cast(items_price_total + freight_total as number(12,2))                            as gmv,
    cast(iff(order_status not in ('canceled', 'unavailable'), items_price_total, 0) as number(12,2))   as revenue,
    cast(payment_total as number(12,2))                                                as payment_total,
    cast(payment_count as number(10,0))                                                as payment_count,
    cast(installments_max as number(10,0))                                             as installments_max,
    cast(primary_payment_type as varchar)                                              as primary_payment_type,
    cast(review_score as number(1,0))                                                  as review_score,
    cast(review_count as number(10,0))                                                 as review_count

from measured
