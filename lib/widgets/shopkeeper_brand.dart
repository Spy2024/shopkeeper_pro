import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Reusable Shopkeeper Pro monogram: shopping cart + rising chart/arrow.
class ShopkeeperBrandMark extends StatelessWidget {
  final double size;
  final bool showName;

  const ShopkeeperBrandMark({
    super.key,
    this.size = 72,
    this.showName = false,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: AppTheme.teal.withValues(alpha: 0.85), width: 1.4),
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
          Icon(
            Icons.shopping_cart_rounded,
            size: size * 0.58,
            color: Colors.white,
          ),
          Positioned(
            right: size * 0.07,
            top: size * 0.07,
            child: Container(
              padding: EdgeInsets.all(size * 0.025),
              decoration: BoxDecoration(
                color: AppTheme.ink,
                borderRadius: BorderRadius.circular(size * 0.10),
              ),
              child: Icon(
                Icons.trending_up_rounded,
                size: size * 0.34,
                color: AppTheme.gold,
              ),
            ),
          ),
          Positioned(
            right: size * 0.08,
            bottom: size * 0.07,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.06,
                vertical: size * 0.025,
              ),
              decoration: BoxDecoration(
                color: AppTheme.teal,
                borderRadius: BorderRadius.circular(size * 0.07),
                border: Border.all(color: Colors.white, width: 0.8),
              ),
              child: Text(
                'SP',
                style: TextStyle(
                  color: AppTheme.ink,
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
                color: AppTheme.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
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
