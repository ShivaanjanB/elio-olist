{#
  Rolls the payment rows up to ORDER grain: one row per order that has payments. An order can be paid in up to 29
  pieces and by mixed methods, so joining payments to anything at item or order level would inflate every total (D15).

  primary_payment_type is the type of the LARGEST payment. The two largest payments tie on value for 188 orders, so
  the tie is broken by payment_sequential (the earlier payment wins) to keep the answer stable between runs.
#}
with payments as (

    select * from {{ ref('stg_olist__order_payments') }}

),

totals as (

    select
        order_id,
        sum(payment_value)                          as payment_total,
        count(*)                                    as payment_count,
        max(payment_installments)                   as installments_max,
        boolor_agg(payment_type = 'voucher')        as used_voucher
    from payments
    group by order_id

),

largest as (

    select
        order_id,
        payment_type as primary_payment_type
    from payments
    qualify row_number() over (
        partition by order_id
        order by payment_value desc, payment_sequential
    ) = 1

)

select
    totals.order_id,
    totals.payment_total,
    totals.payment_count,
    totals.installments_max,
    totals.used_voucher,
    largest.primary_payment_type

from totals
inner join largest on largest.order_id = totals.order_id
