import 'dart:io';

import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';
import 'package:postgres/postgres.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

/// To run locally, start postgres:
/// `docker run -d -p 5432:5432 --name my-postgres -e POSTGRES_PASSWORD=postgres postgres`
void main() {
  test('Can apply migrations', () async {
    final source = InMemory({
      '00': 'create table test (id text not null);',
      '01': 'alter table test add column foo text;',
      '02': 'alter table test add column bar text;'
    });
    final connection = await _createConnection();

    final gateway = PostgreSQLGateway(connection);
    await gateway.dropMigrations();
    await connection.execute("drop table if exists test");
    final db = Database(gateway);
    await db.migrate(source);
    expect(await gateway.currentVersion(), equals('02'));
    await db.migrate(source); // idempotency
    expect(await gateway.currentVersion(), equals('02'));
    await connection.execute(
        Sql.named('insert into test (id, foo, bar) values (@id, @foo, @bar)'),
        parameters: {
          'id': '0000',
          'foo': 'hello',
          'bar': 'world',
        });
    final result = await connection.execute('select * from test');
    expect(
        result,
        equals([
          ['0000', 'hello', 'world']
        ]));
  });

  test('Invalid migrations', () async {
    final connection = await _createConnection();

    final gateway = PostgreSQLGateway(connection);
    await gateway.dropMigrations();
    await connection.execute("drop table if exists test");
    final db = Database(gateway);
    expect(() => db.migrate(AsIs([Migration('00', 'drop table not_exists;')])),
        throwsA(isA<PgException>()));
    expect(await gateway.currentVersion(), isNull);
    await db.migrate(AsIs([Migration('00', 'create table test (id text);')]));
    expect(await gateway.currentVersion(), equals('00'));
    expect(() => db.migrate(AsIs([Migration('01', 'drop table not_exists;')])),
        throwsA(isA<PgException>()));
    expect(await gateway.currentVersion(), equals('00'));
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
