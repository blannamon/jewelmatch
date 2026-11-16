# Структура проекта

```text
.
├── .github/workflows/ci.yml   # CI: lint, typecheck, formatting, build
├── src/                        # React-приложение
│   ├── App.tsx
│   ├── features/
│   │   └── workshops/
│   │       └── WorkshopOnboarding.tsx
│   ├── lib/
│   │   └── supabase.ts
│   ├── main.tsx
│   └── styles.css
├── supabase/
│   ├── config.toml             # локальная конфигурация Supabase CLI
│   ├── migrations/             # версионируемая схема PostgreSQL
│   └── seed.sql                # справочные данные для разработки
├── .env.example                # только публичные клиентские настройки
├── JEWELMATCH_MVP_TZ_1.0.md    # продуктовые требования
├── JEWELMATCH_ARCHITECTURE_1.0.md
├── JEWELMATCH_IMPLEMENTATION_PLAN.md
├── DESIGN_SYSTEM.md           # типографическая шкала и нормы повторяющихся элементов
└── README.md
```

Модули предметной области и таблицы будут добавляться по этапам плана. Миграции и RLS политики должны храниться в `supabase/migrations/`.

Типографические токены и правила повторяющихся элементов описаны в `DESIGN_SYSTEM.md` и заданы в `src/styles.css`.
