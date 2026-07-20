// Coverage for BR-N2E9MF: GpfLabelRepository resolves Czech GPF labels
// offline — bundled asset seeds the Drift cache on first read, and a populated
// cache takes precedence.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/data/repositories/gpf_label_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late GpfLabelRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = ApiClient(AuthTokenStorage(prefs: prefs));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = GpfLabelRepository(db, api);
  });

  tearDown(() => db.close());

  test('seeds the 35 Czech labels from the bundled asset when cache is empty',
      () async {
    expect(await db.getGpfDimensions(), isEmpty);

    final labels = await repo.getLabels();

    expect(labels, hasLength(35));
    expect(labels.first.domainName, 'Číslo a operace');
    // Cache was populated as a side effect.
    expect(await db.getGpfDimensions(), hasLength(35));
  });

  test('domainNames maps every domain code to its Czech name', () async {
    final map = await repo.domainNames();
    expect(map['N'], 'Číslo a operace');
    expect(map['M'], 'Míry');
    expect(map['G'], 'Geometrie');
    expect(map['S'], 'Statistika a pravděpodobnost');
    expect(map['A'], 'Algebra');
  });

  test('populated Drift cache takes precedence over the bundled asset',
      () async {
    await db.replaceGpfDimensions([
      GpfDimensionsTableCompanion.insert(
        dimensionIndex: const Value(0),
        code: 'N1.1',
        domainCode: 'N',
        domainName: 'CACHED NAME',
        constructName: 'x',
        name: 'y',
      ),
    ]);

    final labels = await repo.getLabels();
    expect(labels, hasLength(1));
    expect(labels.first.domainName, 'CACHED NAME');
  });
}
