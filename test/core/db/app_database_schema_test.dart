import 'dart:convert';
import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// The schema dump drift writes, next to the database it describes.
/// Regenerate it with `dart run drift_dev make-migrations`.
File _schemaDump() => File('lib/core/db/schema/cutter/drift_schema_v1.json');

/// One column of the dumped schema.
class _DumpColumn {
  const _DumpColumn({
    required this.name,
    required this.moorType,
    required this.nullable,
    required this.hasCheck,
  });

  final String name;
  final String moorType;
  final bool nullable;
  final bool hasCheck;
}

/// One table of the dumped schema.
class _DumpTable {
  const _DumpTable({required this.name, required this.columns});

  final String name;
  final List<_DumpColumn> columns;
}

List<_DumpTable> _dumpTables() {
  final dump =
      jsonDecode(_schemaDump().readAsStringSync()) as Map<String, dynamic>;
  final entities = dump['entities']! as List<dynamic>;

  return [
    for (final entity in entities)
      _DumpTable(
        name: _entity(entity)['name'] as String,
        columns: [
          for (final column in _entity(entity)['columns']! as List<dynamic>)
            _DumpColumn(
              name: _column(column)['name'] as String,
              moorType: _column(column)['moor_type'] as String,
              nullable: _column(column)['nullable'] as bool,
              hasCheck: (_column(column)['dsl_features']! as List<dynamic>)
                  .isNotEmpty,
            ),
        ],
      ),
  ];
}

/// The payload of one dumped entity.
Map<String, dynamic> _entity(Object? entity) =>
    (entity! as Map<String, dynamic>)['data']! as Map<String, dynamic>;

/// The payload of one dumped column.
Map<String, dynamic> _column(Object? column) => column! as Map<String, dynamic>;

/// The SQL type SQLite uses for a column of the given drift type.
String _sqlType(String moorType) => switch (moorType) {
      'int' || 'bool' => 'INTEGER',
      'double' => 'REAL',
      _ => 'TEXT',
    };

/// One table of the live database: the SQL that created it and its columns.
class _LiveTable {
  const _LiveTable({required this.sql, required this.columns});

  final String sql;
  final Map<String, Map<String, Object?>> columns;
}

Future<Map<String, _LiveTable>> _liveTables(AppDatabase database) async {
  final tables = <String, _LiveTable>{};

  final rows = await database
      .customSelect("SELECT name, sql FROM sqlite_master WHERE type = 'table'")
      .get();
  for (final row in rows) {
    final name = row.read<String>('name');
    final columns =
        await database.customSelect('PRAGMA table_info($name)').get();
    tables[name] = _LiveTable(
      sql: row.read<String>('sql'),
      columns: {
        for (final column in columns)
          column.read<String>('name'): {
            'type': column.read<String>('type'),
            'notnull': column.read<int>('notnull') == 1,
          },
      },
    );
  }
  return tables;
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() => database.close());

  test('the tables of the dump are the tables of the database', () async {
    final live = await _liveTables(database);

    expect(
      live.keys.toSet(),
      {for (final table in _dumpTables()) table.name},
    );
  });

  test('every dumped column exists with the same type and nullability',
      () async {
    final live = await _liveTables(database);

    for (final table in _dumpTables()) {
      expect(
        live[table.name]!.columns.keys.toSet(),
        {for (final column in table.columns) column.name},
        reason: '${table.name} does not have the columns of the dump',
      );

      for (final column in table.columns) {
        final liveColumn = live[table.name]!.columns[column.name]!;

        expect(
          liveColumn['type'],
          _sqlType(column.moorType),
          reason: '${table.name}.${column.name} has the wrong type',
        );
        expect(
          liveColumn['notnull'],
          !column.nullable,
          reason: '${table.name}.${column.name} has the wrong nullability',
        );
      }
    }
  });

  test('every checked column of the dump is checked in the database', () async {
    final live = await _liveTables(database);

    for (final table in _dumpTables()) {
      // Drift adds a check of its own for every boolean column, on top of
      // the ones the table declares.
      final checked = table.columns.where((column) => column.hasCheck).length;
      final booleans =
          table.columns.where((column) => column.moorType == 'bool').length;

      expect(
        'CHECK'.allMatches(live[table.name]!.sql).length,
        checked + booleans,
        reason: '${table.name} does not carry the checks of the dump',
      );
    }
  });
}
