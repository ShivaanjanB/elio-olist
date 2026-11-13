{#
  Every person must have exactly ONE first order. Comparing "number of first orders" with "number of people" can match
  while one person has none and another has two, so this counts per person. Returns each person who does not have
  exactly one; the test passes when nothing is returned.

  Debugging a failure: look at int_customer_orders for that customer_unique_id. A person with two first orders means the
  ranking did not break a tie (D13); a person with none means they have no orders, which cannot happen from orders.
#}
select
    customer_sk,
    count_if(is_first_order) as first_orders
from {{ ref('fct_orders') }}
group by customer_sk
having count_if(is_first_order) <> 1
