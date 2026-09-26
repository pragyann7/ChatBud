import 'package:flutter/material.dart';
import 'package:chatbud/models/bud.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:provider/provider.dart';

class BudSelectorChip extends StatelessWidget {
  final Bud? activeBud;
  final ValueChanged<Bud?> onBudSelected;

  const BudSelectorChip({
    super.key,
    required this.activeBud,
    required this.onBudSelected,
  });

  IconData _getIconData(String? iconName) {
    if (iconName == null) return Icons.memory_rounded;
    switch (iconName) {
      case 'code':
        return Icons.code_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'palette':
        return Icons.palette_rounded;
      case 'psychology':
        return Icons.psychology_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'smart_toy':
      default:
        return Icons.smart_toy_rounded;
    }
  }

  void _showBudSelectionSheet(BuildContext context) {
    final budRepo = Provider.of<BudRepository>(context, listen: false);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.psychology_rounded, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        "Switch AI Persona (Bud)",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<List<Bud>>(
                    stream: budRepo.watchBuds(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      final buds = snapshot.data!;

                      return ListView(
                        controller: scrollController,
                        children: [
                          // "No Bud / Raw LLM" Option
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: activeBud == null
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceVariant,
                              foregroundColor: activeBud == null
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurfaceVariant,
                              child: const Icon(Icons.memory_rounded, size: 20),
                            ),
                            title: const Text(
                              "No Bud / Raw LLM",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              "Standard model completion without custom system prompt persona",
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: activeBud == null
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            onTap: () {
                              onBudSelected(null);
                              Navigator.pop(context);
                            },
                          ),
                          const Divider(height: 1, indent: 64),

                          // Dynamic Bud List
                          ...buds.map((bud) {
                            final isSelected = activeBud?.id == bud.id;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceVariant,
                                foregroundColor: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurfaceVariant,
                                child: Icon(
                                  _getIconData(bud.iconName),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                bud.name,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                bud.systemPrompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                              onTap: () {
                                onBudSelected(bud);
                                Navigator.pop(context);
                              },
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = activeBud?.name ?? "No Bud (Raw LLM)";
    final icon = _getIconData(activeBud?.iconName);

    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: activeBud != null
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(
        name,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: activeBud != null
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: activeBud != null
          ? theme.colorScheme.primaryContainer.withOpacity(0.4)
          : theme.colorScheme.surfaceVariant.withOpacity(0.5),
      side: BorderSide(
        color: activeBud != null
            ? theme.colorScheme.primary.withOpacity(0.2)
            : theme.colorScheme.outline.withOpacity(0.2),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      onPressed: () => _showBudSelectionSheet(context),
    );
  }
}
