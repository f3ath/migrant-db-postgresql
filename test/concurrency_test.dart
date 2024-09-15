import 'dart:io';
import 'dart:math';

import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// To run locally, start postgres:
/// `docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres`
void main() {
  const schema = 'concurrency_test';
  group('Concurrency', () {
    setUp(() async {
      final connection = await _createConnection();
      await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE;');
      await connection.execute('CREATE SCHEMA IF NOT EXISTS $schema;');
      await connection.close();
    });

    test('Migrate concurrently', () async {
      final migrations = [
        Migration('0000', [
          'CREATE TABLE $schema.test (id TEXT PRIMARY KEY);',
          'ALTER TABLE $schema.test ADD COLUMN foo0 TEXT;',
        ])
      ];

      for (var i = 1; i <= 100; i++) {
        migrations.add(Migration(i.toString().padLeft(4, '0'), [
          'ALTER TABLE $schema.test ADD COLUMN foo$i TEXT;',
          'SELECT PG_SLEEP(0.001);',
          'ALTER TABLE $schema.test DROP COLUMN foo${i - 1};',
        ]));
      }

      final futures = <Future>[];
      for (var i = 0; i < 100; i++) {
        futures.add(() async {
          final connection = await _createConnection();
          final gateway = PostgreSQLGateway(connection, schema: schema);
          final db = Database(gateway);
          while (true) {
            try {
              await db.upgrade(InMemory(migrations));
              break;
            } on RaceCondition {
              await Future.delayed(
                  Duration(milliseconds: Random().nextInt(100)));
            }
          }
          await connection.close();
        }());
      }

      await Future.wait(futures);

      final connection = await _createConnection();
      final gateway = PostgreSQLGateway(connection, schema: schema);
      final version = await gateway.currentVersion();
      await connection.close();

      expect(version, equals('0100'));
    });
  });
}

Future<Connection> _createConnection() {
  final env = Platform.environment;
  return Connection.open(
      Endpoint(
        host: env['PG_HOST'] ?? 'localhost',
        port: int.fromEnvironment('PG_PORT', defaultValue: 5432),
        database: env['PG_DATABASE'] ?? 'postgres',
        username: env['PG_USER'] ?? 'postgres',
        password: env['PG_PASSWORD'] ?? 'postgres',
      ),
      settings: ConnectionSettings(sslMode: SslMode.disable));
}
