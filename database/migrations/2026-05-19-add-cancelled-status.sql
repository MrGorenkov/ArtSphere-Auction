-- Расширяет valid_auction_status включая 'cancelled' (для возврата эскроу при отмене аукциона).
ALTER TABLE auctions DROP CONSTRAINT IF EXISTS valid_auction_status;
ALTER TABLE auctions ADD CONSTRAINT valid_auction_status CHECK (
    status IN ('upcoming', 'active', 'ended', 'sold', 'cancelled')
);
