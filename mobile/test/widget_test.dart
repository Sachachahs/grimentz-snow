import 'package:flutter_test/flutter_test.dart';
import 'package:grimentz_snow/util/format.dart';
import 'package:grimentz_snow/util/json.dart';

void main() {
  test('format : pas de « -0 », valeur absente = null', () {
    expect(fmt(-0.04, digits: 1), '0.0');
    expect(fmt(null), isNull);
    expect(fmt(12.0, unit: 'cm'), '12 cm');
    expect(fmtCm(0.4), '0.4 cm');
  });

  test('heure de Zurich (hiver / été)', () {
    expect(toZurich(DateTime.utc(2026, 1, 10, 12)).hour, 13);
    expect(toZurich(DateTime.utc(2026, 7, 10, 12)).hour, 14);
  });

  test('JSON : accès sûr', () {
    const j = J({'a': [1, 2.5], 'b': null});
    expect(j['a'][1].d, 2.5);
    expect(j['a'][5].d, isNull);
    expect(j['b']['x'].s, isNull);
    expect(j['zzz'].list, isEmpty);
  });
}
