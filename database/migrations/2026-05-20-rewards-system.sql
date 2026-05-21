-- Rewards system: volume tier для buyer'ов + mint milestones для creator'ов + daily bonus.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS total_volume_traded DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_mints INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_daily_claim TIMESTAMPTZ;

-- Стартовый баланс новых юзеров — 50 (default по умолчанию был 10).
ALTER TABLE users ALTER COLUMN balance SET DEFAULT 50.0;

-- Существующих юзеров поднимаем до 50, если меньше.
UPDATE users SET balance = 50.0 WHERE balance < 50.0;

-- Существующим creator'ам считаем total_mints из nft_tokens (один токен = один mint).
UPDATE users u SET total_mints = sub.cnt
FROM (
    SELECT owner_id, COUNT(*) AS cnt FROM nft_tokens GROUP BY owner_id
) sub
WHERE u.id = sub.owner_id;
