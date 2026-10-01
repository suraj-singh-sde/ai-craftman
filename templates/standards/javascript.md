# JavaScript / TypeScript standards (Node services)

## Layout (NestJS or Express, feature modules)
```
src/
  main.ts                         # bootstrap only
  config/                         # typed config validated at startup (zod / @nestjs/config)
  common/errors/                  # AppError hierarchy + one global error handler/filter
  common/logger/                  # pino
  modules/<resource>/
    <resource>.controller.ts      # thin: validate DTO, call service
    <resource>.service.ts         # business logic, throws domain errors
    <resource>.repository.ts      # Prisma/TypeORM/Drizzle only
    dto/                          # zod schemas or class-validator DTOs
    <resource>.module.ts          # (Nest) wiring
test/unit, test/integration (supertest)
```

## Libraries
- NestJS or Express/Fastify
- zod or class-validator
- Prisma/Drizzle/TypeORM with migrations
- multer or @fastify/multipart for uploads
- pino for logging
- undici/axios with timeouts

## Rules
- TypeScript `strict`, no `any` in public types, no floating promises (`@typescript-eslint/no-floating-promises`).
- Controllers never touch the DB. Services never import HTTP types.
- One global error filter/middleware maps domain errors to status + problem+json.
- No empty `catch`. Rethrow with `{ cause }`.
- ESLint + Prettier clean.

## Review checklist
- `eval`/`new Function`, and `innerHTML` with user data
- Unparameterized queries
- Secrets in client bundles
- React: hook deps, stable keys
