CREATE SCHEMA IF NOT EXISTS portfolio;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'asset_type' AND n.nspname = 'portfolio'
  ) THEN
    CREATE TYPE portfolio.asset_type AS ENUM (
      'STOCK',
      'ETF',
      'BOND',
      'CRYPTO',
      'CASH',
      'COMMODITY',
      'OTHER'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'tx_type' AND n.nspname = 'portfolio'
  ) THEN
    CREATE TYPE portfolio.tx_type AS ENUM (
      'BUY',
      'SELL',
      'DIVIDEND',
      'FEE',
      'TAX',
      'DEPOSIT',
      'WITHDRAWAL',
      'SPLIT'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS portfolio.assets (
  asset_id BIGSERIAL PRIMARY KEY,
  ticker TEXT,
  isin TEXT,
  name TEXT NOT NULL,
  asset_type portfolio.asset_type NOT NULL,
  currency CHAR(3) NOT NULL,
  exchange TEXT,
  country CHAR(2),
  provider TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT assets_currency_len CHECK (char_length(currency) = 3),
  CONSTRAINT assets_country_len CHECK (country IS NULL OR char_length(country) = 2)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_assets_isin
  ON portfolio.assets (isin)
  WHERE isin IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_assets_ticker_exchange
  ON portfolio.assets (ticker, exchange)
  WHERE ticker IS NOT NULL;

CREATE TABLE IF NOT EXISTS portfolio.transactions (
  tx_id BIGSERIAL PRIMARY KEY,
  broker TEXT NOT NULL,
  account TEXT,
  tx_type portfolio.tx_type NOT NULL,
  tx_time TIMESTAMPTZ NOT NULL,
  asset_id BIGINT REFERENCES portfolio.assets(asset_id),
  quantity NUMERIC(20, 8) NOT NULL DEFAULT 0,
  price NUMERIC(20, 8) NOT NULL DEFAULT 0,
  fees NUMERIC(20, 8) NOT NULL DEFAULT 0,
  taxes NUMERIC(20, 8) NOT NULL DEFAULT 0,
  fx_rate NUMERIC(20, 10),
  cash_currency CHAR(3) NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT tx_cash_currency_len CHECK (char_length(cash_currency) = 3),
  CONSTRAINT tx_quantity_nonneg CHECK (quantity >= 0),
  CONSTRAINT tx_price_nonneg CHECK (price >= 0),
  CONSTRAINT tx_fees_nonneg CHECK (fees >= 0),
  CONSTRAINT tx_taxes_nonneg CHECK (taxes >= 0)
);

CREATE INDEX IF NOT EXISTS ix_transactions_time
  ON portfolio.transactions (tx_time);

CREATE INDEX IF NOT EXISTS ix_transactions_asset_time
  ON portfolio.transactions (asset_id, tx_time);

CREATE TABLE IF NOT EXISTS portfolio.prices_daily (
  asset_id BIGINT NOT NULL REFERENCES portfolio.assets(asset_id),
  price_date DATE NOT NULL,
  close NUMERIC(20, 8) NOT NULL,
  currency CHAR(3) NOT NULL,
  source TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (asset_id, price_date),
  CONSTRAINT prices_currency_len CHECK (char_length(currency) = 3),
  CONSTRAINT prices_close_pos CHECK (close > 0)
);

CREATE INDEX IF NOT EXISTS ix_prices_daily_date
  ON portfolio.prices_daily (price_date);

CREATE TABLE IF NOT EXISTS portfolio.fx_rates_daily (
  base_ccy CHAR(3) NOT NULL,
  quote_ccy CHAR(3) NOT NULL,
  rate_date DATE NOT NULL,
  rate NUMERIC(20, 10) NOT NULL,
  source TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (base_ccy, quote_ccy, rate_date),
  CONSTRAINT fx_base_len CHECK (char_length(base_ccy) = 3),
  CONSTRAINT fx_quote_len CHECK (char_length(quote_ccy) = 3),
  CONSTRAINT fx_rate_pos CHECK (rate > 0)
);

CREATE INDEX IF NOT EXISTS ix_fx_rates_daily_date
  ON portfolio.fx_rates_daily (rate_date);