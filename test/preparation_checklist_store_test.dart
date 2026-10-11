import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/preparation_checklist_store.dart';

void main() {
  test('checklist survives reopening and keeps revisions separate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'preparation-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/preparation.json');
    final store = PreparationChecklistStore(file);

    await store.setChecked('recipe-a', 1, 'prep-onion', true);
    await store.setChecked('recipe-a', 2, 'prep-sauce', true);
    final reopened = PreparationChecklistStore(file);
    expect(await reopened.checked('recipe-a', 1), {'prep-onion'});
    expect(await reopened.checked('recipe-a', 2), {'prep-sauce'});
    await reopened.setChecked('recipe-a', 1, 'prep-onion', false);
    expect(
      await PreparationChecklistStore(file).checked('recipe-a', 1),
      isEmpty,
    );
    expect(await PreparationChecklistStore(file).checked('recipe-a', 2), {
      'prep-sauce',
    });
    await reopened.reset('recipe-a', 2);
    expect(
      await PreparationChecklistStore(file).checked('recipe-a', 2),
      isEmpty,
    );
  });

  test('corrupt primary reads valid backup without overwriting it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'preparation-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/preparation.json');
    await PreparationChecklistStore(file)
        .setChecked('recipe-a', 1, 'prep-a', true);
    final backup = File('${file.path}.bak');
    final original = await backup.readAsString();
    await file.writeAsString('{broken');

    expect(await PreparationChecklistStore(file).checked('recipe-a', 1), {
      'prep-a',
    });
    expect(await file.readAsString(), '{broken');
    expect(await backup.readAsString(), original);

    await backup.writeAsString('{broken');
    final blocked = PreparationChecklistStore(file);
    await expectLater(
      blocked.setChecked('recipe-a', 1, 'prep-b', true),
      throwsFormatException,
    );
    expect(await file.readAsString(), '{broken');
    expect(await backup.readAsString(), '{broken');
  });
}
