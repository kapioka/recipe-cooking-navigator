import 'package:flutter/material.dart';

void main() {
  runApp(const RecipeCookingNavigatorApp());
}

class RecipeCookingNavigatorApp extends StatelessWidget {
  const RecipeCookingNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Recipe Cooking Navigator',
      home: Scaffold(body: Center(child: Text('Recipe Cooking Navigator'))),
    );
  }
}
