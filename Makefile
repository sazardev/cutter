.DEFAULT_GOAL := setup

.PHONY: setup generate schema format format-check analyze test check run

setup:
	flutter pub get
	@test -f .env || cp .env.example .env
	dart run build_runner build
	flutter gen-l10n
	lefthook install

generate:
	dart run build_runner build
	flutter gen-l10n

# Dump the database schema and write the migration steps and their tests.
schema:
	dart run drift_dev make-migrations

format:
	dart format .

format-check:
	dart format --set-exit-if-changed .

analyze:
	flutter analyze

test:
	flutter test

check: generate format-check analyze test

run:
	flutter run --dart-define-from-file=.env
