import 'package:flutter/services.dart';

abstract class RecipeSharePlatform {
  void setIncomingHandler(void Function() handler);
  Future<String?> takeNext();
  void dispose();
}

class AndroidRecipeSharePlatform implements RecipeSharePlatform {
  AndroidRecipeSharePlatform([
    this._channel = const MethodChannel('recipe/share'),
  ]);

  final MethodChannel _channel;

  @override
  void setIncomingHandler(void Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') handler();
    });
  }

  @override
  Future<String?> takeNext() => _channel.invokeMethod<String>('takeNext');

  @override
  void dispose() => _channel.setMethodCallHandler(null);
}
