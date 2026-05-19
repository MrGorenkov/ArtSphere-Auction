-- Переводит существующие артворки и NFT-токены на TON и меняет DEFAULT.
-- Запускать поверх уже инициализированной БД; init.sql также обновлён.

ALTER TABLE artworks ALTER COLUMN blockchain SET DEFAULT 'TON';
ALTER TABLE nft_tokens ALTER COLUMN blockchain SET DEFAULT 'TON';

-- Все существующие артворки переводим на TON (раньше были Polygon/Ethereum по умолчанию).
UPDATE artworks SET blockchain = 'TON' WHERE blockchain IN ('Polygon', 'Ethereum');
UPDATE nft_tokens SET blockchain = 'TON' WHERE blockchain IN ('Polygon', 'Ethereum');
