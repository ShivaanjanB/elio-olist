{#
  Every person must have exactly ONE first order.
#}
select
    customer_sk,
    count_if(is_first_order) as first_orders
from {{ ref('fct_orders') }}
group by customer_sk
having count_if(is_first_order) <> 1
