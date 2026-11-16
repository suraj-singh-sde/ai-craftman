# Java / Kotlin standards (Spring Boot)

## Layout (package by feature)
```
com.example.<service>/
  <resource>/
    <Resource>Controller   # thin, @Valid DTOs
    <Resource>Service      # business logic, throws domain exceptions
    <Resource>Repository   # Spring Data
    dto/, <Resource>Entity, <Resource>Mapper (MapStruct)
  common/error/            # exception hierarchy + @RestControllerAdvice (ProblemDetail)
  common/config/           # @ConfigurationProperties, validated
db/migration/              # Flyway
```

## Rules
- Constructor injection only. Transactions at the service layer.
- No empty catch blocks and no catching `Throwable`. Keep the cause.
- Bean Validation on DTOs. No entities in API responses.
- Spotless/Checkstyle clean. Testcontainers for integration tests.
