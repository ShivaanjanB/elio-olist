{#
  Passes when no combination of the given columns appears more than once. This is what proves a
  COMPOSITE key, which dbt's built-in `unique` test cannot do (it takes one column).
  Used for (order_id, order_item_id), (order_id, payment_sequential) and (review_id, order_id).

  Written locally rather than imported from a package (D30). Same behaviour and name as
  dbt_utils.unique_combination_of_columns, so it can be swapped for the package later.

  Usage in a model's YAML:
    data_tests:
      - unique_combination_of_columns:
          arguments:
            combination_of_columns: [order_id, order_item_id]

  Debugging a failure: the test returns the repeated combinations and how many times each occurs.
#}
{% test unique_combination_of_columns(model, combination_of_columns) %}

select
    {{ combination_of_columns | join(', ') }},
    count(*) as rows_with_this_combination
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1

{% endtest %}
