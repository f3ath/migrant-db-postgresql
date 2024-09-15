import 'package:migrant/migrant.dart';
import 'package:postgres/postgres.dart';

class PostgreSQLGateway implements DatabaseGateway {
  PostgreSQLGateway(this._db,
      {String schema = 'public', String table = 'schema_version'})
      : _insertVersion = Sql.named(
            'INSERT INTO "$schema"."$table" (version, applied_at) VALUES (@version, now())'),
        _lockTable =
            Sql.named('LOCK TABLE "$schema"."$table" IN EXCLUSIVE MODE NOWAIT'),
        _createTable = Sql.named(
            'CREATE TABLE IF NOT EXISTS "$schema"."$table" (version text PRIMARY KEY COLLATE "C", applied_at timestamp NOT NULL)'),
        _selectMaxVersion = Sql.named(
            'SELECT version FROM "$schema"."$table" ORDER BY version  DESC LIMIT 1'),
        _tryLock =
            Sql.named('SELECT pg_try_advisory_xact_lock(hashtext(@text))');

  final Connection _db;
  final Sql _insertVersion,
      _lockTable,
      _createTable,
      _selectMaxVersion,
      _tryLock;

  @override
  Future<void> initialize(Migration migration) async {
    await _db.runTx((ctx) async {
      final locked = await ctx.execute(_tryLock, parameters: {
        'text': 'migrant_db_postgresql',
      }).then((r) => r.first.first as bool);
      if (!locked) {
        throw RaceCondition('DB already initialized');
      }
      await ctx.execute(_createTable);
    });
    return await _apply(migration, null);
  }

  @override
  Future<void> upgrade(String version, Migration migration) =>
      _apply(migration, version);

  Future<void> _apply(Migration migration, String? expectedVersion) =>
      _db.runTx((ctx) async {
        try {
          await ctx.execute(_lockTable);
        } on ServerException catch (e) {
          if (e.code == _lockNotAvailable) {
            throw RaceCondition('Another process is running');
          }
          rethrow;
        }
        final maxVersion = await _currentVersion(ctx);
        if (maxVersion != expectedVersion) {
          throw RaceCondition('DB not at version $expectedVersion');
        }
        await ctx.execute(_insertVersion, parameters: {
          'version': migration.version,
        });
        for (final statement in migration.statements) {
          await ctx.execute(statement);
        }
      });

  @override
  Future<String?> currentVersion() => _currentVersion(_db);

  Future<String?> _currentVersion(Session session) async {
    try {
      return await session
          .execute(_selectMaxVersion)
          .then((r) => r.isEmpty ? null : r.first.first) as String?;
    } on ServerException catch (e) {
      if (e.code == _undefinedTable) return null;
      rethrow;
    }
  }
}

/// Thrown when a race condition is detected.
class RaceCondition implements Exception {
  const RaceCondition(this.message);

  final String message;

  @override
  String toString() => message;
}

const _undefinedTable = '42P01';
const _lockNotAvailable = '55P03';
