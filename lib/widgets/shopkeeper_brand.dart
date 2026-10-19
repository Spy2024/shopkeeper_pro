import 'package:flutter/material.dart';

/// Shopkeeper Pro brand mark: a shopping cart with a rising chart/arrow.
class ShopkeeperBrandMark extends StatelessWidget {
  final double size;
  final bool showName;

  const ShopkeeperBrandMark({
    super.key,
    this.size = 72,
    this.showName = false,
  });

  static const _navy = Color(0xFF0B3D91);
  static const _teal = Color(0xFF14B8A6);
  static const _gold = Color(0xFFFFBF24);

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: _teal.withValues(alpha: 0.75)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: size * 0.10,
            bottom: size * 0.12,
            child: Icon(
              Icons.shopping_cart_rounded,
              size: size * 0.62,
              color: Colors.white,
            ),
          ),
          Positioned(
            right: size * 0.08,
            top: size * 0.08,
            child: Icon(
              Icons.trending_up_rounded,
              size: size * 0.43,
              color: _gold,
            ),
          ),
          Positioned(
            right: size * 0.08,
            bottom: size * 0.07,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.055,
                vertical: size * 0.018,
              ),
              decoration: BoxDecoration(
                color: _teal,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'SP',
                style: TextStyle(
                  color: _navy,
                  fontSize: size * 0.12,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!showName) return mark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 12),
        Text(
          'Shopkeeper Pro',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: _navy,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'POS  •  INVENTORY  •  FINANCE',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                letterSpacing: 1.1,
              ),
        ),
      ],
    );
  }
}
