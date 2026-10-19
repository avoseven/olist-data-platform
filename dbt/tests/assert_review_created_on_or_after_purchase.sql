-- レビューの作成日が、対象の注文の購入日より前になっているレビューを検出する。
--
-- 複数のテーブルにまたがるルールのため、汎用のテストではなく、SQL で直接書く (singular test)。
-- 結果が 1 行以上あるとテストは失敗する。
-- 元データには例外がある (64 行、大半はキャンセルされた注文。docs/data_notes.md) ため、警告にする。

{{ config(severity='warn') }}

select
    reviews.review_id,
    reviews.order_id,
    reviews.review_creation_date,
    orders.order_purchased_at,
    orders.order_status
from {{ ref('stg_order_reviews') }} as reviews
inner join {{ ref('stg_orders') }} as orders
    on reviews.order_id = orders.order_id
where reviews.review_creation_date < date(orders.order_purchased_at)
