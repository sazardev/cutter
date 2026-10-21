# STACK.md: Flutter offline-first

## Summary

A Flutter app that works without a network: the local SQLite database (drift) is the source of truth for the UI, every
write goes to the database and to an **outbox** in one transaction, and a sync engine pushes the outbox and pulls
changes when the device is online (foreground and background). Conflicts are resolved by an explicit, documented policy.
The UI never waits on the network: it watches database queries and shows each record's sync status.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ | Sealed classes and patterns for sync states |
| Framework | Flutter (stable channel) | One codebase for Android and iOS |
| Local database | `drift` (SQLite) + `drift_flutter` | Typed queries, reactive `watch()` streams, migrations |
| Sync | Own sync engine: outbox table + pull by cursor (`updated_at`/version) | Predictable, testable, no vendor lock-in |
| Background work | `workmanager` (Android WorkManager / iOS BGTaskScheduler) | Sync when the app is closed, OS-scheduled |
| Connectivity | `connectivity_plus` (a hint) + real request outcome (the truth) | "Connected" does not mean "reachable" |
| HTTP | `dio` with timeouts and retry interceptor | Cancellation, backoff |
| IDs | Client-generated UUID v7 (`uuid`) | Records exist before the server knows them; time-ordered |
| State | `flutter_riverpod` + `riverpod_generator` | StreamProviders over drift queries |
| Models | `freezed` + `json_serializable` | Immutable entities and sync DTOs |
| Lint | `very_good_analysis` | Strict analysis |
| Testing | `flutter_test`, drift in-memory database, `mocktail`, `fake_async` | Sync tested deterministically |
| Deploy | Store builds per flavor | See the deploy add-on for the pipeline |
| Database | SQLite (one file, WAL mode, `foreign_keys=ON`, versioned migrations) | Zero operations: no server, trivial backups, fast for one writer |
| Internationalization | Flutter `gen-l10n` (ARB files in `lib/l10n/`, generated `AppLocalizations`, `intl`) | Official, typed, compile-time checked translations |
| CI | GitHub Actions (`.github/workflows/ci.yml`) on every pull request and push to `main` | Runs the same quality gates as local, next to the code review |
| Hooks | Lefthook (`lefthook.yml`): pre-commit format + lint on staged files, commit-msg Conventional Commits check | Problems caught before they reach CI, in parallel and in milliseconds |
| Updates | Renovate (`renovate.json`): grouped weekly updates, automerge for patch and lockfile maintenance | Dependencies stay current in small, reviewable steps |

## Project layout

```
lib/
  main.dart                                 opens the database, registers background sync, ProviderScope
  app/                                      app.dart, router.dart, theme/
  core/
    db/
      app_database.dart                     @DriftDatabase: tables + DAOs + migration strategy
      migrations/                           one step per schema version (from1To2.dart…)
      tables/outbox_table.dart              id, entity, entity_id, operation, payload, attempts, last_error, created_at
      tables/sync_state_table.dart          per-entity pull cursor
    sync/
      sync_engine.dart                      push outbox → pull changes → apply; one run at a time (lock)
      push_outbox.dart                      sends pending operations in order, marks done/failed
      pull_changes.dart                     fetches since cursor, applies in one transaction
      conflict_policy.dart                  the rule (e.g. server wins for fields X, last-write-wins for Y)
      background_sync.dart                  workmanager callback → SyncEngine.run()
      sync_status.dart                      sealed: synced | pending | failed(error)
    network/api_client.dart                 dio + interceptors
  features/
    visits/
      domain/visit.dart                     entity with syncStatus
      domain/visits_repository.dart         interface: watchAll(), save(), delete()
      data/visits_table.dart                drift table (id UUID, fields, updated_at, deleted flag)
      data/visits_dao.dart                  queries + watch streams
      data/local_visits_repository.dart     writes row + outbox entry in ONE transaction
      data/visit_sync_adapter.dart          entity ↔ API payload, apply remote change
      presentation/visits_controller.dart
      presentation/visits_page.dart         shows per-row sync badge
test/
```

Dependency direction: `presentation → domain ← data`; `core/sync` depends on per-feature sync adapters through an
interface, never on presentation. The UI reads ONLY the local database; only `core/sync` talks to the API.

```
migrations/                    numbered, forward-only SQL migrations
data/app.db                    the database file (git-ignored; with its -wal and -shm files)
```

```
l10n.yaml                      arb-dir: lib/l10n, template-arb-file: app_en.arb, output-localization-file: app_localizations.dart
lib/l10n/app_en.arb            the template: keys, text, @key descriptions and placeholders
lib/l10n/app_<lng>.arb         one ARB per language (app_es.arb, app_pt.arb)
```

```
.github/workflows/ci.yml       jobs: lint (format + lint + typecheck), test, build; dependency cache; concurrency per branch
```

```
lefthook.yml                   pre-commit: format + lint ({staged_files}); commit-msg: conventional commit check
```

```
renovate.json                  extends config:recommended; schedule; packageRules: groups, automerge patch
```

## Conventions

- Every write = local row change + outbox entry in one drift transaction; nothing writes to the API directly from a feature.
- Deletes are soft (`deleted` flag) until the server confirms; then the row is purged.
- Every synced table has `id` (client UUID v7), `updated_at` (server time when known) and `version` or equivalent for conflict detection.
- The conflict policy is written in `conflict_policy.dart` and in this file; changing it is a reviewed decision.
- Push is idempotent: the server accepts the same operation id twice without duplicating effects.
- Retries use exponential backoff with jitter; after N failures the item is `failed` and visible to the user, never silently dropped.
- Schema changes bump `schemaVersion` with a migration step and a migration test.
- Path from configuration (`DATABASE_PATH`); the directory is a persistent volume in containers.
- On every connection: `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=ON`, `PRAGMA busy_timeout=5000`.
- One writer at a time: keep write transactions short and never hold one across a network call.
- Types are loose: add `CHECK` constraints and `STRICT` tables where the driver supports them.
- Back up with `sqlite3 data/app.db ".backup out.db"`, never by copying a live file.
- `flutter: generate: true` in `pubspec.yaml`; `flutter_localizations` and `intl` are dependencies.
- `app_en.arb` is the template; every key has an `@key` entry with a `description` and typed `placeholders`.
- Strings are read with `AppLocalizations.of(context)!.<key>` (or `context.l10n` through an extension); no literal text in widgets.
- Plurals and selects use ICU syntax in the ARB (`{count, plural, =0{No items} one{1 item} other{{count} items}}`).
- Dates and numbers use `DateFormat` / `NumberFormat` with the current locale; placeholders declare `format`.
- `supportedLocales` and `localizationsDelegates` come from `AppLocalizations`; the app reacts to the system locale.
- Generated files in `.dart_tool` or `lib/l10n/app_localizations*.dart` are never edited by hand.
- CI runs exactly the commands in the Commands table; no CI-only scripts.
- Third-party actions are pinned to a full commit SHA; `permissions:` default to `contents: read`.
- `concurrency` cancels superseded runs on the same branch; `main` is protected and requires a green CI.
- Hooks run only the fast checks on staged files; tests stay in CI.
- Hooks run the same commands as the Commands table.
- Related packages update together (framework + its plugins, test tooling, linters).
- Patch updates and lockfile maintenance automerge only when CI is green; minor/major are reviewed.
- A major update gets its own pull request with the migration notes linked.

## Commands

| Task | Command |
| --- | --- |
| Install hooks | `lefthook install` |
| Generate l10n | `flutter gen-l10n` |
| Dump schema | `dart run drift_dev make-migrations` |
| Run | `flutter run` |
| Test | `flutter test` |
| Lint | `flutter analyze` |
| Format | `dart format .` |
| Shell | `sqlite3 data/app.db` |
| Backup | `sqlite3 data/app.db ".backup backup.db"` |

## Testing

- Repositories against an in-memory drift database (`NativeDatabase.memory()`): a save creates the row AND the outbox entry.
- Sync engine with a fake API: push order, idempotent retries, backoff (`fake_async`), partial failure, conflict cases from `conflict_policy.dart`.
- Migration tests for every schema version (drift's generated schema verifier).
- A "kill mid-sync" test: interrupting between push and pull leaves the database consistent.
- Widget tests show the right sync badge for synced, pending and failed rows.
- Tests use a temporary file or `:memory:` with the real migrations applied, so schema and constraints are the production ones.
- Widget tests pump the app with `AppLocalizations.delegate` and a test locale; a golden or finder per language catches overflow.

## Quality gates

- `flutter analyze` zero issues; `dart format --set-exit-if-changed .`.
- `flutter test` passes, including migration and sync tests; generated code and drift schema dumps are up to date.

## Dependencies

- Allowed: the table above. A sync framework (PowerSync, Brick, ElectricSQL) only by an explicit decision that replaces `core/sync`.
- Do NOT use: `shared_preferences` or files as a data store, `hive`/`isar` next to drift, direct API calls from features, server-generated IDs for records created offline.

## Rules for agents

- Never call the API from a feature or a widget: write to the local database; `core/sync` does the rest.
- Every local write and its outbox entry happen in the same transaction.
- Never block the UI on the network; screens watch drift queries.
- Never change a synced table without a migration step and its test.
- Every new synced entity gets a sync adapter, a conflict rule and tests for push, pull and conflict.
- Sync runs are serialized (one at a time) and safe to interrupt at any point.
- Show sync status per record; failed items offer retry, they are never discarded silently.
- Use client-generated UUID v7 for new records; never auto-increment IDs for synced tables.
- Never commit the `.db`, `-wal` or `-shm` files; add them to `.gitignore`.
- Never open the same database from several processes that write heavily; if that is needed, say so and propose PostgreSQL.
- Always bind parameters; never concatenate user input into SQL.
- Never hardcode a visible string; add the key to `app_en.arb` and every other ARB, then run `flutter gen-l10n`.
- Never edit generated `AppLocalizations` files.
- Never concatenate localized fragments; use placeholders.
- Never weaken or skip a CI step to make a change pass.
- A new quality gate is added to the Commands table and to `ci.yml` in the same change.
- Never put secrets in workflow files; use repository or environment secrets.
- Never bypass hooks with `--no-verify`.
- Commit messages follow Conventional Commits (`feat(scope): …`, `fix(scope): …`).
- Never pin a dependency to an old version to silence Renovate without a comment saying why.
- Never mix a dependency update with feature changes in one commit.

## Engineering principles

Rules, not suggestions: every change follows them, and a review checks them. When one has to be broken, say so in the change and why.

### Accessibility

- **WCAG 2.2 AA** is the minimum bar for every screen, not a later phase.
- **Semantic elements first**: `button` for actions, `a` for navigation, headings in order, lists, landmarks; ARIA only when no native element fits.
- **Keyboard**: everything works with the keyboard alone, in a logical tab order, with no traps; custom widgets follow the ARIA Authoring Practices patterns.
- **Visible focus** on every interactive element (never `outline: none` without a replacement); focus moves into dialogs and returns on close.
- **Labels**: every input has a visible label; icon-only buttons have an accessible name; images have alt text (empty for decorative ones).
- **Contrast**: text ≥ 4.5:1 (large text ≥ 3:1), UI components and focus indicators ≥ 3:1; color is never the only signal.
- **Targets** at least 24×24 CSS px (44×44 on touch); content reflows at 320px width and 200% zoom.
- **Motion**: respect `prefers-reduced-motion`; nothing flashes more than 3 times per second; auto-playing content can be paused.
- **Errors** are announced, described in text and tied to their field (`aria-describedby`).
- Review check: axe (or equivalent) reports no violations, the flow was done with keyboard only, and a screen reader announces the new UI meaningfully.

### Clean Architecture

- **Four rings**: entities (enterprise rules) → use cases (application rules) → interface adapters (controllers, presenters, gateways) → frameworks and drivers.
- **Dependency rule**: source code dependencies point inward only; an inner ring never names anything declared in an outer one.
- **One use case per file/class**, named as an action (`PlaceOrder`, `CancelSubscription`), with its own input and output models.
- **DTOs at boundaries**: data crossing a ring is a plain structure defined by the inner ring; entities never leak to controllers, views or the database layer.
- **Gateways are interfaces** declared by use cases and implemented in the adapters ring.
- **Presenters format output** for the delivery mechanism; use cases return data, never HTTP status codes, HTML or JSON.
- **Frameworks are details**: they are plugged in at the outer ring and could be replaced without touching use cases or entities.
- Review check: every new use case has its own file, input/output types and a unit test with fake gateways; no inner file imports an outer package.

### Clean Code

- **Names** reveal intent: a reader knows what a variable holds or a function does without reading its body; no abbreviations, no `data`, `info`, `tmp`, `manager`, `helper`.
- **Small functions**: one thing, one level of abstraction; ~30 lines is a smell, ~60 is a split. At most 3-4 parameters; more becomes an options/params type.
- **Guard clauses**: handle invalid cases first and return early; nesting deeper than 3 levels is refactored.
- **No surprises**: a function named like a query does not mutate; side effects are visible in the name (`save`, `send`, `delete`).
- **No magic values**: numbers and strings with meaning become named constants or configuration.
- **Comments explain why**, never what: the code says what. No commented-out code, no journal comments, no stale TODOs.
- **DRY with judgment**: remove duplicated knowledge, not similar-looking code; wait for the third occurrence before abstracting.
- **Boolean flags** that switch a function's behaviour become two functions.
- Review check: every new name reads as a sentence in its call site; no function in the diff exceeds the limits above without a reason in the change.

### Error handling

- **Never swallow**: every error is handled, returned or logged-and-escalated exactly once; empty catch blocks and ignored results are bugs.
- **Wrap with context**: add what was being done (`load order 42: …`) while keeping the original cause inspectable (wrapping, `cause`).
- **Domain errors are types/values** (`ErrOrderNotFound`, `InsufficientFunds`) declared in the core; infrastructure errors stay in adapters and are translated.
- **Map at the boundary, once**: one place turns errors into HTTP status, exit codes or UI messages; no status codes inside business logic.
- **Fail fast at startup**: missing or invalid configuration stops the process with a clear message instead of failing on first use.
- **No exceptions/panics for control flow**: expected outcomes (not found, invalid input) are values; panics only for programmer errors.
- **User-safe messages**: users see what happened and what to do; stack traces, SQL and internal ids go only to logs.
- **Log where handled**, not at every layer: one log entry per failure, with its context and correlation id.
- **Retries** only for transient errors, with backoff, jitter and a limit; never retry non-idempotent operations blindly.
- Review check: no new code path drops an error; every new error type is mapped at the boundary.

### Hexagonal architecture

- **The core** (domain + application) contains business rules and knows nothing about HTTP, databases, queues, frameworks, ORMs or the UI.
- **Ports are owned by the core**: interfaces declared where they are used (`OrderRepository`, `PaymentGateway`, `Clock`), named in business terms, never after a technology.
- **Adapters live at the edge**: driving adapters (HTTP handlers, CLI, consumers) call use cases; driven adapters (Postgres, Stripe, SMTP) implement ports.
- **Dependency rule**: adapters → application → domain. The core never imports an adapter, a driver or a framework package.
- **No framework types in the core**: no request/response objects, ORM entities, annotations or SDK types cross into it; adapters map to and from core types.
- **One composition root** (`main`/bootstrap) wires concrete adapters into the core; nothing else instantiates infrastructure.
- **Tests through ports**: use cases are tested with in-memory fakes of their ports; adapters get their own integration tests against the real technology.
- Review check: grep the core for driver, framework and SDK imports: there are none; every new adapter implements a port declared in the core.

### Observability

- **Structured logs** (JSON in production) with level, message, timestamp and context fields; never interpolate values into the message string.
- **Correlation**: every request/job carries a request id / trace id that appears in all its logs and is propagated to downstream calls.
- **Levels mean something**: error = someone must act, warn = degraded but handled, info = business-relevant events, debug off in production.
- **Metrics**: RED (rate, errors, duration) for every endpoint and consumer, USE (utilization, saturation, errors) for resources and pools.
- **Traces** with OpenTelemetry for requests that cross services, databases or queues; spans named after operations, not URLs with ids.
- **Health endpoints**: liveness (process alive) and readiness (dependencies reachable) are separate and cheap.
- **Alerts are actionable**: on symptoms users feel (error rate, latency SLOs), each with a runbook link; no alerts nobody acts on.
- **Cardinality control**: no user ids, emails or raw URLs as metric labels.
- Review check: a new feature's failure would show up in logs, metrics and traces with enough context to diagnose it without a debugger.

### One file, one responsibility

- **One file = one responsibility**: one entity, one use case, one handler group, one component. If its description needs "and", it is two files.
- **Size limits**: ~300 lines is a soft limit, ~500 a hard one; a file over it is split by responsibility, not by line count.
- **Folders by feature**, not by technical type: `orders/` holds its entity, use cases, adapters and tests; shared kernels stay small and explicit.
- **Explicit public surface**: each module exposes a small API (index/exports/package-level types); everything else is private and may change freely.
- **No dumping grounds**: no `utils`, `helpers`, `common`, `misc` files; a helper lives next to its only user or in a module named for what it does.
- **High cohesion, low coupling**: things that change together live together; modules talk through interfaces or events, never through each other's internals.
- **Replaceable modules**: deleting or swapping a module touches its folder and the composition root, nothing else.
- **No cycles**: module dependencies form a DAG; a cycle is broken by extracting the shared concept or inverting a dependency.
- Review check: each new file can be described in one sentence; no import reaches into another module's private files.

### Performance

- **Measure first**: optimize only with a profile, benchmark or production metric that shows the problem; record the before and after numbers.
- **Budgets**: explicit targets (p95 latency per endpoint, bundle size, startup time, memory) checked in CI or monitoring.
- **No N+1**: data for a list is loaded in one query or a batch (joins, `IN`, dataloaders); queries inside loops are bugs.
- **Bounded work**: every list is paginated, large payloads are streamed, unbounded reads (whole tables, whole files) are not allowed.
- **Indexes** match the queries; every new query is checked with its plan on realistic data.
- **Caching** has an owner, a key, a TTL and an invalidation strategy; never cache without knowing how it becomes stale.
- **Timeouts everywhere**: every network call, query and lock has a timeout and cancellation propagates (context, abort signals).
- **Async for slow work**: emails, reports and third-party calls that the user need not wait for go to a queue.
- **No premature optimization**: clear code first; micro-optimizations need a measurement that justifies the lost readability.
- Review check: no new query in a loop, no unbounded list, no network call without a timeout.

### Security

- **Validate at every boundary**: input from users, APIs, files and queues is parsed into typed values with allowlists, size and range limits; reject, never sanitize-and-hope.
- **Injection**: parameterized queries and safe APIs only; never build SQL, shell commands, paths or HTML by string concatenation with input.
- **Authorization on every request**: check that this user may do this action on this resource (object-level), server-side, deny by default.
- **Authentication**: proven libraries, hashed passwords (argon2id/bcrypt), short-lived tokens, secure cookies (`HttpOnly`, `Secure`, `SameSite`), CSRF protection for cookie sessions.
- **Secrets** never in code, logs, URLs or the repository; they come from the environment or a secret manager and are rotatable.
- **Least privilege**: database users, service accounts, tokens and containers get only the permissions they need.
- **Output encoding** by context (HTML, attribute, URL, JS); security headers (CSP, HSTS) on web apps.
- **No PII or secrets in logs**; personal data is minimized, encrypted in transit (TLS) and at rest where required.
- **Dependencies** are pinned and scanned (Dependabot, `npm audit`, `govulncheck`, `cargo audit`); known-vulnerable versions block the build.
- Review check: every new endpoint has an authorization check and input validation; no new string-built query or command.

### SOLID

- **Single responsibility**: a module, type or function has one reason to change. If describing it needs "and", split it.
- **Open/closed**: add behaviour by adding code (a new implementation, a new strategy, a new handler), not by growing `switch`/`if` chains in existing code.
- **Liskov substitution**: every implementation of an interface honours its full contract (inputs, outputs, errors, side effects); no implementation panics or ignores a method it "does not support".
- **Interface segregation**: interfaces are small and owned by the consumer; a consumer never depends on methods it does not call.
- **Dependency inversion**: business code depends on interfaces it defines; concrete adapters (DB, HTTP, queues, clocks, random) are injected from the composition root.
- Review check: no constructor creates its own infrastructure; no type takes more than ~5 dependencies (a sign it does too much).

### Testing

- **Pyramid**: many fast unit tests, fewer integration tests against real dependencies (containers), a few end-to-end tests of critical flows.
- **Test behaviour, not implementation**: assert on outputs and observable effects through public APIs; refactoring must not break tests.
- **Arrange, Act, Assert**: one behaviour per test, named after it (`rejects_order_without_items`); table-driven for variations.
- **Deterministic**: no `sleep`, no real clock, randomness or network in unit tests; inject clocks, id generators and seeds.
- **Fakes over mocks** for ports you own (in-memory repository); mocks only to assert interactions that are the behaviour (an email was sent).
- **Isolated**: tests do not depend on order or shared state; each creates its data and cleans up (transactions rolled back, temp dirs).
- **Every bug gets a regression test** that fails before the fix and passes after it.
- **Coverage is a signal, not a target**: uncovered critical paths matter; chasing a percentage with trivial tests does not.
- Review check: every changed behaviour has a test in the same change; the suite passes repeatedly and in parallel.
