{#
  One row per order that has a review, holding the LATEST review (D14). 547 orders have several reviews and no two of
  them tie on answer time, but review_id is still the tie-break so the choice can never depend on row order.
  review_count keeps the fact that there were several visible.
#}
with reviews as (

    select * from {{ ref('stg_olist__order_reviews') }}

),

counted as (

    select
        order_id,
        count(*) as review_count
    from reviews
    group by order_id

),

latest as (

    select
        order_id,
        review_id,
        review_score,
        review_answer_timestamp
    from reviews
    qualify row_number() over (
        partition by order_id
        order by review_answer_timestamp desc, review_id
    ) = 1

)

select
    latest.order_id,
    latest.review_id,
    latest.review_score,
    latest.review_answer_timestamp,
    counted.review_count

from latest
inner join counted on counted.order_id = latest.order_id
