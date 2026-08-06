import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';

/// Panel lateral de categorías (ui-spec §2.3: "nombre + contador").
/// `selectedCategoryId: null` significa la pseudo-categoría "Todas".
class CategoryPanel extends StatelessWidget {
  const CategoryPanel({
    super.key,
    required this.categories,
    required this.allCount,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final List<CategoryWithCount> categories;
  final int allCount;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      children: [
        _CategoryTile(
          key: const Key('categoryTile.all'),
          label: l10n.categoryAllLabel,
          count: allCount,
          selected: selectedCategoryId == null,
          onTap: () => onSelected(null),
        ),
        const Divider(height: 1, color: IptvColors.border),
        for (final category in categories)
          _CategoryTile(
            key: Key('categoryTile.${category.category.id}'),
            label: category.category.name,
            count: category.channelCount,
            selected: selectedCategoryId == category.category.id,
            onTap: () => onSelected(category.category.id),
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: IptvColors.surface,
      title: Text(label, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '$count',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: IptvColors.textSecondary),
      ),
      onTap: onTap,
    );
  }
}
