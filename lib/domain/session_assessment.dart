/// User-entered facts about one completed cook. Stored beside its Cook Session,
/// never in a Recipe document.
class SessionAssessment {
  const SessionAssessment({
    required this.actualTimeMinutes,
    required this.difficultyScore,
    required this.difficultyComment,
    required this.issues,
    required this.changesMade,
    required this.overall,
    required this.taste,
    required this.comment,
    required this.nextTimeIntent,
  });

  final int actualTimeMinutes;
  final int difficultyScore;
  final String difficultyComment;
  final List<String> issues;
  final List<Map<String, String>> changesMade;
  final int overall;
  final List<Map<String, dynamic>> taste;
  final String comment;
  final List<String> nextTimeIntent;

  static const tasteDimensions = <String>{
    'sweetness',
    'saltiness',
    'umami',
    'spiciness',
    'acidity',
    'richness',
    'aroma',
    'texture',
  };

  factory SessionAssessment.fromJson(Map<String, dynamic> value) {
    final difficulty = value['difficulty'];
    final evaluation = value['evaluation'];
    if (value.keys.toSet().difference({
          'actual_time_minutes',
          'difficulty',
          'issues',
          'changes_made',
          'evaluation',
        }).isNotEmpty ||
        value.length != 5 ||
        value['actual_time_minutes'] is! int ||
        difficulty is! Map<String, dynamic> ||
        value['issues'] is! List ||
        value['changes_made'] is! List ||
        evaluation is! Map<String, dynamic>) {
      throw const FormatException('調理後の評価が破損しています。');
    }
    final rawIssues = value['issues'] as List;
    final rawChanges = value['changes_made'] as List;
    final rawTaste = evaluation['taste'];
    final rawIntent = evaluation['next_time_intent'];
    if (difficulty.length != 2 ||
        difficulty['score'] is! int ||
        difficulty['comment'] is! String ||
        evaluation.length != 4 ||
        evaluation['overall'] is! int ||
        rawTaste is! List ||
        evaluation['comment'] is! String ||
        rawIntent is! List ||
        rawIssues.any((item) => item is! String || item.trim().isEmpty) ||
        rawChanges.any(
          (item) =>
              item is! Map<String, dynamic> ||
              item.keys.toSet().difference({
                'description',
                'result',
              }).isNotEmpty ||
              item['description'] is! String ||
              (item['description'] as String).trim().isEmpty ||
              (item.containsKey('result') && item['result'] is! String),
        ) ||
        rawIntent.any((item) => item is! String || item.trim().isEmpty) ||
        rawTaste.any(
          (item) =>
              item is! Map<String, dynamic> ||
              item.length != 3 ||
              !tasteDimensions.contains(item['dimension']) ||
              item['deviation'] is! int ||
              item['comment'] is! String,
        )) {
      throw const FormatException('調理後の評価が破損しています。');
    }
    return SessionAssessment(
      actualTimeMinutes: value['actual_time_minutes'] as int,
      difficultyScore: difficulty['score'] as int,
      difficultyComment: difficulty['comment'] as String,
      issues: rawIssues.cast<String>(),
      changesMade: rawChanges
          .map((item) => Map<String, String>.from(item as Map))
          .toList(),
      overall: evaluation['overall'] as int,
      taste: rawTaste
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      comment: evaluation['comment'] as String,
      nextTimeIntent: rawIntent.cast<String>(),
    )..validate();
  }

  void validate() {
    if (actualTimeMinutes < 1 ||
        difficultyScore < 1 ||
        difficultyScore > 5 ||
        overall < 1 ||
        overall > 5 ||
        issues.any((item) => item.trim().isEmpty) ||
        changesMade.any(
          (item) =>
              item.keys.toSet().difference({
                'description',
                'result',
              }).isNotEmpty ||
              item['description'] == null ||
              item['description']!.trim().isEmpty,
        ) ||
        nextTimeIntent.any((item) => item.trim().isEmpty) ||
        taste.any(
          (item) =>
              !tasteDimensions.contains(item['dimension']) ||
              item['deviation'] is! int ||
              (item['deviation'] as int) < -2 ||
              (item['deviation'] as int) > 2 ||
              item['comment'] is! String,
        ) ||
        taste.map((item) => item['dimension']).toSet().length != taste.length) {
      throw const FormatException('調理後の評価が正しくありません。');
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'actual_time_minutes': actualTimeMinutes,
      'difficulty': {'score': difficultyScore, 'comment': difficultyComment},
      'issues': List<String>.of(issues),
      'changes_made': [
        for (final change in changesMade) Map<String, String>.of(change),
      ],
      'evaluation': {
        'overall': overall,
        'taste': [for (final rating in taste) Map<String, dynamic>.of(rating)],
        'comment': comment,
        'next_time_intent': List<String>.of(nextTimeIntent),
      },
    };
  }
}
