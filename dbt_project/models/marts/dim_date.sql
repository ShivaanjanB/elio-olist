{#
  One row per calendar day from 2016-01-01 to 2018-12-31 (D25), generated here so it needs no package (D40).
#}
{%- set start_date = '2016-01-01' -%}
{%- set end_date = '2018-12-31' -%}
{%- set day_count = (modules.datetime.date.fromisoformat(end_date) - modules.datetime.date.fromisoformat(start_date)).days + 1 -%}

with spine as (

    select
        dateadd(day, row_number() over (order by seq4()) - 1, to_date('{{ start_date }}')) as date_day
    from table(generator(rowcount => {{ day_count }}))

)

select
    cast(date_day as date)                                  as date_day,
    cast(year(date_day) as number(4,0))                     as year,
    cast(quarter(date_day) as number(1,0))                  as quarter,
    cast(month(date_day) as number(2,0))                    as month,
    cast(to_char(date_day, 'YYYY-MM') as varchar(7))        as year_month,
    cast(monthname(date_day) as varchar(3))                 as month_name,
    cast(dayofweekiso(date_day) as number(1,0))             as day_of_week,
    cast(dayname(date_day) as varchar(3))                   as day_name,
    cast(dayofweekiso(date_day) >= 6 as boolean)            as is_weekend

from spine
