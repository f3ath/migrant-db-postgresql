import 'dart:io';

import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';
import 'package:migrant_source_fs/migrant_source_fs.dart';
import 'package:postgres/postgres.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

/// To run locally, start postgres:
/// `docker run -d -p 5432:5432 --name my-postgres -e POSTGRES_PASSWORD=postgres postgres`
void main() {
  test('Can apply migrations', () async {
    final source = LocalDirectory(
        Directory('test/migrations'), FileNameFormat(RegExp(r'\d{2}')));
    final connection = _createConnection();

    final gateway = PostgreSQLGateway(connection);
    await connection.open();
    await gateway.dropMigrations();
    await connection.transaction((ctx) async {
      await ctx.query("drop table if exists test");
    });
    final db = Database(gateway);
    await db.migrate(source);
    expect(await gateway.currentVersion(), equals('02'));
    await db.migrate(source); // idempotency
    expect(await gateway.currentVersion(), equals('02'));
    await connection.transaction((ctx) async {
      await ctx.query(
          "insert into test (id, foo, bar) values (@id, @foo, @bar)",
          substitutionValues: {
            'id': '0000',
            'foo': 'hello',
            'bar': 'world',
          });
    });
    final result = await connection.query('select * from test');
    expect(
        result,
        equals([
          ['0000', 'hello', 'world']
        ]));
  });

  test('Invalid migrations', () async {
    final connection = _createConnection();

    final gateway = PostgreSQLGateway(connection);
    await connection.open();
    await gateway.dropMigrations();
    await connection.transaction((ctx) async {
      await ctx.query("drop table if exists test");
    });
    final db = Database(gateway);
    expect(
        () => db.migrate(
            TestMigrationSource([Migration('00', 'drop table not_exists;')])),
        throwsA(isA<PostgreSQLException>()));
    expect(await gateway.currentVersion(), isNull);
    await db.migrate(
        TestMigrationSource([Migration('00', 'create table test (id text);')]));
    expect(await gateway.currentVersion(), equals('00'));
    expect(
        () => db.migrate(
            TestMigrationSource([Migration('01', 'drop table not_exists;')])),
        throwsA(isA<PostgreSQLException>()));
    expect(await gateway.currentVersion(), equals('00'));
  });
}

PostgreSQLConnection _createConnection() {
  final env = Platform.environment;
  return PostgreSQLConnection(
      env['PG_HOST'] ?? 'localhost',
      int.fromEnvironment('PG_PORT', defaultValue: 5432),
      env['PG_DATABASE'] ?? 'postgres',
      username: env['PG_USER'] ?? 'postgres',
      password: env['PG_PASSWORD'] ?? 'postgres');
}
