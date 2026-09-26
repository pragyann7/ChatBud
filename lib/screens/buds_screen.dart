import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:chatbud/models/bud.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:provider/provider.dart';

class BudsScreen extends StatelessWidget {
  const BudsScreen({super.key});

  IconData _getIconData(String iconName) {
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

  void _showAddOrEditBudDialog(BuildContext context, {Bud? bud}) {
    final budRepo = context.read<BudRepository>();
    final isEditing = bud != null;

    final nameController = TextEditingController(text: bud?.name ?? "");
    final promptController = TextEditingController(text: bud?.systemPrompt ?? "");
    String selectedIcon = bud?.iconName ?? 'smart_toy';

    final icons = [
      {'name': 'smart_toy', 'icon': Icons.smart_toy_rounded},
      {'name': 'code', 'icon': Icons.code_rounded},
      {'name': 'school', 'icon': Icons.school_rounded},
      {'name': 'palette', 'icon': Icons.palette_rounded},
      {'name': 'psychology', 'icon': Icons.psychology_rounded},
      {'name': 'terminal', 'icon': Icons.terminal_rounded},
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? "Edit Bud" : "Create Custom Bud"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Bud Name",
                        hintText: "e.g., Python Tutor Bud",
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: promptController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: "System Prompt",
                        hintText: "You are an expert in...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Select Icon",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: icons.map((item) {
                        final iconName = item['name'] as String;
                        final iconData = item['icon'] as IconData;
                        final isSelected = selectedIcon == iconName;

                        return InkWell(
                          onTap: () {
                            setDialogState(() {
                              selectedIcon = iconName;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.surfaceVariant,
                            child: Icon(
                              iconData,
                              size: 18,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final prompt = promptController.text.trim();
                    if (name.isEmpty || prompt.isEmpty) return;

                    final updatedBud = Bud(
                      id: bud?.id ?? Isar.autoIncrement,
                      name: name,
                      systemPrompt: prompt,
                      iconName: selectedIcon,
                      isDefault: bud?.isDefault ?? false,
                    );

                    try {
                      await budRepo.saveBud(updatedBud);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to save Bud: $e")),
                        );
                      }
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Text(isEditing ? "Save Changes" : "Create Bud"),
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
    final budRepo = context.read<BudRepository>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage AI Buds"),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOrEditBudDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text("New Bud"),
      ),
      body: StreamBuilder<List<Bud>>(
        stream: budRepo.watchBuds(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final buds = snapshot.data!;
          if (buds.isEmpty) {
            return const Center(
              child: Text("No Buds available. Tap + to create one."),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: buds.length,
            itemBuilder: (context, index) {
              final bud = buds[index];
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor: theme.colorScheme.onPrimaryContainer,
                            child: Icon(_getIconData(bud.iconName)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bud.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (bud.isDefault)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "Built-in Default",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _showAddOrEditBudDialog(context, bud: bud),
                          ),
                          if (!bud.isDefault)
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: theme.colorScheme.error,
                              ),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Delete Bud"),
                                    content: Text("Are you sure you want to delete '${bud.name}'?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text("Cancel"),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.colorScheme.error,
                                          foregroundColor: theme.colorScheme.onError,
                                        ),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text("Delete"),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  try {
                                    await budRepo.deleteBud(bud.id);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Failed to delete Bud: $e")),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          bud.systemPrompt,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
