import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/levels.dart';

void main() {
  group('LevelConfig.forLevel', () {
    test('level 1 values', () {
      final c = LevelConfig.forLevel(1);
      expect(c.level, 1);
      expect(c.arenaSize, 60);
      expect(c.bots, 3);
      expect(c.targetPercent, 15.0);
      expect(c.botSkill, closeTo(0.41, 1e-9));
    });

    test('difficulty never decreases from one level to the next', () {
      var prev = LevelConfig.forLevel(1);
      for (var l = 2; l <= 60; l++) {
        final c = LevelConfig.forLevel(l);
        expect(c.level, l);
        expect(c.bots, greaterThanOrEqualTo(prev.bots), reason: 'bots at level $l');
        expect(c.targetPercent, greaterThanOrEqualTo(prev.targetPercent), reason: 'target at level $l');
        expect(c.botSkill, greaterThanOrEqualTo(prev.botSkill), reason: 'skill at level $l');
        expect(c.arenaSize, greaterThanOrEqualTo(prev.arenaSize), reason: 'arena at level $l');
        prev = c;
      }
    });

    test('difficulty strictly increases over the early levels', () {
      for (var l = 1; l < 7; l++) {
        final a = LevelConfig.forLevel(l), b = LevelConfig.forLevel(l + 1);
        expect(b.bots, greaterThan(a.bots));
        expect(b.targetPercent, greaterThan(a.targetPercent));
        expect(b.botSkill, greaterThan(a.botSkill));
      }
    });

    test('values are capped', () {
      for (final l in [10, 11, 25, 100, 999]) {
        final c = LevelConfig.forLevel(l);
        expect(c.bots, lessThanOrEqualTo(9));
        expect(c.targetPercent, lessThanOrEqualTo(55.0));
        expect(c.botSkill, lessThanOrEqualTo(0.97));
        expect(c.arenaSize, lessThanOrEqualTo(96));
      }
      final top = LevelConfig.forLevel(999);
      expect(top.bots, 9);
      expect(top.targetPercent, 55.0);
      expect(top.botSkill, 0.97);
      expect(top.arenaSize, 96);
    });

    test('bot count fits within the arena player limit', () {
      // Player ids are 1..bots+1 and Arena supports 16 ids.
      expect(LevelConfig.forLevel(999).bots + 1, lessThanOrEqualTo(16));
    });

    test('levels below 1 are clamped to level 1', () {
      for (final l in [0, -1, -50]) {
        final c = LevelConfig.forLevel(l);
        expect(c.level, 1);
        expect(c.bots, LevelConfig.forLevel(1).bots);
        expect(c.targetPercent, LevelConfig.forLevel(1).targetPercent);
      }
    });

    test('target is always reachable (below 100%) and positive', () {
      for (var l = 1; l <= 40; l++) {
        final c = LevelConfig.forLevel(l);
        expect(c.targetPercent, inExclusiveRange(0, 100));
        expect(c.botSkill, inExclusiveRange(0, 1));
      }
    });
  });

  test('speed settings are ordered slow < normal < fast', () {
    expect(speedCellsPerSecond(SpeedSetting.slow), lessThan(speedCellsPerSecond(SpeedSetting.normal)));
    expect(speedCellsPerSecond(SpeedSetting.normal), lessThan(speedCellsPerSecond(SpeedSetting.fast)));
    expect(speedCellsPerSecond(SpeedSetting.normal), 6.3);
  });
}
