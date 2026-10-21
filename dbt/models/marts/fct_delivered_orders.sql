-- 1 行 = 1 注文 (delivered の注文のみ)
--
-- 明細・支払い・レビューは、それぞれ注文単位に集約してから結合する (二重計上を防ぐため。ADR 006)。
-- 支払いやレビューがない注文も残すため、結合はすべて LEFT JOIN にする。
-- 列の定義は docs/customer_features.md の「fct_delivered_orders の列」を参照。

with orders as (
    -- 購入が成立した注文 (ADR 006 の A)
    select * from {{ ref('stg_orders') }}
    where order_status = 'delivered'
),

customers as (
    -- 1 行 = 1 customer_id (注文と 1:1)
    select
        customer_id,
        customer_unique_id,
        customer_state
    from {{ ref('stg_customers') }}
),

items_per_order as (
    -- 1 行 = 1 注文
    select
        order_id,
        count(*) as item_count,
        sum(price) as items_amount,
        sum(freight_value) as freight_amount
    from {{ ref('stg_order_items') }}
    group by order_id
),

payments_per_order as (
    -- 1 行 = 1 注文。支払いのレコードがない注文は、この CTE に現れない (結合後に NULL になる)
    select
        order_id,
        logical_or(payment_type = 'credit_card') as has_credit_card_payment,
        -- 分割回数が 0 のカード払いは不整合な値のため、対象から外す (ADR 006 の E)
        max(
            case
                when payment_type = 'credit_card' and payment_installments >= 1
                    then payment_installments
            end
        ) as max_card_installments,
        logical_or(payment_type = 'voucher' and payment_value > 0) as has_voucher_payment
    from {{ ref('stg_order_payments') }}
    group by order_id
),

valid_reviews as (
    -- 作成日が購入日より前のレビューは、注文との紐付けが疑わしいため除く (ADR 006 の C の手順 1)
    select reviews.*
    from {{ ref('stg_order_reviews') }} as reviews
    inner join orders
        on reviews.order_id = orders.order_id
    where reviews.review_creation_date >= date(orders.order_purchased_at)
),

adopted_reviews as (
    -- 1 行 = 1 注文。最新の回答を 1 件採用する (ADR 006 の C の手順 2)
    -- コメントは staging で空白を除き、空白だけのものは NULL にしているため、NULL でなければ文字がある
    select
        order_id,
        review_id,
        review_score,
        (review_comment_title is not null or review_comment_message is not null) as has_review_comment
    from valid_reviews
    qualify row_number() over (
        partition by order_id
        order by review_answered_at desc nulls last, review_id asc
    ) = 1
),

final as (
    select
        orders.order_id,
        customers.customer_unique_id,
        customers.customer_state,
        orders.order_purchased_at,
        items.item_count,
        items.items_amount,
        items.freight_amount,
        payments.has_credit_card_payment,
        payments.max_card_installments,
        payments.has_voucher_payment,
        reviews.review_id,
        reviews.review_score,
        reviews.has_review_comment,
        date(orders.order_purchased_at) as order_purchase_date,
        items.items_amount + items.freight_amount as total_amount,
        -- 配送の日数は日付どうしの差で計算する。配達日時がない注文は NULL になる (ADR 006 の E)
        date_diff(date(orders.order_delivered_customer_at), date(orders.order_purchased_at), day) as delivery_days,
        -- プラスなら遅れ、マイナスなら予定より早い
        date_diff(date(orders.order_delivered_customer_at), orders.order_estimated_delivery_date, day)
            as delivery_delay_days,
        date(orders.order_delivered_customer_at) > orders.order_estimated_delivery_date as is_late_delivery
    from orders
    left join customers
        on orders.customer_id = customers.customer_id
    left join items_per_order as items
        on orders.order_id = items.order_id
    left join payments_per_order as payments
        on orders.order_id = payments.order_id
    left join adopted_reviews as reviews
        on orders.order_id = reviews.order_id
)

select * from final
