-- Adds 'TON' to valid_blockchain CHECK constraints.
-- Run against an already-initialized database; init.sql is updated for fresh installs.

ALTER TABLE artworks DROP CONSTRAINT IF EXISTS valid_blockchain;
ALTER TABLE artworks ADD CONSTRAINT valid_blockchain CHECK (
    blockchain IN ('Ethereum', 'Polygon', 'Solana', 'Tezos', 'TON')
);

ALTER TABLE nft_tokens DROP CONSTRAINT IF EXISTS valid_token_blockchain;
ALTER TABLE nft_tokens ADD CONSTRAINT valid_token_blockchain CHECK (
    blockchain IN ('Ethereum', 'Polygon', 'Solana', 'Tezos', 'TON')
);
