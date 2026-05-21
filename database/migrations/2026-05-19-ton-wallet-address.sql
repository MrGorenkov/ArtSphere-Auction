-- Добавляет колонку под адрес подключённого Tonkeeper-кошелька (для payout при выигрыше).
ALTER TABLE users ADD COLUMN IF NOT EXISTS ton_wallet_address VARCHAR(48);
