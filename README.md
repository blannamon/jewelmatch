# JewelMatch AI

Пилотная платформа для связи частных заказчиков с ювелирными мастерскими.

## Стек

- React + TypeScript + Vite
- Supabase: PostgreSQL, Auth, Storage и Realtime
- Локальная разработка базы через Supabase CLI и Docker

## Требования

- Node.js 20.19+ или 22.12+
- npm
- Docker Desktop (для локального Supabase)

## Запуск интерфейса

```sh
npm install
cp .env.example .env.local
npm run dev
```

Откройте URL, который выведет Vite (по умолчанию `http://localhost:5173`).

## Локальный Supabase

После установки зависимостей:

```sh
npm run supabase:start
npm run supabase:status
```

Локальные API URL и anon key команда `supabase status` выведет в терминал. Вставьте их в `.env.local`. Локальные ключи предназначены только для разработки. Service role key нельзя добавлять в клиентский `.env` или коммитить.

Остановить локальный стек:

```sh
npm run supabase:stop
```

Миграции хранятся в `supabase/migrations/` и должны применяться из чистой базы. Схема приложения и RLS будут добавлены отдельными миграциями после этапа инфраструктуры.

## Проверки

```sh
npm run lint
npm run typecheck
npm run format:check
npm run build
```

GitHub Actions запускает эти команды при push в `main` и для pull request.

## Переменные окружения

Скопируйте `.env.example` в `.env.local`. Все `VITE_*` переменные доступны в браузере и не должны содержать секреты.

## Требования продукта и архитектура

- [Техническое задание](./JEWELMATCH_MVP_TZ_1.0.md)
- [Архитектура](./JEWELMATCH_ARCHITECTURE_1.0.md)
- [План реализации](./JEWELMATCH_IMPLEMENTATION_PLAN.md)
