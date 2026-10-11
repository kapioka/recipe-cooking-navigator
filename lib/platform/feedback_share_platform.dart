import 'package:flutter/services.dart';

abstract class FeedbackSharePlatform {
  Future<void> shareJson(String source);
}

class AndroidFeedbackSharePlatform implements FeedbackSharePlatform {
  const AndroidFeedbackSharePlatform([
    this._channel = const MethodChannel('recipe/feedback'),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> shareJson(String source) async {
    await _channel.invokeMethod<void>('shareJson', source);
  }
}
