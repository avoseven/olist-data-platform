-- customer_features の顧客数・注文数・購入金額が、fct_delivered_orders と一致するかを検証する。
--
-- カテゴリや支払い方法などの CTE を顧客単位に集約せずに結合すると、行が増えて値が重複して数えられる。
-- その場合、顧客数か合計がずれるため、このテストで検出できる。
-- 結果が 1 行以上あるとテストは失敗する。

with fct as (
    select
        count(distinct customer_unique_id) as customer_count,
        count(*) as order_count,
        sum(items_amount) as items_amount
    from {{ ref('fct_delivered_orders') }}
),

features as (
    select
        count(*) as customer_count,
        sum(order_count) as order_count,
        sum(total_items_amount) as items_amount
    from {{ ref('customer_features') }}
)

select
    fct.customer_count as fct_customer_count,
    features.customer_count as features_customer_count,
    fct.order_count as fct_order_count,
    features.order_count as features_order_count,
    fct.items_amount as fct_items_amount,
    features.items_amount as features_items_amount
from fct
cross join features
where
    fct.customer_count != features.customer_count
    or fct.order_count != features.order_count
    or fct.items_amount != features.items_amount
