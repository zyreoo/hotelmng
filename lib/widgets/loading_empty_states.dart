import 'package:flutter/material.dart';

/// Skeleton placeholder for list loading (e.g. bookings, clients).
class SkeletonListLoader extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsets? padding;

  const SkeletonListLoader({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 120,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    // ListView must have bounded height (e.g. when used in SliverToBoxAdapter).
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final boundedHeight = maxHeight.isFinite ? maxHeight : 600.0;
        return SizedBox(
          height: boundedHeight,
          child: ListView.builder(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              return _SkeletonCard(
                height: itemHeight,
                baseColor: baseColor,
                highlightColor: highlightColor,
              );
            },
          ),
        );
      },
    );
  }
}

/// Static skeleton card (no animation) to avoid rebuilds during device update.
/// Clips content when given a tight height to prevent overflow.
class _SkeletonCard extends StatelessWidget {
  final double height;
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonCard({
    required this.height,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveHeight = constraints.maxHeight.isFinite && constraints.maxHeight < height
            ? constraints.maxHeight
            : height;
        final innerHeight = effectiveHeight - 32; // minus padding
        final useCompactLayout = innerHeight < 85; // full column needs ~83px
        final _placeholder = (double h, [double? w]) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: highlightColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        );
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: effectiveHeight,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRect(
              child: useCompactLayout
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _placeholder((innerHeight * 0.35).clamp(8.0, 20.0), 120),
                        SizedBox(height: (innerHeight * 0.2).clamp(4.0, 10.0)),
                        _placeholder((innerHeight * 0.35).clamp(8.0, 20.0), 80),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _placeholder(18, 160),
                        const SizedBox(height: 8),
                        _placeholder(14, 120),
                        const SizedBox(height: 16),
                        Container(
                          height: 1,
                          color: highlightColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _placeholder(14)),
                            const SizedBox(width: 16),
                            Expanded(child: _placeholder(14)),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Centered empty state with icon and message.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    this.icon = Icons.inbox_rounded,
    required this.title,
    this.subtitle,
    this.iconSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
