-- ================================================================
-- NFT Arts — Полная схема базы данных
-- PostgreSQL 16
-- Домашнее задание: Аукцион картин с 3D визуализацией
-- Студент: Горенков А.А., группа ИУ5-73Б
-- Кафедра ИУ5, МГТУ им. Н.Э. Баумана, 2025
--
-- 11 сущностей из ER-диаграммы:
--   Пользователь, Работа, Коллекция, Коллекция_Работа,
--   Стиль_Живописи, NFT_Токен, Аукцион, Ставка,
--   Транзакция, 3D_Визуализация, Уведомление
-- ================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- 1. ПОЛЬЗОВАТЕЛЬ (users)
-- ============================================
-- Содержит основную персональную информацию:
-- фамилия, имя, фото, почта, псевдоним, номер карты, адрес, пароль
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username        VARCHAR(50)  UNIQUE NOT NULL,          -- псевдоним
    display_name    VARCHAR(100) NOT NULL,                  -- имя + фамилия
    email           VARCHAR(255) UNIQUE,                    -- почта
    wallet_address  VARCHAR(100) UNIQUE NOT NULL,           -- адрес кошелька
    card_number     VARCHAR(19),                            -- номер карты
    avatar_url      TEXT,                                   -- фото профиля (MinIO)
    bio             TEXT DEFAULT '',
    balance         DOUBLE PRECISION DEFAULT 10.0,
    password_hash   TEXT NOT NULL,                          -- пароль (bcrypt)
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_wallet   ON users(wallet_address);

-- ============================================
-- 2. СТИЛЬ_ЖИВОПИСИ (art_styles)
-- ============================================
-- Справочник художественных направлений и техник:
-- название стиля, описание стиля
CREATE TABLE art_styles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) UNIQUE NOT NULL,               -- название стиля
    description TEXT DEFAULT '',                             -- описание стиля
    icon_name   VARCHAR(50),                                -- SF Symbol для iOS
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 3. РАБОТА (artworks)
-- ============================================
-- Данные о произведении цифрового искусства:
-- название, описание, фото, доступность, путь к файлу, цена
CREATE TABLE artworks (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title            VARCHAR(200) NOT NULL,                  -- название
    artist_name      VARCHAR(100) NOT NULL,
    description      TEXT DEFAULT '',                        -- описание
    image_url        TEXT,                                   -- путь к фото (MinIO)
    file_path        TEXT,                                   -- путь к исходному файлу (MinIO)
    price            DOUBLE PRECISION,                         -- цена за токены
    is_for_sale      BOOLEAN DEFAULT TRUE,                   -- доступность для продажи
    style_id         UUID REFERENCES art_styles(id) ON DELETE SET NULL,
    blockchain       VARCHAR(20) NOT NULL DEFAULT 'Polygon',
    metadata_json    TEXT DEFAULT '{}',
    creator_id       UUID REFERENCES users(id) ON DELETE SET NULL,
    is_published     BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT valid_blockchain CHECK (blockchain IN (
        'Ethereum', 'Polygon', 'Solana', 'Tezos'
    ))
);

CREATE INDEX idx_artworks_style    ON artworks(style_id);
CREATE INDEX idx_artworks_creator  ON artworks(creator_id);
CREATE INDEX idx_artworks_created  ON artworks(created_at DESC);

-- ============================================
-- 4. 3D_ВИЗУАЛИЗАЦИЯ (visualizations_3d)
-- ============================================
-- Данные для AR-просмотра произведений:
-- путь к 3D визуализации, вес файла, дата загрузки
CREATE TABLE visualizations_3d (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    artwork_id      UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    file_url        TEXT NOT NULL,                           -- путь к 3D-файлу (MinIO)
    file_size_bytes BIGINT,                                  -- вес файла
    format          VARCHAR(20) DEFAULT 'usdz',              -- usdz, glb, obj
    normal_map_url  TEXT,                                     -- normal map (MinIO)
    thumbnail_url   TEXT,
    uploaded_at     TIMESTAMPTZ DEFAULT NOW(),                -- дата загрузки

    CONSTRAINT valid_format CHECK (format IN ('usdz', 'glb', 'obj', 'reality'))
);

CREATE INDEX idx_viz3d_artwork ON visualizations_3d(artwork_id);

-- ============================================
-- 5. NFT_ТОКЕН (nft_tokens)
-- ============================================
-- Связь произведения с невзаимозаменяемым токеном:
-- адрес контракта, блокчейн, дата/время эмиссии, статус
CREATE TABLE nft_tokens (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    artwork_id       UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    owner_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contract_address VARCHAR(42) NOT NULL,                   -- адрес контракта NFT
    token_id_on_chain VARCHAR(100),                          -- ID токена в блокчейне
    blockchain       VARCHAR(20) NOT NULL DEFAULT 'Polygon', -- блокчейн
    status           VARCHAR(20) NOT NULL DEFAULT 'minted',  -- статус токена
    minted_at        TIMESTAMPTZ DEFAULT NOW(),               -- дата+время эмиссии
    metadata_uri     TEXT,                                    -- URI метаданных (IPFS/MinIO)

    CONSTRAINT valid_token_status CHECK (status IN (
        'minted', 'listed', 'sold', 'transferred', 'burned'
    )),
    CONSTRAINT valid_token_blockchain CHECK (blockchain IN (
        'Ethereum', 'Polygon', 'Solana', 'Tezos'
    ))
);

CREATE INDEX idx_nft_artwork ON nft_tokens(artwork_id);
CREATE INDEX idx_nft_owner   ON nft_tokens(owner_id);
CREATE UNIQUE INDEX idx_nft_contract ON nft_tokens(contract_address, token_id_on_chain);

-- ============================================
-- 6. АУКЦИОН (auctions)
-- ============================================
-- Торговая сессия: дата начала, время начала, дата окончания, время окончания
CREATE TABLE auctions (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    artwork_id     UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    creator_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    starting_price DOUBLE PRECISION NOT NULL,
    current_bid    DOUBLE PRECISION NOT NULL DEFAULT 0,
    reserve_price  DOUBLE PRECISION,
    bid_step       DOUBLE PRECISION DEFAULT 0.01,              -- шаг ставки
    start_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),        -- дата+время начала
    end_time       TIMESTAMPTZ NOT NULL,                      -- дата+время окончания
    status         VARCHAR(20) NOT NULL DEFAULT 'active',
    winner_id      UUID REFERENCES users(id) ON DELETE SET NULL,
    bid_count      INTEGER DEFAULT 0,
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT valid_auction_status CHECK (status IN ('upcoming', 'active', 'ended', 'sold')),
    CONSTRAINT valid_prices         CHECK (starting_price > 0),
    CONSTRAINT valid_times          CHECK (end_time > start_time)
);

CREATE INDEX idx_auctions_status   ON auctions(status);
CREATE INDEX idx_auctions_artwork  ON auctions(artwork_id);
CREATE INDEX idx_auctions_end_time ON auctions(end_time);
CREATE INDEX idx_auctions_creator  ON auctions(creator_id);

-- ============================================
-- 7. СТАВКА (bids)
-- ============================================
-- Действие участника: дата ставки, время ставки, стоимость ставки
CREATE TABLE bids (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    auction_id UUID NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount     DOUBLE PRECISION NOT NULL,                      -- стоимость ставки
    created_at TIMESTAMPTZ DEFAULT NOW(),                     -- дата+время ставки

    CONSTRAINT positive_amount CHECK (amount > 0)
);

CREATE INDEX idx_bids_auction    ON bids(auction_id);
CREATE INDEX idx_bids_user       ON bids(user_id);
CREATE INDEX idx_bids_amount     ON bids(auction_id, amount DESC);
CREATE INDEX idx_bids_created_at ON bids(created_at DESC);

-- ============================================
-- 8. ТРАНЗАКЦИЯ (transactions)
-- ============================================
-- Финансовые операции: сумма, дата, время, статус
CREATE TABLE transactions (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    auction_id     UUID REFERENCES auctions(id) ON DELETE SET NULL,
    buyer_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seller_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    artwork_id     UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    nft_token_id   UUID REFERENCES nft_tokens(id) ON DELETE SET NULL,
    amount         DOUBLE PRECISION NOT NULL,                  -- сумма транзакции
    status         VARCHAR(20) NOT NULL DEFAULT 'pending',   -- статус транзакции
    tx_hash        VARCHAR(66),                              -- хэш транзакции в блокчейне
    created_at     TIMESTAMPTZ DEFAULT NOW(),                 -- дата+время транзакции

    CONSTRAINT valid_tx_status CHECK (status IN (
        'pending', 'processing', 'completed', 'failed', 'refunded'
    ))
);

CREATE INDEX idx_tx_buyer   ON transactions(buyer_id);
CREATE INDEX idx_tx_seller  ON transactions(seller_id);
CREATE INDEX idx_tx_auction ON transactions(auction_id);
CREATE INDEX idx_tx_status  ON transactions(status);

-- ============================================
-- 9. КОЛЛЕКЦИЯ (collections)
-- ============================================
-- Персональные подборки: название, дата создания, приватность
CREATE TABLE collections (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name             VARCHAR(100) NOT NULL,                   -- название коллекции
    description      TEXT DEFAULT '',
    cover_artwork_id UUID REFERENCES artworks(id) ON DELETE SET NULL,
    is_private       BOOLEAN DEFAULT FALSE,                   -- приватность коллекции
    is_default       BOOLEAN DEFAULT FALSE,
    created_at       TIMESTAMPTZ DEFAULT NOW(),                -- дата создания
    updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_collections_user ON collections(user_id);

-- ============================================
-- 10. КОЛЛЕКЦИЯ_РАБОТА (collection_artworks)
-- ============================================
-- Ассоциативная сущность: позиция в коллекции, дата, заметка
CREATE TABLE collection_artworks (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    artwork_id    UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    position      INTEGER DEFAULT 0,                          -- позиция в коллекции
    user_note     TEXT DEFAULT '',                             -- заметка пользователя
    added_at      TIMESTAMPTZ DEFAULT NOW(),                   -- дата создания

    CONSTRAINT unique_collection_artwork UNIQUE (collection_id, artwork_id)
);

CREATE INDEX idx_ca_collection ON collection_artworks(collection_id);
CREATE INDEX idx_ca_artwork    ON collection_artworks(artwork_id);

-- ============================================
-- 11. УВЕДОМЛЕНИЕ (notifications)
-- ============================================
-- Системные оповещения: текст, дата получения, время получения
CREATE TABLE notifications (
    id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type               VARCHAR(30) NOT NULL,
    title              VARCHAR(200) NOT NULL,                  -- текст уведомления (заголовок)
    message            TEXT NOT NULL,                           -- текст уведомления (тело)
    related_auction_id UUID REFERENCES auctions(id) ON DELETE SET NULL,
    related_artwork_id UUID REFERENCES artworks(id) ON DELETE SET NULL,
    is_read            BOOLEAN DEFAULT FALSE,
    created_at         TIMESTAMPTZ DEFAULT NOW(),               -- дата+время получения

    CONSTRAINT valid_notification_type CHECK (type IN (
        'new_bid', 'bid_placed', 'outbid', 'auction_won',
        'auction_ended', 'nft_created', 'nft_transferred',
        'transaction_completed', 'system'
    ))
);

CREATE INDEX idx_notif_user   ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notif_unread ON notifications(user_id) WHERE is_read = FALSE;

-- ============================================
-- ДОПОЛНИТЕЛЬНЫЕ ТАБЛИЦЫ
-- ============================================

-- Избранное
CREATE TABLE favorites (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    artwork_id UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, artwork_id)
);

-- Владение NFT (результат аукциона/создания)
CREATE TABLE owned_artworks (
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    artwork_id       UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
    acquired_at      TIMESTAMPTZ DEFAULT NOW(),
    acquisition_type VARCHAR(20) NOT NULL DEFAULT 'auction',
    price_paid       DOUBLE PRECISION,
    PRIMARY KEY (user_id, artwork_id),
    CONSTRAINT valid_acquisition CHECK (acquisition_type IN ('auction', 'created', 'transfer'))
);

-- JWT/сессии
CREATE TABLE auth_tokens (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_auth_tokens_user ON auth_tokens(user_id);

-- ============================================
-- ФУНКЦИИ И ТРИГГЕРЫ
-- ============================================

-- Автообновление updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated       BEFORE UPDATE ON users       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_artworks_updated    BEFORE UPDATE ON artworks    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_auctions_updated    BEFORE UPDATE ON auctions    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_collections_updated BEFORE UPDATE ON collections FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Обновление аукциона при новой ставке
CREATE OR REPLACE FUNCTION on_bid_insert()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE auctions
    SET current_bid = NEW.amount,
        bid_count   = bid_count + 1,
        updated_at  = NOW()
    WHERE id = NEW.auction_id
      AND NEW.amount > current_bid;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bid_insert AFTER INSERT ON bids
    FOR EACH ROW EXECUTE FUNCTION on_bid_insert();

-- Завершение аукционов + создание транзакций
CREATE OR REPLACE FUNCTION check_auction_end()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT a.id, a.artwork_id, a.current_bid, a.reserve_price, a.creator_id,
               b.user_id AS top_bidder
        FROM auctions a
        LEFT JOIN (
            SELECT DISTINCT ON (auction_id) auction_id, user_id
            FROM bids ORDER BY auction_id, amount DESC
        ) b ON b.auction_id = a.id
        WHERE a.status = 'active' AND a.end_time <= NOW()
    LOOP
        IF rec.top_bidder IS NOT NULL
           AND (rec.reserve_price IS NULL OR rec.current_bid >= rec.reserve_price) THEN
            -- Аукцион продан
            UPDATE auctions SET status = 'sold', winner_id = rec.top_bidder WHERE id = rec.id;

            -- Передать владение
            INSERT INTO owned_artworks (user_id, artwork_id, acquisition_type, price_paid)
            VALUES (rec.top_bidder, rec.artwork_id, 'auction', rec.current_bid)
            ON CONFLICT DO NOTHING;

            -- Создать транзакцию
            INSERT INTO transactions (auction_id, buyer_id, seller_id, artwork_id, amount, status)
            VALUES (rec.id, rec.top_bidder, COALESCE(rec.creator_id, rec.top_bidder),
                    rec.artwork_id, rec.current_bid, 'completed');

            -- Уведомление победителю
            INSERT INTO notifications (user_id, type, title, message, related_auction_id)
            VALUES (rec.top_bidder, 'auction_won', 'Аукцион выигран!',
                    'Вы выиграли аукцион за ' || rec.current_bid || ' ETH', rec.id);
        ELSE
            UPDATE auctions SET status = 'ended' WHERE id = rec.id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Уведомление о перебитой ставке
CREATE OR REPLACE FUNCTION notify_outbid()
RETURNS TRIGGER AS $$
DECLARE
    prev_bidder UUID;
    auction_title TEXT;
BEGIN
    -- Найти предыдущего лидера
    SELECT b.user_id INTO prev_bidder
    FROM bids b WHERE b.auction_id = NEW.auction_id AND b.id != NEW.id
    ORDER BY b.amount DESC LIMIT 1;

    IF prev_bidder IS NOT NULL AND prev_bidder != NEW.user_id THEN
        SELECT aw.title INTO auction_title
        FROM auctions a JOIN artworks aw ON a.artwork_id = aw.id
        WHERE a.id = NEW.auction_id;

        INSERT INTO notifications (user_id, type, title, message, related_auction_id)
        VALUES (prev_bidder, 'outbid', 'Вашу ставку перебили!',
                'Новая ставка ' || NEW.amount || ' ETH на "' || COALESCE(auction_title, '?') || '"',
                NEW.auction_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notify_outbid AFTER INSERT ON bids
    FOR EACH ROW EXECUTE FUNCTION notify_outbid();

-- ============================================
-- ПРЕДСТАВЛЕНИЯ (VIEWS)
-- ============================================

CREATE OR REPLACE VIEW active_auctions_view AS
SELECT a.id AS auction_id, a.starting_price, a.current_bid, a.reserve_price,
       a.start_time, a.end_time, a.status, a.bid_count, a.winner_id,
       aw.id AS artwork_id, aw.title, aw.artist_name, aw.description,
       aw.image_url, s.name AS style_name, aw.blockchain,
       u.display_name AS creator_name
FROM auctions a
JOIN artworks aw ON a.artwork_id = aw.id
LEFT JOIN art_styles s ON aw.style_id = s.id
LEFT JOIN users u ON a.creator_id = u.id
WHERE a.status IN ('active', 'upcoming')
ORDER BY a.end_time ASC;

CREATE OR REPLACE VIEW user_stats_view AS
SELECT u.id AS user_id, u.display_name, u.balance,
       COUNT(DISTINCT oa.artwork_id) AS owned_count,
       COUNT(DISTINCT f.artwork_id) AS favorites_count,
       COUNT(DISTINCT c.id) AS collections_count,
       (SELECT COUNT(*) FROM auctions WHERE winner_id = u.id AND status = 'sold') AS auctions_won
FROM users u
LEFT JOIN owned_artworks oa ON oa.user_id = u.id
LEFT JOIN favorites f ON f.user_id = u.id
LEFT JOIN collections c ON c.user_id = u.id
GROUP BY u.id;
