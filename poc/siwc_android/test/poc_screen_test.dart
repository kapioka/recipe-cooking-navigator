import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rcn_siwc_poc/poc_screen.dart';
import 'package:rcn_siwc_poc/siwc_contract.dart';
import 'package:rcn_siwc_poc/siwc_runtime.dart';

import 'siwc_runtime_test.dart' show FakePlatform, FakeNetwork;

void main() {
  Future<({FakePlatform platform, FakeNetwork network, SiwcRuntime runtime})>
  fixture() async {
    final platform = FakePlatform()
      ..saved = jsonEncode({
        'version': 1,
        'host_id': 'urn:uuid:fixture',
        'active_client_id': 'issued',
        'profiles': [
          {
            'client_id': 'issued',
            'subject': 'account',
            'label': 'Test account',
            'access_token': 'fake-access',
            'refresh_token': 'fake-refresh',
            'id_token': 'retained-fake-hint',
            'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'scopes': scopes.split(' '),
          },
        ],
      });
    final network = FakeNetwork(platform);
    return (
      platform: platform,
      network: network,
      runtime: SiwcRuntime(platform, network),
    );
  }

  testWidgets(
    'voice populates editable field and only confirmation sends edited text once',
    (tester) async {
      final f = await fixture();
      f.platform.speech = '誤認識した条件';
      await tester.pumpWidget(MaterialApp(home: PocScreen(runtime: f.runtime)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('dictate')),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('dictate')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('confirmed_text')))
            .controller!
            .text,
        '誤認識した条件',
      );
      expect(f.network.inferences, 0);
      await tester.ensureVisible(find.byKey(const Key('edit')));
      await tester.tap(find.byKey(const Key('edit')));
      await tester.pumpAndSettle();
      expect(f.network.inferences, 0);
      await tester.enterText(
        find.byKey(const Key('confirmed_text')),
        '修正済みの条件',
      );
      await tester.ensureVisible(find.byKey(const Key('confirm_send')));
      await tester.tap(find.byKey(const Key('confirm_send')));
      await tester.pumpAndSettle();
      expect(f.network.inferences, 1);
      expect(f.network.sent?['input'], [
        {'role': 'user', 'content': '修正済みの条件'},
      ]);
    },
  );

  testWidgets(
    'empty/cancelled speech and editing do not send; blank keyboard input disables confirmation',
    (tester) async {
      final f = await fixture();
      await tester.pumpWidget(MaterialApp(home: PocScreen(runtime: f.runtime)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('dictate')),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      for (final speech in <String?>[null, ' ']) {
        f.platform.speech = speech;
        await tester.tap(find.byKey(const Key('dictate')));
        await tester.pumpAndSettle();
        expect(f.network.inferences, 0);
      }
      await tester.enterText(find.byKey(const Key('confirmed_text')), ' ');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('confirm_send')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm_send')))
            .onPressed,
        isNull,
      );
      expect(f.network.inferences, 0);
    },
  );
}
