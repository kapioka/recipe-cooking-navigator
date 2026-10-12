import 'package:flutter/material.dart';

import '../application/recipe_ai_client.dart';
import '../application/recipe_library_controller.dart';
import '../domain/ai_recipe_prompt.dart';
import '../domain/ai_recipe_request.dart';
import 'ai_recipe_request_screen.dart';

/// Compatibility entry for callers that already have a validated request.
class ConnectedRecipeScreen extends StatelessWidget {
  const ConnectedRecipeScreen({
    required this.request,
    required this.library,
    this.client,
    this.prompt,
    super.key,
  });
  final AiRecipeRequest request;
  final RecipeLibraryController library;
  final RecipeAiClient? client;
  final AiRecipePrompt? prompt;
  @override
  Widget build(BuildContext context) => AiRecipeRequestScreen(
    initialRequest: request,
    library: library,
    client: client,
    prompt: prompt,
  );
}
