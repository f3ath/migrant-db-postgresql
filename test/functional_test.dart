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
  group('Happy path', () {
    late Connection connection;
    late PostgreSQLGateway gateway;
    late Database db;

    setUp(() async {
      connection = await _createConnection();
      await connection.execute('DROP SCHEMA public CASCADE;');
      await connection.execute('CREATE SCHEMA public;');
      gateway = PostgreSQLGateway(connection);
      db = Database(gateway);
    });

    test('Single migration', () async {
      final source = InMemory([
        Migration('0', ['create table test (id text);'])
      ]);

      await db.upgrade(source);
      expect(await gateway.currentVersion(), equals('0'));
      await connection.execute(Sql.named('insert into test (id) values (@id)'),
          parameters: {
            'id': '0000',
          });
      final result = await connection.execute('select * from test');
      expect(
          result,
          equals([
            ['0000']
          ]));
    });

    test('Single migration, idempotency', () async {
      final source = InMemory([
        Migration('0', ['create table test (id text);'])
      ]);

      await db.upgrade(source);
      expect(await gateway.currentVersion(), equals('0'));
      await db.upgrade(source); // idempotency
      expect(await gateway.currentVersion(), equals('0'));
      await connection.execute(Sql.named('insert into test (id) values (@id)'),
          parameters: {
            'id': '0000',
          });
      final result = await connection.execute('select * from test');
      expect(
          result,
          equals([
            ['0000']
          ]));
    });

    test('Multiple migrations', () async {
      final source = InMemory([
        Migration('0', ['create table test (id text);']),
        Migration('1', ['alter table test add column foo text;']),
        Migration('2', ['alter table test add column bar text;'])
      ]);

      await db.upgrade(source);
      expect(await gateway.currentVersion(), equals('2'));
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

    test('Multiple migrations, idempotency', () async {
      final source = InMemory([
        Migration('0', ['create table test (id text);']),
        Migration('1', ['alter table test add column foo text;']),
        Migration('2', ['alter table test add column bar text;'])
      ]);

      await db.upgrade(source);
      expect(await gateway.currentVersion(), equals('2'));
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
  });

  group('Failures', () {
    late Connection connection;
    late PostgreSQLGateway gateway;
    late Database db;

    setUp(() async {
      connection = await _createConnection();
      await connection.execute('DROP SCHEMA public CASCADE;');
      await connection.execute('CREATE SCHEMA public;');
      gateway = PostgreSQLGateway(connection);
      db = Database(gateway);
    });

    test('initialize() detects RC', () async {
      await gateway.initialize(Migration('1', ['create table foo (id text);']));

      await expectLater(
          () => gateway
              .initialize(Migration('0', ['create table bar (id text);'])),
          throwsA(isA<RaceCondition>().having((it) => it.message, 'message',
              equals('Unexpected history: [0, 1]'))));

      expect(await gateway.currentVersion(), equals('1'));
    });

    test('upgrade() detects RC', () async {
      await gateway.initialize(Migration('1', ['create table foo (id text);']));

      await expectLater(
          () => gateway.upgrade(
              '0', Migration('2', ['create table bar (id text);'])),
          throwsA(isA<RaceCondition>().having((it) => it.message, 'message',
              equals('Unexpected history: [1, 2]'))));

      expect(await gateway.currentVersion(), equals('1'));
    });

    test('Single invalid migration not applied', () async {
      final source = InMemory([
        Migration('0', ['drop table not_exists;'])
      ]);

      expect(() => db.upgrade(source), throwsException);
      expect(await gateway.currentVersion(), isNull);
    });

    test('Migrations get applied until the first failure', () async {
      final source = InMemory([
        Migration('0', ['create table test (id text);']),
        Migration('1', ['alter table test add column c1 text;']),
        Migration('2', ['alter table test add column c2 text;']),
        Migration('3', ['alter table test_oops add column c3 text;']),
        Migration('4', ['alter table test add column c4 text;']),
      ]);

      await expectLater(() => db.upgrade(source), throwsException);
      expect(await gateway.currentVersion(), equals('2'));
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
