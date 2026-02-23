CREATE OR REPLACE VIEW portfolio.positions_current AS
WITH qty_by_asset AS (
  SELECT
    t.asset_id,
    SUM(
      CASE
        WHEN t.tx_type = 'BUY' THEN t.quantity
        WHEN t.tx_type = 'SELL' THEN -t.quantity
        ELSE 0
      END
    ) AS quantity
  FROM portfolio.transactions t
  WHERE t.asset_id IS NOT NULL
  GROUP BY t.asset_id
)
SELECT
  a.asset_id,
  a.ticker,
  a.isin,
  a.name,
  a.asset_type,
  a.currency AS asset_currency,
  COALESCE(q.quantity, 0) AS quantity
FROM portfolio.assets a
LEFT JOIN qty_by_asset q
  ON q.asset_id = a.asset_id;


CREATE OR REPLACE VIEW portfolio.cash_ledger AS
SELECT
  t.tx_id,
  t.tx_time,
  t.tx_type,
  t.cash_currency,
  (
    CASE
      WHEN t.tx_type = 'DEPOSIT'  THEN  (t.price - t.fees - t.taxes)
      WHEN t.tx_type = 'WITHDRAWAL' THEN -(t.price + t.fees + t.taxes)
      WHEN t.tx_type = 'DIVIDEND' THEN  (t.price - t.fees - t.taxes)
      WHEN t.tx_type = 'FEE'      THEN -(t.fees + t.taxes)
      WHEN t.tx_type = 'BUY'      THEN -(t.quantity * t.price + t.fees + t.taxes)
      WHEN t.tx_type = 'SELL'     THEN  (t.quantity * t.price - t.fees - t.taxes)
      ELSE 0
    END
  ) AS cash_delta
FROM portfolio.transactions t;
