import 'package:migrant/migrant.dart';
import 'package:postgres/postgres.dart';

class PostgreSQLGateway implements DatabaseGateway {
  PostgreSQLGateway(this._db,
      {String schema = 'public', String tablePrefix = '_migrations'})
      : _table = '$schema.${tablePrefix}_v$_version' {
    _insertVersion = Sql.named(
        'insert into $_table (version, created_at) values (@version, now());');
  }

  /// Internal version.
  static const _version = 1;

  final Connection _db;
  final String _table;
  late final Sql _insertVersion;

  @override
  Future<void> initialize(Migration migration) async {
    await _init();
    await _db.runTx((ctx) async {
      for (final statement in migration.statements) {
        await ctx.execute(statement);
      }
      await _register(migration.version, ctx);
      final history = await _history(ctx);
      if (history.length != 1 || history.first != migration.version) {
        throw RaceCondition('Unexpected history: $history');
      }
    });
  }

  @override
  Future<void> upgrade(String version, Migration migration) async {
    await _init();
    await _db.runTx((ctx) async {
      for (final statement in migration.statements) {
        await ctx.execute(statement);
      }
      await _register(migration.version, ctx);
      final history = await _history(ctx);
      if (history.length < 2 ||
          history.last != migration.version ||
          history[history.length - 2] != version) {
        throw RaceCondition('Unexpected history: $history');
      }
    });
  }

  @override
  Future<String?> currentVersion() async {
    await _init();
    final result = await _db.execute('select max(version) from $_table');
    return result.isEmpty ? null : result.first.first as String?;
  }

  Future<Result> _register(String version, TxSession session) =>
      session.execute(_insertVersion, parameters: {
        'version': version,
      });

  Future<Result> _init() => _db.execute(
      'create table if not exists $_table (version text primary key, created_at timestamp not null);');

  /// Returns the applied versions, ascending.
  Future<List<String>> _history(TxSession session) async {
    final result = await session
        .execute('select version from $_table order by version asc');
    return result.map((row) => row.first as String).toList();
  }
}

/// Thrown when the gateway detects a race condition during migration.
class RaceCondition implements Exception {
  const RaceCondition(this.message);

  final String message;

  @override
  String toString() => message;
}
