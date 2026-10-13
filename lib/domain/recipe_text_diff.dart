import 'dart:typed_data';

class RecipeTextFragment {
  const RecipeTextFragment(this.text, this.changed);
  final String text;
  final bool changed;
}

/// Exact, bounded text comparison. The full text is always preserved.
class RecipeTextDiff {
  RecipeTextDiff(String before, String after) {
    // Keep numbers together so 120 -> 150 highlights the whole value.
    final tokenPattern = RegExp(r'[0-9]+|[^0-9]', unicode: true);
    List<String> tokens(String text) => [
      for (final match in tokenPattern.allMatches(text)) match.group(0)!,
    ];
    final old = tokens(before), current = tokens(after);
    var prefix = 0, suffix = 0;
    while (prefix < old.length &&
        prefix < current.length &&
        old[prefix] == current[prefix]) {
      prefix++;
    }
    while (suffix < old.length - prefix &&
        suffix < current.length - prefix &&
        old[old.length - 1 - suffix] == current[current.length - 1 - suffix]) {
      suffix++;
    }
    final a = old.sublist(prefix, old.length - suffix);
    final b = current.sublist(prefix, current.length - suffix);
    final oldParts = <RecipeTextFragment>[], newParts = <RecipeTextFragment>[];
    void append(List<RecipeTextFragment> parts, String text, bool changed) {
      if (text.isEmpty) return;
      if (parts.isNotEmpty && parts.last.changed == changed) {
        final last = parts.removeLast();
        parts.add(RecipeTextFragment(last.text + text, changed));
      } else {
        parts.add(RecipeTextFragment(text, changed));
      }
    }

    final lead = old.take(prefix).join();
    append(oldParts, lead, false);
    append(newParts, lead, false);
    // Avoid unbounded quadratic work for very long rewritten fields.
    if ((a.length + 1) * (b.length + 1) > 250000) {
      append(oldParts, a.join(), true);
      append(newParts, b.join(), true);
    } else {
      final width = b.length + 1;
      final lengths = Uint32List((a.length + 1) * width);
      for (var i = a.length - 1; i >= 0; i--) {
        for (var j = b.length - 1; j >= 0; j--) {
          lengths[i * width + j] = a[i] == b[j]
              ? 1 + lengths[(i + 1) * width + j + 1]
              : lengths[(i + 1) * width + j] > lengths[i * width + j + 1]
              ? lengths[(i + 1) * width + j]
              : lengths[i * width + j + 1];
        }
      }
      var i = 0, j = 0;
      while (i < a.length || j < b.length) {
        if (i < a.length && j < b.length && a[i] == b[j]) {
          final char = a[i];
          append(oldParts, char, false);
          append(newParts, char, false);
          i++;
          j++;
        } else if (i < a.length &&
            (j == b.length ||
                lengths[(i + 1) * width + j] >= lengths[i * width + j + 1])) {
          append(oldParts, a[i++], true);
        } else {
          append(newParts, b[j++], true);
        }
      }
    }
    final tail = old.skip(old.length - suffix).join();
    append(oldParts, tail, false);
    append(newParts, tail, false);
    beforeFragments = List.unmodifiable(oldParts);
    afterFragments = List.unmodifiable(newParts);
  }

  late final List<RecipeTextFragment> beforeFragments, afterFragments;

  static String excerpt(List<RecipeTextFragment> parts) {
    final text = parts.map((part) => part.text).join();
    var start = 0;
    for (final part in parts) {
      if (part.changed) break;
      start += part.text.length;
    }
    // Keep the first changed line rather than repeating unchanged metadata.
    final lineStart = text.lastIndexOf('\n', start > 0 ? start - 1 : 0) + 1;
    final lineEnd = text.indexOf('\n', start);
    final line = text.substring(lineStart, lineEnd < 0 ? text.length : lineEnd);
    final runes = line.runes.toList();
    final offset = text
        .substring(lineStart, start.clamp(lineStart, text.length))
        .runes
        .length;
    final from = offset > 24 ? offset - 24 : 0;
    final end = (from + 90).clamp(0, runes.length);
    return '${from > 0 ? '…' : ''}${String.fromCharCodes(runes.sublist(from, end))}'
        '${end < runes.length ? '…' : ''}';
  }
}
