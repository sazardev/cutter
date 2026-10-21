import 'package:drift/drift.dart';

// Drift column getters are declarative.
// ignore_for_file: public_member_api_docs

/// A device-level setting stored as text under a unique key (for example
/// whether the onboarding was seen).
@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
