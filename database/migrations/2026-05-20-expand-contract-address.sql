-- nft_tokens.contract_address был VARCHAR(42) (длина Ethereum-адреса),
-- но TON-адреса в user-friendly формате (EQ/UQ/kQ/0Q...) имеют 48 символов.
-- Расширяем до 64 чтобы покрыть TON, Solana base58 (44) и др.
ALTER TABLE nft_tokens ALTER COLUMN contract_address TYPE VARCHAR(64);
