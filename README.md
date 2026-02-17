# NFT Arts — Аукцион картин с 3D визуализацией



---

## Архитектура

```
┌─────────────────┐      REST API / WebSocket      ┌──────────────────┐
│   iOS App       │  ◄──────────────────────────►   │  Vapor Backend   │
│   (SwiftUI)     │       :8080                     │  (Swift 5.9)     │
└─────────────────┘                                 └────────┬─────────┘
                                                             │
                                                    ┌────────┼─────────┐
                                                    │        │         │
                                               ┌────▼───┐ ┌─▼──────┐ ┌▼────────┐
                                               │ Postgre│ │ MinIO  │ │ pgAdmin │
                                               │ SQL 16 │ │ (S3)   │ │         │
                                               │  :5432 │ │ :9000  │ │  :5050  │
                                               └────────┘ └────────┘ └─────────┘
```

## Технологии

| Компонент | Технология |
|-----------|-----------|
| iOS клиент | Swift, SwiftUI, SceneKit, ARKit, RealityKit |
| Бэкенд | Vapor 4 (Swift), Fluent ORM, JWT |
| База данных | PostgreSQL 16 (11 сущностей ER-диаграммы) |
| Хранилище файлов | MinIO (S3-совместимое) |
| Real-time | WebSocket (встроенный в Vapor) |
| Контейнеризация | Docker Compose |
| Управление БД | pgAdmin 4 |
| Генерация проекта | XcodeGen |

## Быстрый старт

### Требования

- **Docker** и **Docker Compose** (v2+)
- **Xcode 15+** (для iOS приложения)
- **macOS 13+**
- **iPhone** с iOS 16+ (для AR функций)

### 1. Запуск серверной части

```bash
# Клонировать/открыть проект
cd "iOS NFT-arts"

# Запустить все сервисы
docker compose up -d

# Проверить статус
docker compose ps
```

Это запустит:

| Сервис | URL | Описание |
|--------|-----|----------|
| **PostgreSQL** | `localhost:5432` | База данных (auto-init + seed) |
| **MinIO API** | `localhost:9000` | S3 хранилище файлов |
| **MinIO Console** | `localhost:9001` | Веб-интерфейс MinIO |
| **Vapor API** | `localhost:8080` | REST API + WebSocket |
| **pgAdmin** | `localhost:5050` | Управление БД |

### 2. Проверка работоспособности

```bash
# Проверить API
curl http://localhost:8080

# Ожидаемый ответ:
# {"status":"ok","service":"NFT Arts API","version":"1.0"}
```

### 3. Сборка iOS приложения

```bash
# Установить XcodeGen (если не установлен)
brew install xcodegen

# Сгенерировать проект
cd "iOS NFT-arts"
xcodegen generate

# Открыть в Xcode
open NFTArts.xcodeproj
```

Далее:
1. Выбрать ваше устройство (iPhone)
2. Указать Team для подписи
3. Cmd+R — запустить

---

## Учётные данные

### PostgreSQL
```
Host:     localhost:5432
Database: nftarts_db
User:     nftarts
Password: nftarts_secret
```

### pgAdmin
```
URL:      http://localhost:5050
Email:    admin@nftarts.com
Password: admin
```

### MinIO Console
```
URL:      http://localhost:9001
User:     nftarts_minio
Password: minio_secret_key
```

### Тестовый пользователь (API)
```
Wallet:   0x742d35Cc6634C0532925a3b844Bc9e7595f2bD01
Password: password123
```

---

## API Endpoints

### Аутентификация (открытые)
```
POST /api/v1/auth/register   — Регистрация
POST /api/v1/auth/login      — Вход (получить JWT)
```

### Стили живописи (открытые)
```
GET /api/v1/styles                  — Список стилей
GET /api/v1/styles/:id/artworks     — Работы по стилю
```

### Произведения (JWT)
```
GET  /api/v1/artworks               — Список (?search=, ?style_id=, ?blockchain=)
GET  /api/v1/artworks/:id           — Детали
POST /api/v1/artworks               — Создать
GET  /api/v1/artworks/:id/3d        — 3D модели
POST /api/v1/artworks/:id/upload-image — Загрузить изображение (multipart)
```

### Аукционы (JWT)
```
GET  /api/v1/auctions               — Список (?status=active)
GET  /api/v1/auctions/:id           — Детали (с artwork + bids)
POST /api/v1/auctions               — Создать
GET  /api/v1/auctions/:id/bids      — Ставки аукциона
```

### Ставки (JWT)
```
POST /api/v1/bids                   — Сделать ставку
```

### Пользователь (JWT)
```
GET  /api/v1/users/me               — Профиль
PUT  /api/v1/users/me               — Обновить профиль
POST /api/v1/users/me/avatar        — Загрузить аватар (multipart)
GET  /api/v1/users/me/stats         — Статистика
GET  /api/v1/users/me/notifications — Уведомления
```

### Коллекции (JWT)
```
GET    /api/v1/collections                         — Мои коллекции
POST   /api/v1/collections                         — Создать
PUT    /api/v1/collections/:id                     — Обновить
DELETE /api/v1/collections/:id                     — Удалить
POST   /api/v1/collections/:id/artworks            — Добавить работу
DELETE /api/v1/collections/:id/artworks/:artworkId — Убрать работу
```

### NFT Токены (JWT)
```
GET  /api/v1/nft          — Мои NFT
GET  /api/v1/nft/:id      — Детали токена
POST /api/v1/nft/mint     — Создать NFT из произведения
```

### Транзакции (JWT)
```
GET /api/v1/transactions       — Мои транзакции
GET /api/v1/transactions/:id   — Детали
```

### WebSocket (real-time)
```
ws://localhost:8080/ws/auction/:auctionId  — Обновления аукциона (ставки)
ws://localhost:8080/ws/user/:userId        — Персональные уведомления
```

---

## Структура базы данных (11 сущностей)

```
Пользователь (users)
Стиль_Живописи (art_styles)
Работа (artworks)
3D_Визуализация (visualizations_3d)
NFT_Токен (nft_tokens)
Аукцион (auctions)
Ставка (bids)
Транзакция (transactions)
Коллекция (collections)
Коллекция_Работа (collection_artworks)
Уведомление (notifications)
```

Дополнительные таблицы: `favorites`, `owned_artworks`, `auth_tokens`

---

## MinIO — хранилище файлов

Бакеты создаются автоматически при запуске:

| Бакет | Назначение |
|-------|-----------|
| `artworks` | Изображения произведений |
| `3d-models` | USDZ, GLB файлы для AR |
| `avatars` | Аватары пользователей |
| `files` | Исходные файлы произведений |

Все бакеты доступны для чтения по прямым URL:
```
http://localhost:9000/artworks/filename.png
http://localhost:9000/3d-models/model.usdz
```

---

## Структура проекта

```
iOS NFT-arts/
├── NFTArts/                    # iOS приложение (SwiftUI)
│   ├── App/                    # Entry point
│   ├── Core/                   # Theme, Navigation, Localization, Extensions
│   ├── Models/                 # NFTArtwork, Auction, User, NFTCollection
│   ├── Services/               # AuctionService, MockDataService, NetworkService
│   ├── Features/               # Feed, Detail, Explore, ARView, Collection, Profile, CreateNFT
│   └── Components/             # Artwork3DView, BidButton, CountdownTimer, etc.
├── backend/                    # Vapor API сервер
│   ├── Sources/App/
│   │   ├── Controllers/        # 8 контроллеров (Auth, Artwork, Auction, Bid, User, Collection, NFT, Transaction)
│   │   ├── Models/             # 9 Fluent моделей
│   │   ├── DTOs/               # Request/Response DTO
│   │   ├── Services/           # MinIOService, WebSocketManager
│   │   ├── routes.swift        # Маршруты + WebSocket
│   │   ├── JWTAuth.swift       # JWT middleware
│   │   └── entrypoint.swift    # Конфигурация
│   ├── Package.swift
│   └── Dockerfile
├── database/
│   ├── init.sql                # Полная схема БД (11 сущностей + триггеры + представления)
│   └── seed.sql                # Тестовые данные (7 пользователей, 10 работ, 10 аукционов)
├── docker-compose.yml          # PostgreSQL + MinIO + Vapor API + pgAdmin
├── project.yml                 # XcodeGen конфигурация
└── README.md
```

---

## Полезные команды

```bash
# Запустить все сервисы
docker compose up -d

# Остановить
docker compose down

# Пересоздать БД (сброс данных)
docker compose down -v && docker compose up -d

# Логи API сервера
docker compose logs -f api

# Логи БД
docker compose logs -f db

# Подключиться к БД через psql
docker compose exec db psql -U nftarts -d nftarts_db

# Пересобрать API после изменений
docker compose build api && docker compose up -d api
```

---

## Пример: авторизация и ставка

```bash
# 1. Логин
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"walletAddress":"0x742d35Cc6634C0532925a3b844Bc9e7595f2bD01","password":"password123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo "Token: $TOKEN"

# 2. Получить активные аукционы
curl -s http://localhost:8080/api/v1/auctions?status=active \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# 3. Сделать ставку
curl -s -X POST http://localhost:8080/api/v1/bids \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"auctionId":"c0000001-0000-0000-0000-000000000001","amount":2.0}'
```
