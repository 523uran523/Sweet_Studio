# SweetStudio

**SweetStudio** — специализированное рабочее пространство кондитера и кондитерской студии: от первого домашнего заказа до небольшой сети витрин. Приложение объединяет расчёт себестоимости рецептов, склад с партиями FEFO, производство, заказы и заявки, POS-кассу со сменами, CRM с купонами, финансы, аналитику, команду с RBAC и управлением подпиской.

**Статус:** Web Cloud Pilot реализован (этапы **A–E** + шаги **F1–F4**: вход Email/пароль и Google SSO, автосохранение черновиков форм и PWA, камера-сканер QR/штрихкодов на POS, межточечные перемещения `StockTransfer` и фильтр по точкам). Проведена проверка бизнес-логики, ролевой модели (RBAC) и адаптивности под экраны смартфонов (от `360 px`) и ПК.

---

## Основные возможности

- **Главная и Работа (`DashboardPage`, `WorkHubPage`)** — сводка поступлений/расходов/балансов за период, ближайшие выдачи, персистентный таймер работы (пишет в табель), единая проекция задач `WorkItem` (список, канбан с drag-and-drop и месячный календарь).
- **Заказы и Заявки (`OrdersAndLeadsPage`)** — воронка заявок с однократной конверсией в заказ, снимки цены и себестоимости при изменении веса, купоны, предоплаты/депозит/возвраты, списание сырья со склада, печать сметы и экспорт **PDF Счёта-сметы и Акта** (`jspdf` с поддержкой кириллицы).
- **POS-касса и смены (`PosPage`)** — открытие и закрытие кассовых смен с Z-отчётом и сверкой наличных, **фильтрация смены, витрины и чеков по активной точке**, продажа готовой продукции со склада и по рецептам со списанием по FEFO, **сканер QR-кодов и штрихкодов камерой, с фото и по Enter с USB-сканера**, автоподбор счёта под наличные/безнал, персональные купоны и возвраты по чекам.
- **Рецепты и Проф-калькулятор (`RecipesAndCalculatorPage`, `RecipeFormDrawer`)** — фотогалерея и таблица, версии рецептов, учёт упёка (`grossGrams` / `yieldGrams`), разделение съедобной массы и упаковки (`isPackaging`), фасовки/наборы (`packVariants`), вариации вкусов, матрица быстрого ввода из Кладовой, профили тарифов (труд, аренда, коммунальные, эквайринг, налоги, маржа/наценка, точка безубыточности, ROI) и массовая синхронизация цен из Кладовой.
- **Кладовая и Производство (`InventoryAndProductionPage`)** — сырьё, полуфабрикаты, упаковка и готовая продукция с **фильтрацией и перемещениями между точками (`StockTransfer`)**; партии FEFO с контролем срока годности и карантином; списание брака/просрочки; быстрая инвентаризация; закупки с оплатой со счёта или в долг поставщику; импорт CSV; проведение производственных партий по точкам без дублей на складе.
- **Клиенты, Лояльность, Качество и Продвижение (`ClientsQualityMarketingPage`)** — база клиентов со слиянием дублей, депозитами и аллергенами; одноразовые купоны с QR-кодом; жалобы с карантином партий и компенсацией; площадки продвижения, рекламные бюджеты и контент-план.
- **Финансы и Аналитика (`MoneyTeamSettingsPage`, `AnalyticsPage`)** — счета (`cash`/`card`/`bank`/`acquiring`), доходы, расходы, межакаунтовые переводы, корректное сторнирование, регулярные платежи, признанная выручка по заказам и POS-чекам, **срез и разбивка по торговым точкам**, маржа, рентабельность рецептов в час, CAC каналов и экспорт в CSV.
- **Команда, Настройки и Академия (`MoneyTeamSettingsPage`, `AcademyPage`)** — сотрудники и приглашения по email, ролевой доступ (`owner`, `admin`, `confectioner`, `seller`, `marketer`, `storekeeper`, `accountant`) с сокрытием финансовых цифр и фильтрацией рецептов, расчёт и выплата зарплаты, 4 темы **Soft Atelier** (`Berry Cream`, `Vanilla Pistachio`, `Porcelain`, `Dark Chocolate`), резервная копия/восстановление JSON и карточка подписки (`499 ₽/мес`).

---

## Технологический стек

- **Frontend:** React 19, TypeScript, Vite 8 (`vite-plugin-pwa` + Workbox), Tailwind CSS v4, Lucide Icons, `html5-qrcode`, `qrcode`, jsPDF (`Liberation Sans` TTF).
- **Backend / Auth / DB:** Firebase Authentication (Email/Password и Google SSO с поддержкой `signInWithRedirect`) и Cloud Firestore (`workspaces/{workspaceId}/...` с проверкой `email_verified`, схемы и прав в `firestore.rules` и `firebase-blueprint.json`).
- **Тестирование:** Vitest (`src/core/__tests__/`).

---

## Структура репозитория

```text
├── src/
│   ├── core/                # Чистая бизнес-логика: calculatorCore, units, payrollEngine, posCore, locations, rbac, subscription
│   │   └── __tests__/       # Модульные тесты Vitest (22 теста)
│   ├── firebase/            # Клиент Firebase, workspaceService (транзакции Firestore), seedDemo
│   ├── components/          # AppShell, UiPrimitives, QuickCreateDrawer, RecipeFormDrawer, AuthScreen, Onboarding
│   ├── pages/               # Экраны разделов (Dashboard, WorkHub, Orders/Leads, POS, Recipes/Calc, Inventory/Prod, CRM, Money/Team/Settings, Analytics, Academy)
│   ├── types/domain.ts      # Доменные модели и типы
│   └── utils/pdfExporter.ts # Генератор PDF Счёта-сметы и Акта
├── docs/                    # Документация, ТЗ, прогресс и планы доработок
├── masters_import/          # Исходные референсы и проверочные материалы (таблица «Цена торта»)
├── firestore.rules          # Правила безопасности Firestore
├── firebase-blueprint.json  # Схема коллекций Firestore
└── firebase-applet-config.json
```

---

## Запуск и развёртывание

### Локальная разработка

```bash
npm install
npm test        # Запуск unit-тестов (Vitest)
npm run lint    # Проверка типов TypeScript (tsc --noEmit)
npm run build   # Сборка production-бандла в dist/
npm run dev     # Dev-сервер на http://localhost:3000
```

### Подключение Firebase и развёртывание на своём сервере

1. Укажите конфигурацию вашего Firebase-проекта в `firebase-applet-config.json` (или используйте свой проект при деплое).
2. Разверните правила доступа: `firebase deploy --only firestore:rules`.
3. **Включите способы входа в Firebase Console:** откройте *Authentication → Sign-in method* и включите провайдеры **Google** и **Email/Password** (без включения `Email/Password` регистрация и вход по почте выдадут `auth/operation-not-allowed`).
4. **Добавьте домены приложения:** в *Authentication → Settings → Authorized domains* добавьте все домены, с которых открывается приложение (preview-домен и ваш рабочий домен), иначе появится ошибка `auth/unauthorized-domain`. Для мобильных WebView при `signInWithRedirect` учитывайте [рекомендации Firebase по redirect](https://firebase.google.com/docs/auth/web/redirect-best-practices).
5. Соберите статику (`npm run build`) и раздавайте папку `dist/` через Nginx/Caddy (с HTTPS и fallback на `index.html`) или `npx vite preview --port 3000 --host 0.0.0.0`.

---

## Документация (`docs/`)

| Документ | Назначение |
|---|---|
| [`docs/PROGRESS.md`](./docs/PROGRESS.md) | Актуальный статус всех модулей, архитектуры и выполненных этапов |
| [`docs/Remaining_Tasks.md`](./docs/Remaining_Tasks.md) | План доработок этапа **F** от простого к сложному (`F1 → F8`) и чеклист настройки Firebase |
| [`docs/ОБЩИЙ_ПЛАН_ДОРАБОТОК.md`](./docs/ОБЩИЙ_ПЛАН_ДОРАБОТОК.md) | Аудит бизнес-логики, сверка формул XLSX «Цена торта» и история этапов A–E |
| [`docs/Sweet_Studio_README.md`](./docs/Sweet_Studio_README.md) | Путеводитель по архивным спецификациям и брендингу в папке `docs/` |
| [`docs/Sweet_Studio_TZ.md`](./docs/Sweet_Studio_TZ.md) | Полное исходное ТЗ (этапы 00–16, тесты приёмки T01–T20) |
| [`docs/Sweet_Studio_Personal_Addendum.md`](./docs/Sweet_Studio_Personal_Addendum.md) | Дополнение к ТЗ по автономной редакции Personal (SQLite, EXE/APK) |
| [`docs/Sweet_Studio_reference.html`](./docs/Sweet_Studio_reference.html) | Визуальный референс интерфейса Soft Atelier |
