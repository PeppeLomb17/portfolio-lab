BEGIN;

INSERT INTO portfolio.prices_daily (asset_id, price_date, close, currency)
SELECT a.asset_id, d.price_date, d.close, d.currency
FROM portfolio.assets a
JOIN (VALUES
  ('VWCE', '2026-02-20'::date, 112.50::numeric, 'EUR'::char(3)),
  ('AAPL', '2026-02-20'::date, 185.00::numeric, 'USD'::char(3)),
  ('BTC',  '2026-02-20'::date, 42000.00::numeric, 'USD'::char(3))
) AS d(ticker, price_date, close, currency)
ON a.ticker = d.ticker
ON CONFLICT DO NOTHING;

COMMIT;