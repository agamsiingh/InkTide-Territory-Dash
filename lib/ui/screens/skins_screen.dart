import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/progression.dart';
import '../../game/sim/skins.dart';
import '../blob_painter.dart';
import '../palette.dart';
import '../widgets.dart';
import 'capsule_screen.dart';

class SkinsScreen extends StatefulWidget {
  const SkinsScreen({super.key});

  @override
  State<SkinsScreen> createState() => _SkinsScreenState();
}

class _SkinsScreenState extends State<SkinsScreen> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final TickerClock _clock = TickerClock(this);
  String? _previewId;

  String _lockedMessage(Skin skin, int coins) {
    if (skin.unlockCountries > 0) {
      final left = skin.unlockCountries - Services.of(context).store.countriesCompleted;
      return 'Complete $left more ${left == 1 ? 'country' : 'countries'} on the world map to unlock ${skin.name}.';
    }
    if (skin.unlockLevel > 0) return 'Reach level ${skin.unlockLevel} to unlock ${skin.name}.';
    if (skin.unlockRank > 0) return 'Reach rank ${skin.unlockRank} to unlock ${skin.name}.';
    final a = skin.unlockAchievement == null ? null : achievementById(skin.unlockAchievement!);
    if (a != null) return 'Earn "${a.title}" (${a.description.toLowerCase()}) to unlock ${skin.name}.';
    if (skin.eventReward) return 'Win ${skin.name} on the Ink Festival reward track.';
    if (skin.gemCost > 0) return 'You need ${skin.gemCost - Services.of(context).store.gems} more gems.';
    return 'You need ${Services.of(context).store.priceOf(skin) - coins} more coins.';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opening the shop counts as seeing today's deal.
    // (After the frame: it notifies listeners, which must not happen mid-build.)
    final store = Services.of(context).store;
    WidgetsBinding.instance.addPostFrameCallback((_) => store.markFeaturedSeen());
    if (_intro.status != AnimationStatus.dismissed) return;
    if (reduceMotion(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _clock.start();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final store = s.store;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const PaintBackground(animate: false),
        SafeArea(
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) => Column(children: [
              StaggerIn(
                animation: _intro,
                end: 0.5,
                offset: const Offset(0, -24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Row(children: [
                    RoundIconButton(
                      key: const Key('backButton'),
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () {
                        s.fx.tap();
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('SKINS', style: kTitle.copyWith(fontSize: 34)),
                      ),
                    ),
                    StatPill(icon: Icons.monetization_on_rounded, value: '${store.coins}'),
                    const SizedBox(width: 6),
                    StatPill(icon: Icons.diamond_rounded, value: '${store.gems}', iconColor: 0xFFE040FB),
                  ]),
                ),
              ),
              StaggerIn(
                animation: _intro,
                start: 0.1,
                end: 0.6,
                scale: 0.9,
                child: _Preview(
                  skin: skinById(_previewId ?? store.selectedSkin),
                  canUnequip: store.selectedSkin != kSkins.first.id &&
                      (_previewId ?? store.selectedSkin) == store.selectedSkin,
                  canEquip: store.isUnlocked(skinById(_previewId ?? store.selectedSkin)) &&
                      (_previewId ?? store.selectedSkin) != store.selectedSkin,
                  onEquip: () {
                    s.fx.tap();
                    store.selectSkin(skinById(_previewId!));
                  },
                  onUnequip: () {
                    s.fx.tap();
                    store.unequipSkin();
                  },
                  status: () {
                    final sk = skinById(_previewId ?? store.selectedSkin);
                    if (store.selectedSkin == sk.id) return 'EQUIPPED';
                    if (store.isUnlocked(sk)) return 'OWNED';
                    return store.requirementText(sk);
                  }(),
                  time: _clock.time,
                ),
              ),
              _FeaturedBanner(
                skin: store.featured,
                owned: store.isUnlocked(store.featured),
                price: store.priceOf(store.featured),
                left: featuredRemaining(store.now),
                onTap: () {
                  s.fx.tap();
                  setState(() => _previewId = store.featured.id);
                },
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: kSkins.length,
                  itemBuilder: (context, i) {
                    final skin = kSkins[i];
                    final unlocked = store.isUnlocked(skin);
                    final selected = store.selectedSkin == skin.id;
                    final delay = math.min(i, 8) * 0.06;
                    return StaggerIn(
                      animation: _intro,
                      start: delay,
                      end: delay + 0.5,
                      scale: 0.85,
                      curve: Curves.easeOutBack,
                      child: _SkinCard(
                        key: Key('skin_${skin.id}'),
                        skin: skin,
                        unlocked: unlocked,
                        selected: selected,
                        affordable: store.canBuy(skin) || store.canBuyWithGems(skin),
                        isNew: store.isNewSkin(skin),
                        price: store.priceOf(skin),
                        deal: store.isFeatured(skin) && !unlocked,
                        time: selected ? _clock.time : null,
                        onTap: () async {
                          setState(() => _previewId = skin.id);
                          if (unlocked) {
                            s.fx.tap();
                            await store.markSkinSeen(skin);
                            await store.selectSkin(skin);
                          } else if (store.canBuyWithGems(skin)) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Unlock ${skin.name}?'),
                                content: Text('Spend ${skin.gemCost} gems?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Not now')),
                                  TextButton(
                                      key: const Key('confirmBuy'),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Unlock')),
                                ],
                              ),
                            );
                            if (ok == true && await store.buySkinWithGems(skin) && context.mounted) {
                              await CapsuleScreen.show(context, [skin]);
                            }
                          } else if (store.canBuy(skin)) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Unlock ${skin.name}?'),
                                content: Text('Spend ${store.priceOf(skin)} coins?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Not now')),
                                  TextButton(
                                      key: const Key('confirmBuy'),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Unlock')),
                                ],
                              ),
                            );
                            if (ok == true && await store.buySkin(skin) && context.mounted) {
                              await CapsuleScreen.show(context, [skin]);
                            }
                          } else {
                            s.fx.tap();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                content: Text(_lockedMessage(skin, store.coins)),
                              ));
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SkinCard extends StatefulWidget {
  const _SkinCard({
    super.key,
    required this.skin,
    required this.unlocked,
    required this.selected,
    required this.affordable,
    required this.onTap,
    required this.price,
    this.deal = false,
    this.isNew = false,
    this.time,
  });

  final Skin skin;
  final bool unlocked;
  final bool selected;
  final bool affordable;
  final int price;
  final bool deal;
  final bool isNew;
  final VoidCallback onTap;
  final ValueListenable<double>? time;

  @override
  State<_SkinCard> createState() => _SkinCardState();
}

class _SkinCardState extends State<_SkinCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin, unlocked = widget.unlocked, selected = widget.selected;
    final String footer;
    if (selected) {
      footer = 'EQUIPPED';
    } else if (unlocked) {
      footer = 'SELECT';
    } else if (skin.cost > 0) {
      footer = '${widget.price}';
    } else if (skin.gemCost > 0) {
      footer = '${skin.gemCost}';
    } else if (skin.eventReward) {
      footer = 'EVENT';
    } else if (skin.unlockLevel > 0) {
      footer = 'LEVEL ${skin.unlockLevel}';
    } else if (skin.unlockRank > 0) {
      footer = 'RANK ${skin.unlockRank}';
    } else if (skin.unlockCountries > 0) {
      footer = '${skin.unlockCountries} COUNTRIES';
    } else {
      footer = 'AWARD';
    }
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.93 : (selected ? 1.03 : 1),
        duration: Duration(milliseconds: _down ? 80 : 320),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? const Color(Palette.green) : const Color(0x00000000), width: 4),
            boxShadow: [
              const BoxShadow(color: Color(0x5516204A), offset: Offset(0, 6)),
              // Equipped card glows; only one card ever has the blurred shadow.
              if (selected) BoxShadow(color: fade(skin.color, 0.55), blurRadius: 18, spreadRadius: 1),
            ],
          ),
          child: Column(children: [
            Expanded(
              child: Stack(alignment: Alignment.center, children: [
                Opacity(
                  opacity: unlocked ? 1 : 0.45,
                  child: BlobAvatar(
                    skin: skin,
                    size: 96,
                    mood: selected ? Mood.excited : Mood.happy,
                    time: widget.time,
                    seed: skin.id.hashCode,
                  ),
                ),
                if (!unlocked) const Icon(Icons.lock_rounded, size: 40, color: Color(Palette.ink)),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: col(rarityColors(skin.rarity).$1), borderRadius: BorderRadius.circular(8)),
                    child: Text(rarityName(skin.rarity).toUpperCase(), style: kTitle.copyWith(fontSize: 11, shadows: [])),
                  ),
                ),
                if (widget.deal)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      key: Key('deal_${skin.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      color: const Color(0xFFFF3B6B),
                      child: Text('50% OFF',
                          textAlign: TextAlign.center, style: kTitle.copyWith(fontSize: 13, shadows: [])),
                    ),
                  ),
                if (widget.isNew)
                  Positioned(
                    right: 4,
                    top: 2,
                    child: Transform.rotate(
                      angle: 0.3,
                      child: Text('NEW',
                          key: Key('new_${skin.id}'),
                          style: kTitle.copyWith(fontSize: 18, color: const Color(0xFFFF5A7A))),
                    ),
                  ),
              ]),
            ),
            Text(skin.name, style: kTitle.copyWith(fontSize: 20, color: const Color(Palette.ink), shadows: [])),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.symmetric(vertical: 6),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Color(selected
                    ? Palette.green
                    : unlocked
                        ? Palette.skyDeep
                        : widget.affordable
                            ? Palette.yellow
                            : 0xFFB0B8C8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (!unlocked && skin.gemCost > 0)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.diamond_rounded, size: 18, color: Colors.white),
                  ),
                if (!unlocked && skin.cost > 0)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.monetization_on_rounded, size: 18, color: Colors.white),
                  ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(footer, maxLines: 1, style: kTitle.copyWith(fontSize: 16)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Large animated preview of the last tapped skin with its status.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.skin,
    required this.status,
    required this.time,
    this.canEquip = false,
    this.canUnequip = false,
    this.onEquip,
    this.onUnequip,
  });
  final Skin skin;
  final String status;
  final ValueListenable<double> time;
  final bool canEquip;
  final bool canUnequip;
  final VoidCallback? onEquip;
  final VoidCallback? onUnequip;

  @override
  Widget build(BuildContext context) {
    final shape = switch (skin.shape) {
      BodyShape.cube => 'Cube',
      BodyShape.round => 'Round',
      BodyShape.bean => 'Bean',
      BodyShape.ghost => 'Ghost',
    };
    return Container(
      key: const Key('skinPreview'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      decoration: BoxDecoration(color: const Color(0x3316204A), borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        RepaintBoundary(child: BlobAvatar(skin: skin, size: 104, mood: Mood.excited, time: time, seed: 5)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(skin.name, style: kTitle.copyWith(fontSize: 26)),
            Text('${rarityName(skin.rarity)}  •  $shape body', style: bodyStyle(14, color: Colors.white)),
            const SizedBox(height: 4),
            Text(status, key: const Key('previewStatus'), style: kTitle.copyWith(fontSize: 16, color: const Color(Palette.gold))),
          ]),
        ),
        if (canEquip)
          ChunkyButton(
              key: const Key('equipButton'), label: 'EQUIP', width: 96, height: 44, fontSize: 18, onTap: onEquip),
        if (canUnequip)
          ChunkyButton(
              key: const Key('unequipButton'),
              label: 'REMOVE',
              color: Palette.pink,
              dark: 0xFFC92A7A,
              width: 104,
              height: 44,
              fontSize: 18,
              onTap: onUnequip),
      ]),
    );
  }
}


/// Today's half-price skin, with a countdown to the next one.
class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({
    required this.skin,
    required this.owned,
    required this.price,
    required this.left,
    required this.onTap,
  });
  final Skin skin;
  final bool owned;
  final int price;
  final Duration left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = left.inHours, m = left.inMinutes % 60;
    return GestureDetector(
      key: const Key('featuredBanner'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF5A8A), Color(0xFFFF9A3C)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 4))],
        ),
        child: Row(children: [
          BlobAvatar(skin: skin, size: 52, mood: Mood.excited),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('TODAY: ${skin.name.toUpperCase()}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: kTitle.copyWith(fontSize: 19)),
              Text(owned ? 'You own it!' : '50% OFF  •  $price coins',
                  key: const Key('featuredText'), style: bodyStyle(13, color: Colors.white)),
            ]),
          ),
          Text('${h}h ${m}m', key: const Key('featuredTimer'), style: kTitle.copyWith(fontSize: 16)),
        ]),
      ),
    );
  }
}
