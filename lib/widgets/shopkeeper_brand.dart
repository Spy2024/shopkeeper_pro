import 'package:flutter/material.dart';

/// Reusable Shopkeeper Pro monochrome monogram.
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
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: const Color(0xFF333333)),
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
          Icon(Icons.storefront_rounded, size: size * 0.55, color: Colors.white),
          Positioned(
            right: size * 0.13,
            bottom: size * 0.10,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.055,
                vertical: size * 0.018,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF171717),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Text(
                'SP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.12,
                  fontWeight: FontWeight.w800,
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
