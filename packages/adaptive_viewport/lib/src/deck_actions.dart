import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An upright bar's action, expanded onto a half-fold deck.
@immutable
class DeckAction {
  const DeckAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
}

enum DeckActionForm { labelled, icons, menu }

/// Uses the room left on the deck for labels, then icons, then an overflow menu.
/// Colours come from the host theme, not from a particular app's brand.
class DeckActionPanel extends StatelessWidget {
  const DeckActionPanel({super.key, required this.actions});

  final List<DeckAction> actions;

  static const tileWidth = 104.0;
  static const minimumTileWidth = 76.0;
  static const tileHeight = 72.0;
  static const iconExtent = 48.0;
  static const gap = 8.0;

  static double heightFor(
    int count,
    double width, {
    bool labelled = true,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (count == 0) return 0;
    final w = labelled ? minimumTileWidth : iconExtent;
    final h = labelled ? _labelHeight(textScaler) : iconExtent;
    final columns = math.max(1, ((width + gap) / (w + gap)).floor());
    final rows = (count / columns).ceil();
    return rows * h + (rows - 1) * gap;
  }

  static double _labelHeight(TextScaler scaler) =>
      math.max(tileHeight, 36 + 2 * scaler.scale(12) * 1.2);

  static DeckActionForm formFor(
    int count,
    Size space, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (count == 0 ||
        (space.width >= minimumTileWidth &&
            heightFor(count, space.width, textScaler: textScaler) <=
                space.height)) {
      return DeckActionForm.labelled;
    }
    if (space.width >= iconExtent &&
        heightFor(count, space.width, labelled: false) <= space.height) {
      return DeckActionForm.icons;
    }
    return DeckActionForm.menu;
  }

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final form = formFor(actions.length, box.biggest, textScaler: scaler);
        if (form == DeckActionForm.menu) return _menu(context, box.maxWidth);
        final columns = math.max(
          1,
          ((box.maxWidth + gap) / (tileWidth + gap)).floor(),
        );
        final rows = (actions.length / columns).ceil();
        final wideLabelsFit = box.maxWidth >= tileWidth &&
            rows * _labelHeight(scaler) + (rows - 1) * gap <= box.maxHeight;
        return Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                _tile(
                  context,
                  action,
                  labelled: form == DeckActionForm.labelled,
                  labelWidth: wideLabelsFit ? tileWidth : minimumTileWidth,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    DeckAction action, {
    required bool labelled,
    double labelWidth = tileWidth,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final colour = action.onPressed == null
        ? scheme.onSurface.withValues(alpha: 0.38)
        : action.selected
            ? scheme.primary
            : scheme.onSurface;
    return SizedBox(
      width: labelled ? labelWidth : iconExtent,
      height: labelled
          ? _labelHeight(MediaQuery.textScalerOf(context))
          : iconExtent,
      child: Tooltip(
        message: action.label,
        child: Semantics(
          button: true,
          enabled: action.onPressed != null,
          selected: action.selected,
          child: Material(
            color: action.selected
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: action.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, size: 22, color: colour),
                    if (labelled) ...[
                      const SizedBox(height: 4),
                      Text(
                        action.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: colour,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, double width) {
    final slots = math.max(1, ((width + gap) / (iconExtent + gap)).floor());
    final shown = math.min(slots - 1, actions.length - 1);
    final rest = actions.sublist(shown);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            for (final action in actions.take(shown))
              _tile(context, action, labelled: false),
            SizedBox.square(
              dimension: iconExtent,
              child: PopupMenuButton<int>(
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                icon: const Icon(Icons.more_vert),
                onSelected: (index) => rest[index].onPressed?.call(),
                itemBuilder: (_) => [
                  for (var i = 0; i < rest.length; i++)
                    PopupMenuItem(
                      value: i,
                      enabled: rest[i].onPressed != null,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(rest[i].icon),
                        title: Text(rest[i].label),
                        selected: rest[i].selected,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
