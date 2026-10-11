import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/cooking_profile_cache_store.dart';

void main() {
  late Directory directory;
  late File file;
  late CookingProfileCacheStore store;
  late Map<String, dynamic> profile;
  const root = 'content://drive/tree/profile';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('profile-cache-');
    file = File('${directory.path}/cache.json');
    store = CookingProfileCacheStore(
      file,
      File('schemas/cooking-profile-v1.schema.json').readAsStringSync(),
      explicitSchemaSource: File('schemas/cooking-profile-v1.1.schema.json')
          .readAsStringSync(),
    );
    profile = jsonDecode(
      File('examples/cooking-profile-example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'validated cache survives restart; same revision is idempotent',
    () async {
      expect(await store.load(), isNull);
      await store.save(root, jsonEncode(profile));
      final bytes = await file.readAsBytes();
      await store.save(root, jsonEncode(profile));
      expect(await file.readAsBytes(), bytes);
      final reloaded = await store.load();
      expect(reloaded!.root, root);
      expect(reloaded.profile.toJson(), profile);
      await store.save(root, jsonEncode({...profile, 'revision': 3}));
      expect((await store.load())!.profile.revision, 3);
      expect(
        jsonDecode(await File('${file.path}.bak').readAsString())['profile'],
        profile,
      );
    },
  );

  test('unknown schemas, conflicting revision, rollback and changed ID retain cache', () async {
    await store.save(root, jsonEncode(profile));
    final before = await file.readAsString();
    await expectLater(
      store.save(
        root,
        jsonEncode({...profile, 'profile_schema_version': '9.0.0'}),
      ),
      throwsFormatException,
    );
    for (final invalid in [
      {...profile, 'revision': 1},
      {...profile, 'profile_id': 'different-profile'},
      {
        ...profile,
        'explicit_constraints': ['new constraint'],
      },
      {...profile, 'revision': 3, 'updated_at': '2026-10-03T00:00:00Z'},
    ]) {
      await expectLater(
        store.save(root, jsonEncode(invalid)),
        throwsStateError,
      );
      expect(await file.readAsString(), before);
    }
    await expectLater(store.save(root, '{broken'), throwsFormatException);
    expect(await file.readAsString(), before);
  });

  test('corrupt primary is neither hidden by backup nor overwritten', () async {
    await store.save(root, jsonEncode(profile));
    await File('${file.path}.bak').writeAsString(await file.readAsString());
    await file.writeAsString('{broken-cache');
    await expectLater(store.load(), throwsFormatException);
    await expectLater(
      store.save(root, jsonEncode(profile)),
      throwsFormatException,
    );
    expect(await file.readAsString(), '{broken-cache');
  });

  test('interrupted first cache is not silently initialized', () async {
    await File('${file.path}.tmp').writeAsString('interrupted');
    await expectLater(store.load(), throwsFormatException);
    await expectLater(
      store.save(root, jsonEncode(profile)),
      throwsFormatException,
    );
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.tmp').readAsString(), 'interrupted');
  });

  test('full record digest survives restart and cannot be downgraded or changed for the same ID', () async {
    await store.save(
      root,
      jsonEncode(profile),
      historyRecordId: 'confirmed',
      historyRecordDigest: 'a' * 64,
    );
    expect((await store.load())!.historyRecordDigest, 'a' * 64);
    final before = await file.readAsString();
    await expectLater(
      store.save(
        root,
        jsonEncode(profile),
        historyRecordId: 'confirmed',
        historyRecordDigest: 'b' * 64,
      ),
      throwsStateError,
    );
    await expectLater(
      store.save(root, jsonEncode(profile), historyRecordId: 'confirmed'),
      throwsStateError,
    );
    await expectLater(store.save(root, jsonEncode(profile)), throwsStateError);
    expect(await file.readAsString(), before);
  });

  test(
    'explicit Profile 1.1 is schema validated and survives restart',
    () async {
      final source = File('examples/cooking-profile-explicit-example.json')
          .readAsStringSync();
      await store.save(root, source);
      expect((await store.load())!.profile.toJson(), jsonDecode(source));
      final invalid = jsonDecode(source) as Map<String, dynamic>;
      invalid['preferences'][1]['feedback_ids'] = ['invented'];
      final before = await file.readAsString();
      await expectLater(
        store.save(root, jsonEncode(invalid)),
        throwsFormatException,
      );
      expect(await file.readAsString(), before);
    },
  );
}
