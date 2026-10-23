-- customer_features.main_payment_type が、独立に再計算した値と一致するかを検証する。
--
-- モデルの結果を正解とみなさないよう、staging から直接、モデルとは別の書き方 (row_number) で期待値を計算する。
-- 定義: 支払い方法ごとに、その方法を使った注文の数 → 金額の合計 → 名前の辞書順で先頭の方法。
-- 複数の方法を含む注文は各方法に 1 注文として数える。支払いの記録がなければ NULL (docs/customer_features.md)。
-- 結果が 1 行以上あるとテストは失敗する。

with delivered_payments as (
    select
        customers.customer_unique_id,
        payments.order_id,
        payments.payment_type,
        payments.payment_value
    from {{ ref('stg_orders') }} as orders
    inner join {{ ref('stg_customers') }} as customers
        on orders.customer_id = customers.customer_id
    inner join {{ ref('stg_order_payments') }} as payments
        on orders.order_id = payments.order_id
    where orders.order_status = 'delivered'
),

per_type as (
    select
        customer_unique_id,
        payment_type,
        count(distinct order_id) as order_count,
        sum(payment_value) as amount
    from delivered_payments
    group by customer_unique_id, payment_type
),

expected as (
    select
        customer_unique_id,
        payment_type as main_payment_type
    from per_type
    qualify row_number() over (
        partition by customer_unique_id
        order by order_count desc, amount desc, payment_type asc
    ) = 1
)

select
    features.customer_unique_id,
    features.main_payment_type as actual_main_payment_type,
    expected.main_payment_type as expected_main_payment_type
from {{ ref('customer_features') }} as features
left join expected
    on features.customer_unique_id = expected.customer_unique_id
where features.main_payment_type is distinct from expected.main_payment_type
