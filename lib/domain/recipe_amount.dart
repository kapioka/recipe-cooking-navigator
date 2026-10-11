class Rational {
  Rational(BigInt numerator, BigInt denominator)
    : assert(numerator > BigInt.zero),
      assert(denominator > BigInt.zero),
      numerator = numerator ~/ numerator.gcd(denominator),
      denominator = denominator ~/ numerator.gcd(denominator);

  factory Rational.fromNumbers(int numerator, int denominator) =>
      Rational(BigInt.from(numerator), BigInt.from(denominator));

  factory Rational.fromStrings(String numerator, String denominator) =>
      Rational(BigInt.parse(numerator), BigInt.parse(denominator));

  final BigInt numerator;
  final BigInt denominator;

  Rational scale(int numerator, int denominator) => Rational(
    this.numerator * BigInt.from(numerator),
    this.denominator * BigInt.from(denominator),
  );

  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Map<String, String> toJson() => {
    'numerator': numerator.toString(),
    'denominator': denominator.toString(),
  };

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);
}

const amountUnitDisplay = <String, String>{
  'g': 'g',
  'kg': 'kg',
  'ml': 'ml',
  'l': 'L',
  'tsp': '小さじ',
  'tbsp': '大さじ',
  'piece': '個',
  'slice': '枚',
  'clove': '片',
  'stalk': '本',
  'sheet': '枚',
  'pack': 'パック',
  'bunch': '束',
};

const amountUnitSpeech = <String, String>{
  'g': 'グラム',
  'kg': 'キログラム',
  'ml': 'ミリリットル',
  'l': 'リットル',
  'tsp': '小さじ',
  'tbsp': '大さじ',
  'piece': '個',
  'slice': '枚',
  'clove': '片',
  'stalk': '本',
  'sheet': '枚',
  'pack': 'パック',
  'bunch': '束',
};

class FormattedAmount {
  const FormattedAmount({required this.display, required this.speech});
  final String display;
  final String speech;
}

FormattedAmount formatMeasuredAmount(Rational value, String unit) {
  final isDecimalUnit = const {'g', 'kg', 'ml', 'l'}.contains(unit);
  final displayNumber = isDecimalUnit
      ? _formatDecimal(value)
      : _formatFraction(value, speech: false);
  final speechNumber = _formatFraction(value, speech: true);
  final displayUnit = amountUnitDisplay[unit]!;
  final speechUnit = amountUnitSpeech[unit]!;
  final prefix = unit == 'tsp' || unit == 'tbsp';
  return FormattedAmount(
    display: prefix
        ? '$displayUnit$displayNumber'
        : '$displayNumber$displayUnit',
    speech: prefix ? '$speechUnit$speechNumber' : '$speechNumber$speechUnit',
  );
}

String _formatDecimal(Rational value) {
  if (value.denominator == BigInt.one) return value.numerator.toString();
  final scaledNumerator = value.numerator * BigInt.from(100);
  var hundredths = scaledNumerator ~/ value.denominator;
  final remainder = scaledNumerator.remainder(value.denominator);
  if (remainder * BigInt.two >= value.denominator) hundredths += BigInt.one;
  if (hundredths == BigInt.zero) return _formatFraction(value, speech: false);
  final exact = hundredths * value.denominator == scaledNumerator;
  final whole = hundredths ~/ BigInt.from(100);
  final fraction = (hundredths % BigInt.from(100)).toInt();
  final text = fraction == 0
      ? '$whole'
      : fraction % 10 == 0
      ? '$whole.${fraction ~/ 10}'
      : '$whole.${fraction.toString().padLeft(2, '0')}';
  return exact ? text : '約$text';
}

String _formatFraction(Rational value, {required bool speech}) {
  if (value.denominator == BigInt.one) return value.numerator.toString();
  final whole = value.numerator ~/ value.denominator;
  final remainder = value.numerator % value.denominator;
  if (remainder == BigInt.zero) return whole.toString();
  final fraction = speech
      ? '${value.denominator}分の$remainder'
      : '$remainder/${value.denominator}';
  return whole == BigInt.zero ? fraction : '$wholeと$fraction';
}

class ResolvedQuantity {
  const ResolvedQuantity._({
    required this.kind,
    this.value,
    this.unit,
    this.text,
    this.adjustmentNote,
  });

  factory ResolvedQuantity.measured(Rational value, String unit) =>
      ResolvedQuantity._(kind: 'measured', value: value, unit: unit);

  factory ResolvedQuantity.qualitative(String text, String adjustmentNote) =>
      ResolvedQuantity._(
        kind: 'qualitative',
        text: text,
        adjustmentNote: adjustmentNote,
      );

  factory ResolvedQuantity.fromJson(Map<String, dynamic> json) {
    if (json['kind'] == 'measured') {
      final value = json['value'] as Map<String, dynamic>;
      return ResolvedQuantity.measured(
        Rational.fromStrings(
          value['numerator'] as String,
          value['denominator'] as String,
        ),
        json['unit'] as String,
      );
    }
    return ResolvedQuantity.qualitative(
      json['text'] as String,
      json['adjustment_note'] as String,
    );
  }

  final String kind;
  final Rational? value;
  final String? unit;
  final String? text;
  final String? adjustmentNote;

  Map<String, dynamic> toJson() => kind == 'measured'
      ? {'kind': kind, 'value': value!.toJson(), 'unit': unit}
      : {'kind': kind, 'text': text, 'adjustment_note': adjustmentNote};
}

class RecipeAmount {
  const RecipeAmount({
    required this.id,
    required this.ingredientId,
    required this.label,
    required this.quantity,
    this.note,
  });

  final String id;
  final String ingredientId;
  final String label;
  final Map<String, dynamic> quantity;
  final List<dynamic>? note;

  bool get isFixed => quantity['scaling'] == 'fixed';
  String? get adjustmentNote => quantity['adjustment_note'] as String?;
}

class ResolvedAmount {
  const ResolvedAmount({required this.amountId, required this.quantity});
  final String amountId;
  final ResolvedQuantity quantity;

  Map<String, dynamic> toJson() => {
    'amount_id': amountId,
    'quantity': quantity.toJson(),
  };

  factory ResolvedAmount.fromJson(Map<String, dynamic> json) => ResolvedAmount(
    amountId: json['amount_id'] as String,
    quantity: ResolvedQuantity.fromJson(
      json['quantity'] as Map<String, dynamic>,
    ),
  );
}
