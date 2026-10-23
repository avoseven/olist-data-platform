-- 1 行 = 1 人 (customer_unique_id)。delivered の注文を 1 件以上持つ顧客のみ
--
-- 顧客セグメンテーションの入力になる特徴量。定義は docs/customer_features.md を参照。
-- 集計の基準は fct_delivered_orders とし、カテゴリ・支払い方法・レビューのように
-- 注文単位では計算できない特徴量は、粒度を明示した CTE で集計してから結合する (ADR 007 の原則 1)。
-- 粒度の違う CTE を注文単位のデータに直接結合すると、注文数や金額が重複して数えられるため、
-- すべての CTE を顧客単位 (1 行 = 1 人) にしてから final で結合する。

with orders as (
    -- 1 行 = 1 注文
    select * from {{ ref('fct_delivered_orders') }}
),

reference as (
    -- 1 行のみ。基準日 = delivered の注文の最後の購入日 (ADR 006 の D)
    select max(order_purchase_date) as reference_date
    from orders
),

-- カテゴリ ------------------------------------------------------------------

category_items as (
    -- 1 行 = 明細 1 行 (delivered の注文、カテゴリがわかる商品のみ)
    select
        orders.customer_unique_id,
        orders.order_id,
        items.price,
        products.product_category_name,
        coalesce(
            translation.product_category_name_english,
            products.product_category_name
        ) as category_name
    from orders
    inner join {{ ref('stg_order_items') }} as items
        on orders.order_id = items.order_id
    inner join {{ ref('stg_products') }} as products
        on items.product_id = products.product_id
    left join {{ ref('stg_product_category_name_translation') }} as translation
        on products.product_category_name = translation.product_category_name
    where products.product_category_name is not null
),

customer_categories as (
    -- 1 行 = 顧客 × カテゴリ (GROUP BY のキーで一意になる)
    select
        customer_unique_id,
        product_category_name,
        category_name,
        -- 同じ注文に同じカテゴリの明細が複数あっても、注文は 1 回だけ数える
        count(distinct order_id) as order_count,
        sum(price) as items_amount
    from category_items
    group by customer_unique_id, product_category_name, category_name
),

category_features as (
    -- 1 行 = 1 人。カテゴリがわかる商品を買っていない顧客は現れない (結合後に NULL)
    select
        customer_unique_id,
        count(*) as distinct_category_count,
        -- 注文の数 → 価格の合計 → ポルトガル語名の辞書順 (原則 4)
        array_agg(
            category_name
            order by order_count desc, items_amount desc, product_category_name asc
            limit 1
        )[offset(0)] as top_category
    from customer_categories
    group by customer_unique_id
),

-- 支払い方法 ----------------------------------------------------------------

customer_payment_types as (
    -- 1 行 = 顧客 × 支払い方法 (GROUP BY のキーで一意になる)
    -- 複数の方法を含む注文は、各方法に 1 注文として数える
    select
        orders.customer_unique_id,
        payments.payment_type,
        count(distinct payments.order_id) as order_count,
        sum(payments.payment_value) as payment_amount
    from orders
    inner join {{ ref('stg_order_payments') }} as payments
        on orders.order_id = payments.order_id
    group by orders.customer_unique_id, payments.payment_type
),

payment_type_features as (
    -- 1 行 = 1 人。支払いのレコードがない顧客は現れない (結合後に NULL)
    select
        customer_unique_id,
        -- 注文の数 → 金額の合計 → 支払い方法の名前の辞書順 (原則 4)
        array_agg(
            payment_type
            order by order_count desc, payment_amount desc, payment_type asc
            limit 1
        )[offset(0)] as main_payment_type
    from customer_payment_types
    group by customer_unique_id
),

-- レビュー ------------------------------------------------------------------

customer_reviews as (
    -- 1 行 = 顧客 × review_id。同じ回答を 1 回だけ数えるため、重複を除く (ADR 006 の C の手順 4)
    -- 同じ review_id は同じスコアであることを、singular test で検証している
    select distinct
        customer_unique_id,
        review_id,
        review_score
    from orders
    where review_id is not null
),

review_features as (
    -- 1 行 = 1 人。採用したレビューがない顧客は現れない (結合後に NULL)
    select
        customer_unique_id,
        avg(review_score) as avg_review_score
    from customer_reviews
    group by customer_unique_id
),

-- 注文単位の値を集約する特徴量 ----------------------------------------------

order_features as (
    -- 1 行 = 1 人
    select
        customer_unique_id,
        count(*) as order_count,
        sum(item_count) as item_count,
        sum(items_amount) as total_items_amount,
        -- 注文ごとの値の平均 (原則 2)
        avg(items_amount) as avg_order_items_amount,
        -- 合計どうしの比 (原則 2)
        sum(items_amount) / sum(item_count) as avg_item_price,
        sum(freight_amount) / sum(total_amount) as freight_ratio,
        min(order_purchase_date) as first_purchase_date,
        max(order_purchase_date) as last_purchase_date,
        -- 以下は注文ごとの値の平均。NULL の注文は除かれ、すべて NULL なら NULL になる (原則 3)
        avg(cast(has_credit_card_payment as int64)) as credit_card_order_ratio,
        avg(max_card_installments) as avg_card_installments,
        avg(delivery_days) as avg_delivery_days,
        avg(delivery_delay_days) as avg_delivery_delay_days,
        avg(cast(is_late_delivery as int64)) as late_delivery_ratio,
        -- 1 つでも TRUE なら TRUE。すべて NULL なら NULL になる (原則 3)
        logical_or(has_voucher_payment) as has_used_voucher,
        logical_or(has_review_comment) as has_review_comment,
        -- 最後の注文に紐づく州。購入日時の降順 → order_id の昇順 (原則 4)
        array_agg(
            customer_state
            order by order_purchased_at desc, order_id asc
            limit 1
        )[offset(0)] as customer_state
    from orders
    group by customer_unique_id
),

final as (
    select
        order_features.customer_unique_id,
        reference.reference_date,
        -- 金額
        order_features.total_items_amount,
        order_features.avg_order_items_amount,
        order_features.avg_item_price,
        order_features.freight_ratio,
        -- 時期
        order_features.order_count,
        -- 商品
        order_features.item_count,
        category_features.distinct_category_count,
        category_features.top_category,
        -- 支払い
        order_features.credit_card_order_ratio,
        order_features.avg_card_installments,
        order_features.has_used_voucher,
        payment_type_features.main_payment_type,
        -- 体験
        review_features.avg_review_score,
        order_features.has_review_comment,
        order_features.avg_delivery_days,
        order_features.avg_delivery_delay_days,
        order_features.late_delivery_ratio,
        -- 地域
        order_features.customer_state,
        -- 時期 (日付どうしの差。ADR 006 の D)
        date_diff(reference.reference_date, order_features.last_purchase_date, day) as days_since_last_purchase,
        date_diff(reference.reference_date, order_features.first_purchase_date, day) as days_since_first_purchase
    from order_features
    cross join reference
    left join category_features
        on order_features.customer_unique_id = category_features.customer_unique_id
    left join payment_type_features
        on order_features.customer_unique_id = payment_type_features.customer_unique_id
    left join review_features
        on order_features.customer_unique_id = review_features.customer_unique_id
)

select * from final
