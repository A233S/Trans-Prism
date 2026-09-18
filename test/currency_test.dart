import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans_prism/utils/currency.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cny = CurrencyFormat.cny;
  const usd = Currency('USD', r'$', '美元', 2);
  const jpy = Currency('JPY', 'JP¥', '日元', 0);
  const krw = Currency('KRW', '₩', '韩元', 0);
  const hkd = Currency('HKD', r'HK$', '港币', 2);

  // ===========================================================================
  // 预设币种
  // ===========================================================================
  group('CurrencyFormat.presets', () {
    test('包含 8 个预设且首个为 CNY', () {
      final presets = CurrencyFormat.presets;
      expect(presets.first, cny);
      expect(presets.length, 8);
      expect(presets.map((c) => c.code).toList(), [
        'CNY',
        'USD',
        'EUR',
        'GBP',
        'JPY',
        'HKD',
        'TWD',
        'KRW',
      ]);
    });

    test('JPY / KRW 为 0 位小数，其余 2 位', () {
      expect(jpy.decimals, 0);
      expect(krw.decimals, 0);
      for (final c in CurrencyFormat.presets) {
        if (c.code == 'JPY' || c.code == 'KRW') continue;
        expect(c.decimals, 2, reason: '${c.code} 应为 2 位小数');
      }
    });

    test('JPY 符号为 JP¥ 以与 CNY 的 ¥ 区分', () {
      expect(jpy.symbol, 'JP¥');
      expect(cny.symbol, '¥');
      expect(cny.label, '人民币');
    });
  });

  // ===========================================================================
  // 格式化
  // ===========================================================================
  group('CurrencyFormat.format', () {
    test('null → 占位符「—」', () {
      expect(CurrencyFormat.format(null, cny), '—');
      expect(CurrencyFormat.format(null, jpy), '—');
      expect(CurrencyFormat.format(null, cny), CurrencyFormat.emptyPlaceholder);
    });

    test('¥1,000.00 千分位正确', () {
      expect(CurrencyFormat.format(1000, cny), '¥1,000.00');
      expect(CurrencyFormat.format(1000.0, cny), '¥1,000.00');
      expect(CurrencyFormat.format(1234567.891, cny), '¥1,234,567.89');
      expect(CurrencyFormat.format(999, cny), '¥999.00');
      expect(CurrencyFormat.format(100, cny), '¥100.00');
      expect(CurrencyFormat.format(12.5, cny), '¥12.50');
      expect(CurrencyFormat.format(0, cny), '¥0.00');
    });

    test('按 decimals 定小数位（JPY / KRW 无小数）', () {
      expect(CurrencyFormat.format(1000, jpy), 'JP¥1,000');
      expect(CurrencyFormat.format(1000.4, jpy), 'JP¥1,000');
      expect(CurrencyFormat.format(1000.6, jpy), 'JP¥1,001');
      expect(CurrencyFormat.format(1234567, krw), '₩1,234,567');
      expect(CurrencyFormat.format(1000, usd), r'$1,000.00');
      expect(CurrencyFormat.format(1000, hkd), r'HK$1,000.00');
    });

    test('负数正常显示', () {
      expect(CurrencyFormat.format(-1234.5, cny), '-¥1,234.50');
      expect(CurrencyFormat.format(-1, cny), '-¥1.00');
      expect(CurrencyFormat.format(-1000, jpy), '-JP¥1,000');
    });

    test('非有限值按占位符处理（不产生 NaN / Infinity 文案）', () {
      expect(CurrencyFormat.format(double.nan, cny), '—');
      expect(CurrencyFormat.format(double.infinity, cny), '—');
      expect(CurrencyFormat.format(double.negativeInfinity, cny), '—');
    });

    test('round 行为：四舍五入到 decimals 位', () {
      expect(CurrencyFormat.format(2.142857, cny), '¥2.14');
      expect(CurrencyFormat.format(5.357142857, cny), '¥5.36');
      expect(CurrencyFormat.format(19.285714, cny), '¥19.29');
      expect(CurrencyFormat.format(22.959183, cny), '¥22.96');
    });
  });

  group('CurrencyFormat.formatWithUnit', () {
    test('带单位：¥1,000.00 / 针', () {
      expect(CurrencyFormat.formatWithUnit(1000, cny, '针'), '¥1,000.00 / 针');
      expect(CurrencyFormat.formatWithUnit(30, cny, 'mg'), '¥30.00 / mg');
    });

    test('unit 为 null / 空串 / 空白 → 等同 format', () {
      expect(CurrencyFormat.formatWithUnit(1000, cny, null), '¥1,000.00');
      expect(CurrencyFormat.formatWithUnit(1000, cny, ''), '¥1,000.00');
      expect(CurrencyFormat.formatWithUnit(1000, cny, '   '), '¥1,000.00');
    });

    test('未定价 → 只显示占位符', () {
      expect(CurrencyFormat.formatWithUnit(null, cny, '针'), '—');
    });
  });

  // ===========================================================================
  // 持久化 / 回退
  // ===========================================================================
  group('CurrencyFormat 持久化', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('缺失 → 回退 CNY', () async {
      expect(await CurrencyFormat.current(), cny);
    });

    test('存储键为 cost_currency_code', () async {
      await CurrencyFormat.set(jpy);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CurrencyFormat.storageKey), 'JPY');
      expect(CurrencyFormat.storageKey, 'cost_currency_code');
    });

    test('set → current 往返', () async {
      await CurrencyFormat.set(usd);
      final cur = await CurrencyFormat.current();
      expect(cur.code, 'USD');
      expect(cur.symbol, r'$');
      expect(cur.decimals, 2);

      await CurrencyFormat.set(jpy);
      expect((await CurrencyFormat.current()).code, 'JPY');
    });

    test('非法 code → 回退 CNY', () async {
      SharedPreferences.setMockInitialValues({
        CurrencyFormat.storageKey: 'XYZ',
      });
      expect(await CurrencyFormat.current(), cny);

      SharedPreferences.setMockInitialValues({
        CurrencyFormat.storageKey: '',
      });
      expect(await CurrencyFormat.current(), cny);
    });

    test('byCode：合法 / 非法 / null', () async {
      expect((await CurrencyFormat.byCode('USD')).code, 'USD');
      expect((await CurrencyFormat.byCode('usd')).code, 'USD');
      expect((await CurrencyFormat.byCode(' JPY ')).code, 'JPY');
      expect(await CurrencyFormat.byCode('XYZ'), cny);
      expect(await CurrencyFormat.byCode(''), cny);
      expect(await CurrencyFormat.byCode(null), cny);
    });

    test('货币判等基于 code', () async {
      expect(await CurrencyFormat.byCode('CNY'), CurrencyFormat.cny);
      expect(const Currency('CNY', '¥', '人民币', 2), cny);
      expect(CurrencyFormat.presets.contains(jpy), isTrue);
    });
  });
}
