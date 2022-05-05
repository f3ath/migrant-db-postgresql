import 'package:migrant/migrant.dart';
import 'package:postgres/postgres.dart';

class PostgreSQLGateway implements DatabaseGateway {
  PostgreSQLGateway(this._db,
      {String schema = 'public', String tablePrefix = '_migrations'})
      : _table = '$schema.${tablePrefix}_v$_version';

  /// Internal version.
  static const _version = '1';

  final PostgreSQLConnection _db;
  final String _table;

  @override
  Future<String?> currentVersion() async {
    await _init();
    final result = await _db.query('select max(version) from $_table');
    if (result.isEmpty) return null;
    return result.first.first;
  }

  @override
  Future<void> apply(Migration migration) async {
    await _init();
    await _db.transaction((ctx) async {
      await ctx.query(
          'insert into $_table (version, created_at) values (@version, now());',
          substitutionValues: {
            'version': migration.version,
          });
      await ctx.execute(migration.statement);
    });
  }

  /// Drops the migrations table.
  Future<void> dropMigrations() => _db.execute('drop table if exists $_table');

  Future<void> _init() => _db.execute(
      'create table if not exists $_table (version text primary key, created_at timestamp not null);');
}
