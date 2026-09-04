import 'package:file_selector/file_selector.dart';

Future<String?> pickRecipeSource() async {
  const recipeType = XTypeGroup(
    label: 'ChatGPTレシピ',
    extensions: ['json'],
    mimeTypes: ['application/json', 'text/json'],
  );
  final file = await openFile(acceptedTypeGroups: const [recipeType]);
  return file?.readAsString();
}
