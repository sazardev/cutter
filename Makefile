.DEFAULT_GOAL := setup

.PHONY: setup generate bridge schema format format-check analyze test rust-test check run build-apk

setup:
	flutter pub get
	@test -f .env || cp .env.example .env
	dart run build_runner build
	flutter gen-l10n
	lefthook install

generate:
	dart run build_runner build
	flutter gen-l10n

# Regenerate the Dart bindings of the Rust engine (rust/src/api) with
# flutter_rust_bridge_codegen 2.13.0 (`cargo install flutter_rust_bridge_codegen --version 2.13.0`).
bridge:
	flutter_rust_bridge_codegen generate

# The engine's own tests; they make their fixtures with the ffmpeg CLI.
rust-test:
	cd rust && cargo clippy -- -D warnings && cargo test

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

check: generate format-check analyze test rust-test

run:
	flutter run --dart-define-from-file=.env

# The database path and the rest of the configuration come from .env, so the
# build carries them too.
build-apk:
	flutter build apk --dart-define-from-file=.env
