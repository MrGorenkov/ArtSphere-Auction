# Handoff: ArtSphere Auction → Gemini

Передаю состояние проекта дипломной работы для продолжения. Защита **8 июня 2026**, сегодня **18 мая**, осталось **21 день**. Я — предыдущий ИИ-ассистент (Claude), это рабочий ctxt чтоб ты не разбирался с нуля.

## Что это за проект

iOS-приложение «ArtSphere Auction» — аукцион цифровых произведений искусства с 3D-визуализацией. Клиент-сервер: iOS (Swift/SwiftUI/SceneKit) ↔ Vapor 4 backend (Swift/PostgreSQL/MinIO) ↔ Docker.

**Репозиторий:** `https://github.com/MrGorenkov/ArtSphere-Auction`
**Локальный путь:** `/Users/alex_gorenkov/Desktop/iOS NFT-arts/`
**Студент:** Горенков А.А., ИУ5-83Б, МГТУ им. Баумана
**Защита:** 8 июня 2026, кафедра ИУ-5

## Текущее состояние (на момент handoff)

Последний коммит: **`6c5ea0e`** — A4 toggle + A5 heatmap overlay + A6 admin delete/timeseries.

### Что уже сделано перед смотром макетов (был ~15 мая)

- iOS-приложение полностью функционально
- Авторизация JWT с Keychain
- Лента аукционов с категориями, поиском, Featured carousel
- Детальный экран произведения с 2D/3D/Fullscreen 3D режимами
- 3D-визуализация через **NormalMapGenerator** (классический Sobel)
- Тепловая карта сложности текстуры (heatmap)
- Виртуальный 3D-шоурум в стиле Лувра (PBR, режимы освещения, walk-mode, расстановка картин)
- Создание NFT с серверным mint (симуляция блокчейна)
- Аукционные ставки real-time через WebSocket
- Offline-режим с BidQueue
- Десктопное приложение администратора (macOS)
- Документы: ТЗ, ПМИ, Руководство пользователя (в `Показ макетов/`)

### Замечания комиссии на смотре макетов (≈15 мая)

Комиссия потребовала исправить:

1. **Имитация блокчейна не понравилась** → нужна **реальная интеграция с TON Testnet** (но без реальных денег, тестовые монеты)
2. **Алгоритм Собеля заменить** на более современный → выбран **Depth Anything V2 (нейросеть монокулярной оценки глубины)** + Laplacian для деталей
3. **WebSocket нестабильный** — уведомления теряются → исправить лайф-цикл подключений
4. **Auto-broker не работает** — логика только клиентская, ломается при закрытии приложения
5. **Heatmap слабая** — переделать в overlay-режим с легендой
6. **Завершённые аукционы висят в ленте** → фильтровать
7. **Карусель «ХИТ» переименовать** в «Скоро завершатся» (раз там аукционы с истекающим временем)
8. **Шоурум очень понравился** → расширить: добавить пресеты тем + возможность шеринга
9. **Бонусная система (Battle Pass)** для пользователей
10. **Админка macOS неполная** — добавить удаление аукционов и расширенный функционал
11. **Ставки не на все картины проходят** — багу починить

### Что уже исправлено в последних коммитах

**Коммит `2dea357` (A1 + A2):**

- ✅ Завершённые/просроченные аукционы фильтруются на бекенде + клиенте
- ✅ Карусель «ХИТ» → «Скоро завершатся», бейдж «ФИНАЛ», иконка hourglass
- ✅ Сортировка featured по timeRemaining (правда о «соonest-to-end»)
- ✅ Багу со ставками на новые лоты починили — `minimumNextBid` теперь использует `startingPrice` когда `currentBid == 0`
- ✅ WebSocket подписан на `UIApplication.didBecomeActive` / `willResignActive` — корректно переподключается
- ✅ Auction History подтягивает sold + ended параллельно

**Коммит `2e5ac36` (A4 hybrid 3D):**

- ✅ Скачана и интегрирована Apple Depth Anything V2 Small CoreML (24МБ, F16-INT8)
- ✅ `DepthEstimator.swift` — обёртка VNCoreMLRequest, кэш на NSCache, runs on Neural Engine, ~30ms на iPhone 11 Pro
- ✅ `NormalMapGenerator.FilterAlgorithm` enum: `.sobel` / `.laplacian` / `.hybrid` (default)
- ✅ `generateLaplacian` — Marr-Hildreth (LoG) с ядрами `[1, -2, 1]` X/Y
- ✅ `generateHybrid` — `0.7 * depth_gradient + 0.3 * laplacian_detail`, normal map из combined gradient
- ✅ `generateHeightmap` в hybrid режиме возвращает MiDaS depth напрямую → реальная пространственная глубина в SCN displacement
- ✅ Graceful fallback на Laplacian если CoreML модель не загрузилась

**Коммит `6c5ea0e` (A4 toggle + A5 heatmap + A6 admin):**

- ✅ **A4 Phase 3** — Picker в ArtworkDetailView переключает Sobel / Laplacian / Hybrid (AI) на лету. `Artwork3DView.Coordinator.applyAlgorithm(_:)` пересоздаёт normal+displacement через `Task.detached`, кэш `NormalMapGenerator` использует составной ключ `normal_<strength>_<algorithm>`.
- ✅ **A5 Heatmap overlay** — `Slider` `heatmapBlend` (0.1…1.0) + вертикальная легенда (красный→жёлтый→синий). `setComplexityOverlay` смешивает оригинал и heatmap через `UIGraphicsImageRenderer` с `blendMode: .normal, alpha: heatmapBlend`.
- ✅ **A6 Admin DELETE** — `DELETE /admin/auctions/:id` с явным каскадом (bids → transactions → nullify notification refs). Кнопка с `confirmationDialog` в `AuctionDetailView` (NFTArtsAdmin), `deleteAuction(_:)` чистит выделение и `bids`.
- ✅ **A6 Admin timeseries** — `GET /admin/stats/timeseries` (14-дневная сводка количества аукционов и ставок по дням, DTO `AdminTimeseries`). Базовый URL macOS-админки переведён на `localhost:8080`.

## Что ещё нужно сделать (в порядке приоритета)

### КРИТИЧНО — осталось завершить

| # | Задача | Сложность | Замечание комиссии |
|---|---|---|---|
| 1 | **A3 Auto-broker** — перенести логику автоматических контр-ставок на бекенд (таблица `auto_broker_settings`, фоновая задача, broadcast через WS) | 1 день | пункт 4 |
| 2 | **Admin UI для timeseries** — отрисовать новый эндпоинт `/admin/stats/timeseries` (14-дневный график) на дашборде macOS-админки | 2-3 часа | пункт 10 (расширение) |
| 3 | **B (TON блокчейн)** — TestNet TON, смарт-контракт TEP-62 NFT-collection, TON Connect 2.0 SDK, реальный mint через подпись Tonkeeper | 4-5 дней | пункт 1 — **самое важное** |
| 4 | **C1 (Шоурум пресеты + шеринг)** — 4 темы (Лувр / Современная / Лофт / Cyberpunk), универсальные ссылки artsphere://showroom/CODE, гостевой режим | 2-3 дня | пункт 8 |
| 5 | **C2 (Bonus система)** — таблица `user_bonuses`, XP за действия, уровни 1-10 с разблокировкой тем шоурума | 2 дня | пункт 9 — опционально |

### ДОКУМЕНТЫ — после кода

| # | Документ | Что делать |
|---|---|---|
| 8 | Правки **ТЗ** под новые фичи (TON, шоурум-пресеты, бонусы) | 2-3 часа |
| 9 | Правки **ПМИ** — новые тест-кейсы | 2-3 часа |
| 10 | Правки **НИР2** — раздел про MiDaS вместо/вместе с Sobel (математика, листинг) | 1 день |
| 11 | **РПЗ (Расчётно-пояснительная записка)** — сборка из готовых артефактов по шаблону (взять у Пермякова или Иванова) | 1-2 дня |

## Архитектурные ориентиры (для быстрого старта)

### iOS-структура (`NFTArts/`)

```
NFTArts/
├── App/                       NFTArtsApp, AppDelegate
├── Core/
│   ├── Extensions/            View+, Color+
│   ├── Localization/          L10n.swift (русский/английский)
│   ├── Navigation/            MainTabView
│   └── Theme/                 NFTTypography, цвета
├── Components/
│   ├── NormalMapGenerator.swift   ⭐ алгоритм Sobel/Laplacian/Hybrid
│   ├── DepthEstimator.swift       ⭐ CoreML Depth Anything V2
│   ├── Artwork3DView.swift        SceneKit с PBR
│   ├── FullScreen3DViewer.swift   USDZ + orbit
│   ├── ErrorBanner.swift          (отключён, см. историю)
│   ├── SkeletonView.swift         loading state
│   ├── BidButton.swift            ставка + sheet
│   ├── ArtworkImageView.swift     async image
│   └── ImagePicker.swift
├── Features/
│   ├── Auth/                  LoginView, RegisterView
│   ├── Feed/                  FeedView, FeedViewModel
│   ├── Explore/               ExploreView (категории, поиск)
│   ├── Detail/                ArtworkDetailView, AuctionHistoryView
│   ├── CreateNFT/             CreateNFTView
│   ├── Collection/            MyCollectionView, EditCollectionSheet
│   ├── Showroom/              ShowroomView, ShowroomScene, ShowroomLayoutStore
│   ├── Profile/               ProfileView, UserProfileView
│   ├── Messages/              MessagesView (чат)
│   └── Onboarding/            OnboardingView
├── Models/
│   ├── NFTArtwork.swift
│   ├── Auction.swift          ⭐ minimumNextBid bug fix here
│   ├── User.swift
│   └── Collection.swift
├── Services/
│   ├── AuctionService.swift   ⭐ главный синглтон, 900+ строк
│   ├── AuctionService+DTOMapping.swift
│   ├── AuctionService+MockData.swift
│   ├── NetworkService.swift   REST клиент + APIConfig.baseURL
│   ├── WebSocketService.swift ⭐ lifecycle observation
│   ├── AuthManager.swift      JWT в Keychain
│   ├── BidQueueService.swift  offline-очередь
│   ├── ImageLoader.swift      NSCache + URL fetching
│   ├── HapticService.swift
│   ├── AnalyticsService.swift
│   ├── MetricsService.swift   ⭐ метрики времени операций
│   ├── MockDataService.swift  процедурные плейсхолдеры
│   └── PushNotificationService.swift
├── Resources/
│   ├── Assets.xcassets        Картинки, AppIcon, AccentColor
│   └── ML/                    ⭐ Depth Anything V2 mlpackage
└── Info.plist                 ATS exception для 172.20.10.2 (TON hotspot)
```

### Backend (`backend/`)

```
backend/
├── Package.swift              Swift 5.9, Vapor 4
├── Dockerfile
├── Sources/App/
│   ├── routes.swift           Регистрация контроллеров
│   ├── configure.swift
│   ├── Models/                Fluent ORM модели
│   ├── Controllers/
│   │   ├── AuthController.swift          JWT login/register
│   │   ├── ArtworkController.swift       CRUD произведений
│   │   ├── AuctionController.swift       ⭐ buy-now, auto-broker, index фильтр
│   │   ├── BidController.swift           размещение ставок
│   │   ├── NFTTokenController.swift      ⭐ /nft/mint — заменить на TON
│   │   ├── UserController.swift
│   │   ├── CollectionController.swift
│   │   ├── MessageController.swift
│   │   ├── InteractionController.swift   лайки/комменты/подписки
│   │   ├── AdminController.swift         ⭐ DELETE будет здесь
│   │   └── TransactionController.swift
│   ├── DTOs/DTOs.swift        Все Codable-структуры
│   ├── Middlewares/
│   │   ├── JWTAuthMiddleware.swift
│   │   └── AdminMiddleware.swift
│   └── WebSocketManager.swift Broadcast bidUpdate, auctionStatus, userNotification
├── docker-compose.yml         api, db, minio, pgadmin
└── database/init.sql          18 таблиц + триггеры + представления
```

### Ключевые особенности кода

1. **MVVM + Singletons** — сервисы как `AuctionService.shared`, View подписаны через `@EnvironmentObject`
2. **Combine для реактивности** — `@Published` свойства, `.sink`, `.combineLatest`
3. **DTO ↔ Domain маппинг** — изолирован в `AuctionService+DTOMapping.swift`, не смешан с бизнес-логикой
4. **Кеширование** — `NSCache` с лимитами (60 МБ для картинок, 32 МБ для depth maps)
5. **Async/await + Task.detached** — все долгие операции вне main thread
6. **MainActor** аннотации для UI-мутаций
7. **PBR-материалы** в SceneKit: `roughness`, `metalness`, `normal`, `displacement`

## Инфраструктура

### Локальная разработка

```bash
cd "/Users/alex_gorenkov/Desktop/iOS NFT-arts"
docker compose up -d
# Containers: nftarts-api (8080), nftarts-db (5432), nftarts-minio (9000/9001), nftarts-pgadmin (5050)

# IP-конфиг для физического iPhone:
# - Mac IP сейчас: 172.20.10.2 (на iPhone hotspot)
# - На обычной Wi-Fi был 192.168.1.67
# - Скрипт `scripts/set-ip.sh` обновляет IP во всех нужных файлах:
bash scripts/set-ip.sh 172.20.10.2
```

### Тестовые креды

| Назначение | Wallet | Password |
|---|---|---|
| iOS (Sancho — основной) | `1234` | `sancho123` |
| Admin macOS / iOS admin | `0xADMIN` | `admin123` |
| pgAdmin | `admin@nftarts.com` | `admin` |
| MinIO Console | `nftarts_minio` | `minio_secret_key` |

### Физическое устройство

- **iPhone 11 Pro «Sancho»**
- devicectl ID: `AD815FE5-D00D-5E02-964F-3C490B694A9B`
- Bundle ID: `com.gorenkov.NFTArts`
- Provisioning profile: `~/Library/Developer/Xcode/UserData/Provisioning Profiles/348b53f9-4573-4d6c-9040-9aafbe208ad6.mobileprovision`
- Sign identity: `"Apple Development: sgrenkov39@gmail.com (842T79LDTW)"`
- Team ID: `27LYLK4WV8`

### Команды сборки и установки

```bash
# Build
cd "/Users/alex_gorenkov/Desktop/iOS NFT-arts"
rm -rf /tmp/nftarts-build
xcodebuild \
  -project NFTArts.xcodeproj -scheme NFTArts -configuration Debug -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  SYMROOT=/tmp/nftarts-build OBJROOT=/tmp/nftarts-build/obj \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" ONLY_ACTIVE_ARCH=NO build

# Sign + Install
PROFILE=~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/348b53f9-4573-4d6c-9040-9aafbe208ad6.mobileprovision
APP=/tmp/nftarts-build/Debug-iphoneos/NFTArts.app
ENTITLEMENTS="/Users/alex_gorenkov/Desktop/iOS NFT-arts/NFTArts.entitlements"
SIGN_ID="Apple Development: sgrenkov39@gmail.com (842T79LDTW)"
cp "$PROFILE" "$APP/embedded.mobileprovision"
xattr -cr "$APP"
codesign --force --sign "$SIGN_ID" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
xcrun devicectl device install app --device AD815FE5-D00D-5E02-964F-3C490B694A9B "$APP"
```

## TON-интеграция (приоритет 1 после A4 завершения)

**ВАЖНО:** Пользователь НЕ хочет реальные деньги. Только TestNet — чтобы блокчейн был **реальный**, но монеты тестовые (бесплатные).

### План интеграции

1. **Регистрация в Tonkeeper Testnet** — пользователь уже поставил приложение
2. **Получить тестовые TON** через `@testgiver_ton_bot` в Telegram (2 TON за запрос, cooldown 6 часов)
3. **Деплой смарт-контракта NFT-collection** — стандарт TEP-62 (TON-аналог ERC-721):
   - Шаблон: https://github.com/ton-org/blueprint (`npm create ton@latest`)
   - Выбрать `nft-collection`, задеплоить через faucet wallet
   - Сохранить адрес коллекции
4. **iOS интеграция TON Connect 2.0**:
   - SDK: https://github.com/tonkeeper/wallet-api-spec
   - Deep-link с iOS на Tonkeeper для подписи
5. **Замена `NFTTokenController.mint`** на сборку payload смарт-контракта + transition через TON Connect
6. **Bid логика** — гибрид: обычные ставки на сервере (скорость), финальная purchase on-chain
7. **Balance отображение** через RPC: `runGetMethod`
8. **Deep-link кнопка** для пополнения через testgiver

### Что отвечать комиссии

«Реализована реальная интеграция с TON Testnet — блокчейн настоящий, транзакции видны в `testnet.tonscan.org`. Используются тестовые TON (без денежной ценности), что позволяет демонстрировать полный mint и transfer без финансовых рисков. Структура полностью соответствует mainnet — для перехода достаточно изменить RPC endpoint».

## Документы (уже готовы, ищи в `Показ макетов/`)

- `ИУ5-83Б_Горенков_А_А_ТЗ.docx` — техническое задание (ГОСТ 19.201-78)
- `ИУ5-83Б_Горенков_А_А_ПМИ.docx` — программа и методика испытаний
- `ИУ5-83Б_Горенков_А_А_РП.docx` — руководство пользователя (20 рисунков с скриншотами)

Эти 3 документа после новых фич нужно дополнить (см. список задач 8-11).

## Подводные камни / известные ошибки

1. **Docker VM иногда переполняется** — `docker system prune -af && docker builder prune -af` чистит ~3ГБ
2. **Локальная сеть Network Permission** — приложение требует разрешение на iOS Settings → NFT Arts → Local Network = ON, иначе нет связи с Mac на той же Wi-Fi
3. **VPN на Mac (типа Amnezia)** ломает локальную видимость — нужно выключать
4. **iOS 26.x SDK** требует установки platform runtime в Xcode Settings → Components
5. **Avatar upload field name** должен быть `file`, а не `avatar` — backend ждёт именно `file`
6. **WebSocket в background** — мы только что починили: `UIApplication.didBecomeActive` ребрасывает соединения
7. **Offline banner был убран** полностью — раньше «прилипал» после исчезновения проблемы

## Полезные референсы

- Полный план до защиты: `TODO_DIPLOMA.md` в корне проекта
- Шпаргалка на защиту: `ArtSphere_Защита_Шпаргалка.docx` / `.pdf`
- Auction quick-finalize для демо: `finishauc.md`
- Скрипт смены IP: `scripts/set-ip.sh`
- README: `README.md` (архитектурный обзор)

## Стиль работы пользователя (важно)

- **Отвечать по-русски** (быстрая коммуникация, англоязычные термины как есть)
- **Не делать билды/установки самостоятельно** — пользователь сам жмёт Cmd+R в Xcode. Это правило появилось после случая с крашами от автоматической установки
- **Длинные блоки кода → коммитить отдельно**, чтобы был чекпоинт для отката
- Любить таблицы для сравнений, code blocks для команд
- Конкретность важнее воды — пользователь не любит обтекаемые формулировки

## Что я ОБЯЗАН передать тебе перед уходом

1. **Статус последнего коммита:** `6c5ea0e` — A4 toggle + A5 heatmap overlay + A6 admin delete/timeseries. Запушено в `origin/main`. iOS type-check чистый, backend up локально (`docker compose up -d`, контейнер `nftarts-api` слушает 8080).
2. **Незавершено из блока A:** A3 auto-broker (сервер-сайд) — последняя оставшаяся задача из правок комиссии в коде iOS+backend.
3. **Следующий шаг (по приоритету):**
   - **A3 Auto-broker** — таблица `auto_broker_settings (user_id, auction_id, max_amount, created_at)`, миграция SQL. В `BidController.create` после сохранения новой ставки запрос на `auto_broker_settings` где `max_amount > new_bid.amount + auction.bidStep`, для каждого совпадения — автоматический counter-bid через тот же code path, broadcast через `WebSocketManager.shared`, персональное уведомление перебитому юзеру (`/ws/user/:userId`).
   - **B (TON блокчейн)** — самый важный пункт комиссии (см. раздел «TON-интеграция» выше).
   - **C1 Showroom themes + sharing**, потом документы.
4. **ВАЖНО — стиль работы пользователя:** «ты за меня не собирай и билдь а то багуется и приложение вылетает я сам буду ты просто говори когда» — НЕ запускай `xcodebuild` / `devicectl install` сам. Пиши код и говори юзеру «теперь Cmd+R в Xcode».
5. **TON-констрейнт пользователя:** «в тон интеграции я не хочу реальные деньги, можно просто нарисовать балик юзерам. а так чтобы блокчейн просто был реализован» — TestNet, не mainnet, без реальных денег, но смарт-контракт настоящий.

Удачи. Если что-то непонятно — `git log --oneline -30` показывает историю последних правок, и в `TODO_DIPLOMA.md` есть полный календарный план.
