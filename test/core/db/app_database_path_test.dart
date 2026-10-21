import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the database file of the configuration', () {
    test('an absolute path is used as it is', () {
      final file = resolveDatabaseFile('/var/lib/cutter/app.db', '/documents');

      expect(file.path, '/var/lib/cutter/app.db');
    });

    test('a relative path resolves against the documents directory', () {
      final file = resolveDatabaseFile('data/app.db', '/documents');

      expect(
        file.path,
        '/documents${Platform.pathSeparator}data/app.db',
      );
    });

    test('a relative path in the documents directory stays there', () {
      final file = resolveDatabaseFile('cutter.sqlite', '/documents');

      expect(
        file.path,
        '/documents${Platform.pathSeparator}cutter.sqlite',
      );
    });
  });
}
