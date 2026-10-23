-- customer_features.top_category と distinct_category_count が、独立に再計算した値と一致するかを検証する。
--
-- モデルの結果を正解とみなさないよう、staging から直接、モデルとは別の書き方 (row_number) で期待値を計算する。
-- 定義: カテゴリがわかる商品について、注文の数 → 価格の合計 → ポルトガル語名の辞書順で先頭のカテゴリ。
-- 出力は英語名 (なければポルトガル語名)。カテゴリがわかる商品がなければ NULL (docs/customer_features.md)。
-- 結果が 1 行以上あるとテストは失敗する。

with delivered_items as (
    select
        customers.customer_unique_id,
        orders.order_id,
        items.price,
        products.product_category_name,
        translation.product_category_name_english
    from {{ ref('stg_orders') }} as orders
    inner join {{ ref('stg_customers') }} as customers
        on orders.customer_id = customers.customer_id
    inner join {{ ref('stg_order_items') }} as items
        on orders.order_id = items.order_id
    inner join {{ ref('stg_products') }} as products
        on items.product_id = products.product_id
    left join {{ ref('stg_product_category_name_translation') }} as translation
        on products.product_category_name = translation.product_category_name
    where
        orders.order_status = 'delivered'
        and products.product_category_name is not null
),

per_category as (
    select
        customer_unique_id,
        product_category_name,
        any_value(product_category_name_english) as product_category_name_english,
        count(distinct order_id) as order_count,
        sum(price) as amount
    from delivered_items
    group by customer_unique_id, product_category_name
),

ranked as (
    select
        *,
        row_number() over (
            partition by customer_unique_id
            order by order_count desc, amount desc, product_category_name asc
        ) as category_rank,
        count(*) over (partition by customer_unique_id) as category_count
    from per_category
),

expected as (
    select
        customer_unique_id,
        category_count as distinct_category_count,
        if(product_category_name_english is null, product_category_name, product_category_name_english) as top_category
    from ranked
    where category_rank = 1
)

select
    features.customer_unique_id,
    features.top_category as actual_top_category,
    expected.top_category as expected_top_category,
    features.distinct_category_count as actual_distinct_category_count,
    expected.distinct_category_count as expected_distinct_category_count
from {{ ref('customer_features') }} as features
left join expected
    on features.customer_unique_id = expected.customer_unique_id
where
    -- NULL どうしも一致とみなす
    features.top_category is distinct from expected.top_category
    or features.distinct_category_count is distinct from expected.distinct_category_count
