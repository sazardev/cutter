.DEFAULT_GOAL := setup

.PHONY: setup generate format format-check analyze test check run

setup:
	flutter pub get
	@test -f .env || cp .env.example .env
	flutter gen-l10n
	lefthook install

generate:
	flutter gen-l10n

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
