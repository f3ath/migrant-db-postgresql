import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  // These are the migrations. We are using a simple in-memory source,
  // but you may read them from other sources: local filesystem, network, etc.
  // More options at https://pub.dev/packages/migrant
  final migrations = InMemory({
    '0001': 'CREATE TABLE foo (id TEXT NOT NULL PRIMARY KEY);',
    '0002': 'ALTER TABLE foo ADD COLUMN message TEXT;',
    // Try adding more stuff here and running this example again.
  });

  // The postgres connection. To make it work, you need an actual server.
  // Try it with Docker:
  // docker run -d -p 5432:5432 --name my-postgres -e POSTGRES_PASSWORD=postgres postgres
  final connection = PostgreSQLConnection('localhost', 5432, 'postgres',
      username: 'postgres', password: 'postgres');

  // The connection needs to be open before we do anything.
  await connection.open();

  // The gateway is provided by this package.
  final gateway = PostgreSQLGateway(connection);

  // Extra capabilities may be added like this. See the implementation below.
  final loggingGateway = LoggingGatewayWrapper(gateway);

  // Applying migrations.
  await Database(loggingGateway).migrate(migrations);

  // At this point the table "foo" is ready. We're done.
  await connection.close();
}

// Compose everything!
class LoggingGatewayWrapper implements DatabaseGateway {
  LoggingGatewayWrapper(this.gateway);

  final DatabaseGateway gateway;

  @override
  Future<void> apply(Migration migration) async {
    print('Applying version ${migration.version}...');
    gateway.apply(migration);
    print('Version ${migration.version} has been applied.');
  }

  @override
  Future<String?> currentVersion() async {
    final version = await gateway.currentVersion();
    print('The database is at version $version.');
    return version;
  }
}
