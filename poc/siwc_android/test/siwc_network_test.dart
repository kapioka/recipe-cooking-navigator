import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcn_siwc_poc/siwc_contract.dart';
import 'package:rcn_siwc_poc/siwc_network.dart';

class TestHeaders implements HttpHeaders {
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestResponse extends Stream<List<int>> implements HttpClientResponse {
  TestResponse(this.statusCode, String? mime, String body)
    : headers = TestHeaders()
        ..contentType = mime == null ? null : ContentType.parse(mime),
      bytes = Stream.value(utf8.encode(body));
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  final Stream<List<int>> bytes;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => bytes.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestRequest implements HttpClientRequest {
  TestRequest(this.response);
  final TestResponse response;
  @override
  final HttpHeaders headers = TestHeaders();
  @override
  bool followRedirects = true;
  @override
  int contentLength = -1;
  List<int>? payload;
  @override
  void add(List<int> data) {
    payload = List.of(data);
  }

  @override
  void write(Object? object) {}
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestClient implements HttpClient {
  TestClient(this.response);
  final TestResponse response;
  @override
  Duration? connectionTimeout;
  bool closed = false;
  TestRequest? lastRequest;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      lastRequest = TestRequest(response);
  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'HTTP error diagnoses known fields without displaying server contents',
    () async {
      for (final parameter in ['text.format', 'private-account-secret']) {
        final response = jsonEncode({
          'error': {
            'param': parameter,
            'code': 'unsupported_parameter',
            'message': 'secret response with private values',
          },
        });
        final network = HttpSiwcNetwork(
          client: TestClient(TestResponse(400, 'application/json', response)),
        );
        await expectLater(
          network.infer('fake-access', inferenceBody('detected', 'confirmed')),
          throwsA(
            isA<SiwcFailure>().having(
              (error) => error.message,
              'safe HTTP error',
              allOf(
                contains('HTTP 400'),
                contains('未対応の指定'),
                isNot(contains('secret')),
                isNot(contains('private values')),
                parameter == 'text.format'
                    ? contains('出力形式')
                    : isNot(contains('account')),
              ),
            ),
          ),
        );
      }
      expect(
        safeHttpFailure(400, utf8.encode('secret-not-json')),
        isNot(contains('secret')),
      );
    },
  );
  test('successful SSE validates completion with 201 or omitted media header and UTF8 length', () async {
    final body =
        'data: ${jsonEncode({
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'completed'},
                ],
              },
            ],
          },
        })}\n\n';
    for (final example in [(201, 'text/event-stream'), (200, null)]) {
      final client = TestClient(TestResponse(example.$1, example.$2, body));
      final network = HttpSiwcNetwork(client: client);
      expect(
        await network.infer('fake-access', inferenceBody('detected', '確認済み')),
        'completed',
      );
      final request = client.lastRequest!;
      expect(request.contentLength, request.payload!.length);
      expect((jsonDecode(utf8.decode(request.payload!)) as Map)['input'], [
        {'role': 'user', 'content': '確認済み'},
      ]);
    }
  });

  test(
    'omitted media header never makes empty or plain JSON a completed stream',
    () async {
      for (final body in ['', '{"status":"completed","text":"secret-body"}']) {
        final client = TestClient(TestResponse(200, null, body));
        final network = HttpSiwcNetwork(client: client);
        await expectLater(
          network.infer('fake-access', inferenceBody('detected', 'confirmed')),
          throwsA(
            isA<SiwcFailure>().having(
              (error) => error.message,
              'fail closed',
              isNot(contains('secret')),
            ),
          ),
        );
        expect(client.closed, true);
      }
    },
  );

  test(
    'non-stream success fails with HTTP/media diagnosis and hides body',
    () async {
      final client = TestClient(TestResponse(200, 'text/html', 'secret-body'));
      final network = HttpSiwcNetwork(client: client);
      await expectLater(
        network.infer('fake-access', inferenceBody('detected', 'confirmed')),
        throwsA(
          isA<SiwcFailure>().having(
            (error) => error.message,
            'safe media diagnosis',
            allOf(
              contains('HTTP 200'),
              contains('HTML'),
              isNot(contains('secret')),
            ),
          ),
        ),
      );
      expect(client.closed, true);
    },
  );
}
