-- 複数の注文に採用された同じ review_id が、同じ顧客・同じスコアであるかを検証する。
--
-- customer_features では、顧客単位でスコアを平均する前に review_id の重複を除く (ADR 006 の C の手順 4)。
-- これは「同じ review_id は同じ人の同じ回答である」ことを前提にしている。
-- 前提が崩れると、重複を除いたときに情報が失われるため、このテストで検出する。
-- 結果が 1 行以上あるとテストは失敗する。

select
    review_id,
    count(distinct customer_unique_id) as customer_count,
    count(distinct review_score) as score_count
from {{ ref('fct_delivered_orders') }}
where review_id is not null
group by review_id
having
    count(distinct customer_unique_id) > 1
    or count(distinct review_score) > 1
