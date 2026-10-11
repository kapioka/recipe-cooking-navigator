import 'package:flutter/services.dart';

abstract class AiRequestPlatform {
  Future<void> share(String request);
  Future<void> openChatGpt();
}

class AndroidAiRequestPlatform implements AiRequestPlatform {
  const AndroidAiRequestPlatform();
  static const _channel = MethodChannel('recipe/ai-request');

  @override
  Future<void> share(String request) =>
      _channel.invokeMethod<void>('share', request);

  @override
  Future<void> openChatGpt() => _channel.invokeMethod<void>('openChatGpt');
}
