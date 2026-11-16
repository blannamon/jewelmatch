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
Dev-сервер следит за файлами через polling, чтобы видеть правки из IDE. Если порт занят, Vite завершится с ошибкой вместо запуска второй копии на другом порту; остановите прежний процесс и повторите `npm run dev`.

## Локальный Supabase

После установки зависимостей:

```sh
npm run supabase:start
npm run supabase:status
```

Локальные API URL и Publishable key команда `supabase status` выведет в терминал. Вставьте их в `.env.local`. Локальные ключи предназначены только для разработки. Secret key нельзя добавлять в клиентский `.env` или коммитить.

Остановить локальный стек:

```sh
npm run supabase:stop
```

Миграции хранятся в `supabase/migrations/`. После запуска локального стека применить их с нуля вместе с seed-данными можно командой:

```sh
npx supabase db reset
```

Без флага `--remote` команда работает с локальной базой. Она пересоздаёт локальную базу, поэтому локальные данные будут удалены.

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

## Вход и роли

- Регистрация и вход используют email и пароль. При регистрации email подтверждается ссылкой; локальные шаблоны писем находятся в `supabase/templates/`.
- В локальной разработке письма доступны в Mailpit на `http://127.0.0.1:54324`.
- Экран входа позволяет запросить сброс пароля; ссылка восстановления открывает форму нового пароля.
- При первом входе пользователь выбирает роль. Приложение сохраняет её через `choose_app_role`; повторный выбор другой роли база отклоняет.
- После выбора роли мастерской приложение просит заполнить публичное название, город, телефон, специализации и территорию работы. Дополнительное описание и контакты можно добавить сразу или позже.
- Telegram-кнопка включается только после настройки OIDC-провайдера `custom:telegram` в Supabase Auth и установки `VITE_SUPABASE_TELEGRAM_ENABLED=true`. Не храните ключи провайдера в `VITE_*` переменных.
- Для Supabase Cloud укажите URL проекта и публичный Publishable key в локальном `.env.local`, добавьте URL приложения в Auth redirect URLs, включите подтверждение email и настройте письма Confirmation и Password Recovery.
- Установите минимальную длину пароля 8 символов в настройках Supabase Auth; в локальном проекте это задаёт `minimum_password_length` в `supabase/config.toml`.
- После изменений `supabase/config.toml` перезапустите локальный стек командами `npm run supabase:stop` и `npm run supabase:start`.

## Требования продукта и архитектура

- [Техническое задание](./JEWELMATCH_MVP_TZ_1.0.md)
- [Архитектура](./JEWELMATCH_ARCHITECTURE_1.0.md)
- [План реализации](./JEWELMATCH_IMPLEMENTATION_PLAN.md)
