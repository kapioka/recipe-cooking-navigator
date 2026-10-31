import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:siwc_client/siwc_contract.dart';

void main() {
  List<String> completedLines(String text) => [
    'data: ${jsonEncode({
      'type': 'response.completed',
      'response': {
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          },
        ],
      },
    })}',
    '',
  ];
  test(
    'only nonempty text signals receiving and partial output never succeeds',
    () async {
      var notifications = 0;
      final stream = StreamController<String>();
      var finished = false;
      final answer =
          collectCompletedResponse(
            stream.stream,
            onReceiving: () => notifications++,
          ).then((value) {
            finished = true;
            return value;
          });
      void event(Map<String, dynamic> value) {
        stream.add('data: ${jsonEncode(value)}');
        stream.add('');
      }

      event({'type': 'response.in_progress'});
      event({'type': 'response.output_text.delta', 'delta': ''});
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      event({'type': 'response.output_text.delta', 'delta': 'rec'});
      event({'type': 'response.output_text.delta', 'delta': 'ipe'});
      event({'type': 'response.output_text.done', 'text': 'recipe'});
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(finished, isFalse);
      for (final line in completedLines('recipe')) {
        stream.add(line);
      }
      expect(await answer, 'recipe');
      expect(notifications, 1);
      await stream.close();
    },
  );
  test('done without deltas signals receiving once', () async {
    var notifications = 0;
    final lines = [
      'data: ${jsonEncode({'type': 'response.output_text.done', 'text': 'recipe'})}',
      '',
      ...completedLines('recipe'),
    ];
    expect(
      await collectCompletedResponse(
        Stream.fromIterable(lines),
        onReceiving: () => notifications++,
      ),
      'recipe',
    );
    expect(notifications, 1);
  });
}
