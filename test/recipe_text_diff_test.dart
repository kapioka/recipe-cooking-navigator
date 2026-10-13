import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/recipe_text_diff.dart';

void main() {
  String text(List<RecipeTextFragment> parts) =>
      parts.map((part) => part.text).join();
  test('marks sparse changes and whole numbers, leaving shared text alone', () {
    final diff = RecipeTextDiff('中火で120秒焼き、皿に盛る。', '弱火で150秒焼き、皿に盛る。');
    expect(
      diff.beforeFragments
          .where((part) => part.changed)
          .map((part) => part.text),
      ['中火で120'],
    );
    expect(
      diff.afterFragments
          .where((part) => part.changed)
          .map((part) => part.text),
      ['弱火で150'],
    );
    expect(text(diff.beforeFragments), '中火で120秒焼き、皿に盛る。');
    expect(text(diff.afterFragments), '弱火で150秒焼き、皿に盛る。');
  });
  test(
    'rewritten advice highlights readable phrases without isolated kana',
    () {
      final diff = RecipeTextDiff('味が薄い\n塩やしょうゆを少しずつ足す', '味が薄い\nしょうゆを少量ずつ追加する');
      expect(
        diff.afterFragments
            .where((part) => part.changed)
            .map((part) => part.text),
        ['しょうゆを少量ずつ追加する'],
      );
      expect(
        diff.beforeFragments
            .where((part) => part.changed)
            .map((part) => part.text),
        ['塩やしょうゆを少しずつ足す'],
      );
      expect(diff.afterFragments.first.text, '味が薄い\n');
      expect(diff.afterFragments.first.changed, isFalse);
    },
  );
  test('unchanged clauses surrounding a rewrite stay unhighlighted', () {
    final diff = RecipeTextDiff(
      '火を止め、塩を少し足す。味を確認する。',
      '火を止め、しょうゆを少量ずつ追加する。味を確認する。',
    );
    expect(
      diff.afterFragments
          .where((part) => part.changed)
          .map((part) => part.text),
      ['しょうゆを少量ずつ追加する'],
    );
    expect(text(diff.afterFragments), '火を止め、しょうゆを少量ずつ追加する。味を確認する。');
    expect(diff.afterFragments.last.text, '。味を確認する。');
    expect(diff.afterFragments.last.changed, isFalse);
  });
  test(
    'decimal quantities highlight the whole value without coloring units',
    () {
      final diff = RecipeTextDiff('塩 0.5g\n用途: 下味', '塩 0.7g\n用途: 下味');
      expect(
        diff.afterFragments
            .where((part) => part.changed)
            .map((part) => part.text),
        ['0.7'],
      );
      expect(text(diff.beforeFragments), '塩 0.5g\n用途: 下味');
      expect(text(diff.afterFragments), '塩 0.7g\n用途: 下味');
    },
  );
  for (final pair in [
    ('', '塩を加える。'),
    ('塩を加える。', ''),
    ('🍲を温める', '🍛を温める'),
    ('同じ文章', '同じ文章'),
    ('砂糖 120g\n用途: たれ', '砂糖 150g\n用途: たれ'),
  ]) {
    test('preserves both full texts $pair', () {
      final diff = RecipeTextDiff(pair.$1, pair.$2);
      expect(text(diff.beforeFragments), pair.$1);
      expect(text(diff.afterFragments), pair.$2);
      if (pair.$1 == pair.$2) {
        expect(diff.afterFragments.any((part) => part.changed), isFalse);
      }
    });
  }
  test('excerpt finds a late change and skips unchanged metadata', () {
    final prefix = '変わらない説明。' * 30;
    final diff = RecipeTextDiff(
      '${prefix}120秒\n用途: 加熱',
      '${prefix}150秒\n用途: 加熱',
    );
    final excerpt = RecipeTextDiff.excerpt(diff.afterFragments);
    expect(excerpt, startsWith('…'));
    expect(excerpt, contains('150秒'));
    expect(excerpt, isNot(contains('用途')));
    expect(excerpt.runes.length, lessThanOrEqualTo(92));
  });
  test('large rewrites stay bounded and preserve complete text', () {
    final before = '旧い説明🍲。' * 300, after = '新しい工程🍛。' * 300;
    final diff = RecipeTextDiff(before, after);
    expect(text(diff.beforeFragments), before);
    expect(text(diff.afterFragments), after);
    expect(diff.afterFragments.any((part) => part.changed), isTrue);
  });
}
