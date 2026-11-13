with source as (

    select * from {{ source('olist', 'order_reviews') }}

),

typed as (

    select
        cast(review_id as varchar(32))                         as review_id,
        cast(order_id as varchar(32))                          as order_id,
        cast(review_score as number(1, 0))                     as review_score,
        review_comment_title,
        review_comment_message,
        {{ olist_timestamp('review_creation_date') }}          as review_creation_date,
        {{ olist_timestamp('review_answer_timestamp') }}       as review_answer_timestamp,

        _source_file,
        _source_row,
        _loaded_at

    from source

)

select * from typed
