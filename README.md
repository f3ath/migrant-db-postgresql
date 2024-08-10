PostgreSQL gateway for [migrant](https://pub.dev/packages/migrant).

Example:

```dart
import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  // These are the migrations. We are using a simple in-memory source,
  // but you may read them from other sources: local filesystem, network, etc.
  // More options at https://pub.dev/packages/migrant
  final migrations = InMemory([
    Migration('0001', ['CREATE TABLE foo (id TEXT NOT NULL PRIMARY KEY);']),
    Migration('0002', ['ALTER TABLE foo ADD COLUMN message TEXT;']),
    // Try adding more stuff here and running this example again.
  ]);

  // The postgres connection. To make it work, you need an actual server.
  // Try it with Docker:
  // docker run -d -p 5432:5432 --name my-postgres -e POSTGRES_PASSWORD=postgres postgres
  final connection = await Connection.open(
      Endpoint(
        host: 'localhost',
        database: 'postgres',
        username: 'postgres',
        password: 'postgres',
      ),
      settings: ConnectionSettings(sslMode: SslMode.disable));

  // The gateway is provided by this package.
  final gateway = PostgreSQLGateway(connection);

  // Applying migrations.
  await Database(gateway).upgrade(migrations);

  // At this point the table "foo" is ready. We're done.
  await connection.close();
}
```