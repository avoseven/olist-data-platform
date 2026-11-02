-- customer_features.purchase_day_count が、独立に再計算した値と一致するかを検証する。
--
-- モデルの結果を正解とみなさないよう、staging から直接、モデルとは別の書き方 (顧客と購入日の組を先に重複なしで作ってから数える) で期待値を計算する。
-- 定義: delivered の注文がある、異なる購入日の数 (ADR 013)。
-- 結果が 1 行以上あるとテストは失敗する。

with purchase_days as (
    -- 1 行 = 1 人 × 1 購入日
    select distinct
        customers.customer_unique_id,
        date(orders.order_purchased_at) as purchase_date
    from {{ ref('stg_orders') }} as orders
    inner join {{ ref('stg_customers') }} as customers
        on orders.customer_id = customers.customer_id
    where orders.order_status = 'delivered'
),

recomputed as (
    select
        customer_unique_id,
        count(*) as purchase_day_count
    from purchase_days
    group by customer_unique_id
)

select
    features.customer_unique_id,
    features.purchase_day_count,
    recomputed.purchase_day_count as recomputed_purchase_day_count
from {{ ref('customer_features') }} as features
full outer join recomputed
    on features.customer_unique_id = recomputed.customer_unique_id
where
    features.purchase_day_count is null
    or recomputed.purchase_day_count is null
    or features.purchase_day_count != recomputed.purchase_day_count
