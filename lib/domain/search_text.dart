import 'package:unorm_dart/unorm_dart.dart' as unicode;

String normalizeSearchText(String value) {
  return unicode.nfkc(value).trim().toLowerCase();
}
