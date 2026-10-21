-- fct_delivered_orders の件数と金額が、staging の delivered の注文と一致するかを検証する。
--
-- 明細・支払い・レビューを注文単位に集約せずに結合すると、行が増えて金額が二重に数えられる。
-- その場合、件数か金額の合計が staging とずれるため、このテストで検出できる。
-- 結果が 1 行以上あるとテストは失敗する。

with staging as (
    select
        count(distinct orders.order_id) as order_count,
        sum(items.price) as items_amount,
        sum(items.freight_value) as freight_amount
    from {{ ref('stg_orders') }} as orders
    left join {{ ref('stg_order_items') }} as items
        on orders.order_id = items.order_id
    where orders.order_status = 'delivered'
),

mart as (
    select
        count(*) as order_count,
        sum(items_amount) as items_amount,
        sum(freight_amount) as freight_amount
    from {{ ref('fct_delivered_orders') }}
)

select
    staging.order_count as staging_order_count,
    mart.order_count as mart_order_count,
    staging.items_amount as staging_items_amount,
    mart.items_amount as mart_items_amount,
    staging.freight_amount as staging_freight_amount,
    mart.freight_amount as mart_freight_amount
from staging
cross join mart
where
    staging.order_count != mart.order_count
    or staging.items_amount != mart.items_amount
    or staging.freight_amount != mart.freight_amount
