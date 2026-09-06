import 'package:flutter/services.dart';

class CookingDevice {
  static const channel = MethodChannel('recipe/cooking');
  void Function(String method, dynamic value)? onEvent;

  CookingDevice() {
    channel.setMethodCallHandler((call) async {
      onEvent?.call(call.method, call.arguments);
    });
  }
  Future<void> invoke(String method, [dynamic arguments]) async {
    await channel.invokeMethod<void>(method, arguments);
  }

  Future<void> close() async {
    onEvent = null;
    channel.setMethodCallHandler(null);
    await invoke('close');
  }
}
