-- views_v1.sql
-- Recreate portfolio views (drop in dependency order, then create in build order)
--
-- v1 fixes:
-- - Make cash_ledger FX-aware by using transactions.fx_rate when asset currency != cash_currency.
-- - Make cost basis (BUY) EUR-aware for any cash_currency.
-- - Keep logic simple and consistent with demo seed data.

-- Drop dependents first to avoid dependency errors
DROP VIEW IF EXISTS portfolio.positions_enriched_eur;
DROP VIEW IF EXISTS portfolio.snapshot_current_eur;
DROP VIEW IF EXISTS portfolio.pnl_current_eur;
DROP VIEW IF EXISTS portfolio.cash_ledger;
DROP VIEW IF EXISTS portfolio.positions_current;

-- 1) Current positions (quantity per asset)
--    BUY adds quantity, SELL subtracts quantity.
CREATE OR REPLACE VIEW portfolio.positions_current AS
SELECT
  a.asset_id,
  a.ticker,
  a.isin,
  a.name,
  a.asset_type,
  a.currency AS asset_currency,
  COALESCE(
    SUM(
      CASE
        WHEN t.tx_type = 'BUY'  THEN  t.quantity
        WHEN t.tx_type = 'SELL' THEN -t.quantity
        ELSE 0::numeric
      END
    ),
    0::numeric
  )::numeric(20,8) AS quantity
FROM portfolio.assets a
LEFT JOIN portfolio.transactions t
  ON t.asset_id = a.asset_id
GROUP BY a.asset_id, a.ticker, a.isin, a.name, a.asset_type, a.currency;

-- 2) Cash ledger (cash impact per transaction, in t.cash_currency)
--
-- FX rule (demo):
-- - If t.asset_id is NOT NULL and asset_currency != cash_currency and t.fx_rate is provided,
--   then we assume:
--     fx_rate = asset_ccy_per_1_cash_ccy
--   so we convert asset-priced amounts to cash currency by dividing by fx_rate.
--   Example: price=180 USD, cash_currency=EUR, fx_rate=1.08 (USD per EUR)
--            => EUR amount = 180 / 1.08
--
-- Conventions:
-- - DEPOSIT: +price
-- - WITHDRAWAL: -(price + fees + taxes)
-- - BUY: -(gross_cash + fees + taxes)
-- - SELL: +(gross_cash - fees - taxes)
-- - DIVIDEND: +(div_cash - taxes)
-- - FEE/TAX: -(fees + taxes)
CREATE OR REPLACE VIEW portfolio.cash_ledger AS
WITH tx_enriched AS (
  SELECT
    t.tx_id,
    t.tx_time,
    t.tx_type,
    t.cash_currency,
    t.quantity,
    t.price,
    t.fees,
    t.taxes,
    t.fx_rate,
    a.currency AS asset_currency,
    CASE
      WHEN t.asset_id IS NULL THEN t.price
      WHEN a.currency = t.cash_currency THEN (t.price * t.quantity)
      WHEN t.fx_rate IS NULL THEN (t.price * t.quantity)
      ELSE (t.price * t.quantity) / t.fx_rate
    END AS gross_cash,
    CASE
      WHEN t.asset_id IS NULL THEN t.price
      WHEN a.currency = t.cash_currency THEN t.price
      WHEN t.fx_rate IS NULL THEN t.price
      ELSE t.price / t.fx_rate
    END AS unit_price_cash
  FROM portfolio.transactions t
  LEFT JOIN portfolio.assets a
    ON a.asset_id = t.asset_id
)
SELECT
  x.tx_id,
  x.tx_time,
  x.tx_type,
  x.cash_currency,
  (
    CASE
      WHEN x.tx_type = 'DEPOSIT' THEN x.price
      WHEN x.tx_type = 'WITHDRAWAL' THEN -(x.price + x.fees + x.taxes)
      WHEN x.tx_type = 'BUY' THEN -(x.gross_cash + x.fees + x.taxes)
      WHEN x.tx_type = 'SELL' THEN  (x.gross_cash - x.fees - x.taxes)
      WHEN x.tx_type = 'DIVIDEND' THEN (
        CASE
          WHEN x.asset_currency IS NULL THEN x.price
          WHEN x.asset_currency = x.cash_currency THEN x.price
          WHEN x.fx_rate IS NULL THEN x.price
          ELSE x.price / x.fx_rate
        END
        - x.taxes
      )
      WHEN x.tx_type IN ('FEE', 'TAX') THEN -(x.fees + x.taxes)
      ELSE 0::numeric
    END
  )::numeric(20,10) AS cash_delta
FROM tx_enriched x;

-- 3) PnL in EUR (latest price per asset + latest FX rate to EUR)
--
-- Notes:
-- - last_price is taken from prices_daily (latest by date per asset)
-- - fx_to_eur uses fx_rates_daily (latest by date per base_ccy -> EUR)
-- - cost_basis_eur is computed from BUY transactions, converting their cash currency to EUR
CREATE OR REPLACE VIEW portfolio.pnl_current_eur AS
WITH last_price AS (
  SELECT DISTINCT ON (p.asset_id)
    p.asset_id,
    p.price_date,
    p.close AS last_price,
    p.currency AS price_ccy
  FROM portfolio.prices_daily p
  ORDER BY p.asset_id, p.price_date DESC
),
fx_to_eur AS (
  SELECT DISTINCT ON (f.base_ccy, f.quote_ccy)
    f.base_ccy,
    f.quote_ccy,
    f.rate_date,
    f.rate
  FROM portfolio.fx_rates_daily f
  WHERE f.quote_ccy = 'EUR'
  ORDER BY f.base_ccy, f.quote_ccy, f.rate_date DESC
),
pos AS (
  SELECT asset_id, ticker, quantity
  FROM portfolio.positions_current
  WHERE quantity <> 0
),
buys AS (
  SELECT
    t.asset_id,
    SUM(
      (
        CASE
          WHEN a.currency = t.cash_currency THEN (t.price * t.quantity)
          WHEN t.fx_rate IS NULL THEN (t.price * t.quantity)
          ELSE (t.price * t.quantity) / t.fx_rate
        END
        + t.fees + t.taxes
      )
      * (
        CASE
          WHEN t.cash_currency = 'EUR' THEN 1::numeric
          ELSE fx_cash.rate
        END
      )
    )::numeric(20,10) AS buy_cost_eur
  FROM portfolio.transactions t
  JOIN portfolio.assets a
    ON a.asset_id = t.asset_id
  LEFT JOIN fx_to_eur fx_cash
    ON fx_cash.base_ccy = t.cash_currency AND fx_cash.quote_ccy = 'EUR'
  WHERE t.tx_type = 'BUY'
  GROUP BY t.asset_id
)
SELECT
  pos.asset_id,
  pos.ticker,
  pos.quantity,
  lp.last_price,
  lp.price_ccy,
  CASE
    WHEN lp.price_ccy = 'EUR' THEN 1::numeric
    ELSE fx_price.rate
  END AS fx_to_eur,
  (
    (pos.quantity * lp.last_price)
    * (CASE WHEN lp.price_ccy = 'EUR' THEN 1::numeric ELSE fx_price.rate END)
  )::numeric(20,10) AS market_value_eur,
  buys.buy_cost_eur AS cost_basis_eur,
  (
    (
      (pos.quantity * lp.last_price)
      * (CASE WHEN lp.price_ccy = 'EUR' THEN 1::numeric ELSE fx_price.rate END)
    )
    - COALESCE(buys.buy_cost_eur, 0)
  )::numeric(20,10) AS pnl_eur,
  ROUND(
    CASE
      WHEN COALESCE(buys.buy_cost_eur, 0) = 0 THEN NULL
      ELSE (
        (
          (
            (pos.quantity * lp.last_price)
            * (CASE WHEN lp.price_ccy = 'EUR' THEN 1::numeric ELSE fx_price.rate END)
          )
          - buys.buy_cost_eur
        ) / buys.buy_cost_eur
      ) * 100
    END,
    4
  ) AS pnl_pct,
  lp.price_date
FROM pos
JOIN last_price lp USING (asset_id)
LEFT JOIN fx_to_eur fx_price
  ON fx_price.base_ccy = lp.price_ccy AND fx_price.quote_ccy = 'EUR'
LEFT JOIN buys
  ON buys.asset_id = pos.asset_id;

-- 4) Snapshot (cash + portfolio) in EUR
CREATE OR REPLACE VIEW portfolio.snapshot_current_eur AS
WITH cash AS (
  SELECT COALESCE(SUM(cash_delta), 0)::numeric AS cash_total_eur
  FROM portfolio.cash_ledger
  WHERE cash_currency = 'EUR'
),
portfolio_value AS (
  SELECT
    COALESCE(SUM(market_value_eur), 0)::numeric AS portfolio_total_eur,
    COALESCE(SUM(pnl_eur), 0)::numeric         AS pnl_total_eur
  FROM portfolio.pnl_current_eur
)
SELECT
  cash.cash_total_eur,
  portfolio_value.portfolio_total_eur,
  (cash.cash_total_eur + portfolio_value.portfolio_total_eur) AS net_worth_eur,
  portfolio_value.pnl_total_eur
FROM cash, portfolio_value;

-- 5) Enriched positions (allocation + pnl)
CREATE OR REPLACE VIEW portfolio.positions_enriched_eur AS
WITH totals AS (
  SELECT portfolio_total_eur
  FROM portfolio.snapshot_current_eur
)
SELECT
  p.ticker,
  p.market_value_eur,
  ROUND(
    CASE
      WHEN totals.portfolio_total_eur = 0 THEN 0
      ELSE (p.market_value_eur / totals.portfolio_total_eur) * 100
    END,
    4
  ) AS allocation_pct,
  p.pnl_eur,
  p.pnl_pct
FROM portfolio.pnl_current_eur p
CROSS JOIN totals;