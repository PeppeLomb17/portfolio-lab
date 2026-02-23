BEGIN;

INSERT INTO portfolio.assets (ticker, isin, name, asset_type, currency, exchange)
VALUES
  ('AAPL', NULL, 'Apple Inc.', 'STOCK', 'USD', 'NASDAQ'),
  ('VWCE', 'IE00BK5BQT80', 'Vanguard FTSE All-World UCITS ETF', 'ETF', 'EUR', 'XETRA'),
  ('BTC',  NULL, 'Bitcoin', 'CRYPTO', 'USD', 'CRYPTO')
ON CONFLICT DO NOTHING;

WITH a AS (
  SELECT asset_id, ticker FROM portfolio.assets
),
tx AS (
  SELECT * FROM (VALUES
    ('demo', 'main', 'DEPOSIT'::portfolio.tx_type,   '2026-02-01T10:00:00+01'::timestamptz, NULL::bigint, 0::numeric, 1000::numeric, 0::numeric, 0::numeric, NULL::numeric, 'EUR', 'Initial deposit'),

    ('demo', 'main', 'BUY'::portfolio.tx_type,       '2026-02-02T10:00:00+01'::timestamptz, (SELECT asset_id FROM a WHERE ticker='VWCE'), 1::numeric, 110::numeric, 1::numeric, 0::numeric, NULL::numeric, 'EUR', 'Buy VWCE'),

    ('demo', 'main', 'BUY'::portfolio.tx_type,       '2026-02-03T10:00:00+01'::timestamptz, (SELECT asset_id FROM a WHERE ticker='AAPL'), 0.2::numeric, 180::numeric, 0.5::numeric, 0::numeric, 1.08::numeric, 'EUR', 'Buy AAPL (fx example)'),

    ('demo', 'main', 'DIVIDEND'::portfolio.tx_type,  '2026-02-10T10:00:00+01'::timestamptz, (SELECT asset_id FROM a WHERE ticker='AAPL'), 0::numeric, 2::numeric, 0::numeric, 0.4::numeric, 1.08::numeric, 'EUR', 'AAPL dividend'),

    ('demo', 'main', 'FEE'::portfolio.tx_type,       '2026-02-11T10:00:00+01'::timestamptz, NULL::bigint, 0::numeric, 0::numeric, 1::numeric, 0::numeric, NULL::numeric, 'EUR', 'Monthly fee'),

    ('demo', 'main', 'BUY'::portfolio.tx_type,       '2026-02-12T10:00:00+01'::timestamptz, (SELECT asset_id FROM a WHERE ticker='BTC'), 0.01::numeric, 40000::numeric, 0::numeric, 0::numeric, 1.08::numeric, 'EUR', 'Buy BTC')
  ) AS t(broker, account, tx_type, tx_time, asset_id, quantity, price, fees, taxes, fx_rate, cash_currency, notes)
)
INSERT INTO portfolio.transactions
  (broker, account, tx_type, tx_time, asset_id, quantity, price, fees, taxes, fx_rate, cash_currency, notes)
SELECT broker, account, tx_type, tx_time, asset_id, quantity, price, fees, taxes, fx_rate, cash_currency, notes
FROM tx;

COMMIT;

