{#
  The type decisions of docs/data_model.md section 4 (D07), written once so every staging model applies them
  the same way. RAW holds everything as text; these turn it into the real types.

  They are STRICT on purpose (D31): a value that does not fit the type makes the build fail loudly
  instead of silently becoming NULL (which is what try_cast would do). The loaded data was checked
  beforehand with 0 failures (docs/type_and_design_checks.sql), so a failure here means the source changed.
  A blank value is NULL in RAW and stays NULL.
#}

{# Source timestamps look like 2017-10-02 10:56:33, with no time zone, so they stay TIMESTAMP_NTZ (D09).
   The format is spelled out so it is never guessed (a day/month swap would pass silently). #}
{% macro olist_timestamp(column) -%}
    to_timestamp_ntz({{ column }}, 'YYYY-MM-DD HH24:MI:SS')
{%- endmacro %}

{# Money: at most 2 decimals in the data (price up to 6,735.00, payment up to 13,664.08). #}
{% macro olist_money(column) -%}
    cast({{ column }} as number(12, 2))
{%- endmacro %}

{# Whole numbers: counts, positions, lengths, weights and sizes. #}
{% macro olist_integer(column) -%}
    cast({{ column }} as number(10, 0))
{%- endmacro %}
