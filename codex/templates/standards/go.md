# Go standards

## Layout
```
cmd/<service>/main.go            # wiring only
internal/config/                 # env config, validated
internal/domain/                 # entities + sentinel errors (ErrNotFound, ErrConflict)
internal/service/                # business logic, returns domain errors
internal/repository/             # sqlc/pgx or database/sql
internal/transport/http/         # handlers, router (chi or net/http mux), error mapping
internal/adapters/               # storage, external clients (interfaces declared by the consumer)
migrations/                      # goose/migrate
```

## Rules
- Wrap errors with `%w` and context. Map them with `errors.Is`/`errors.As` only in the transport layer.
- `context.Context` is the first parameter on every IO path, with timeouts set.
- No goroutine leaks. `go test -race` is clean. `golangci-lint` is clean.
- `defer` a close only after the error check.
