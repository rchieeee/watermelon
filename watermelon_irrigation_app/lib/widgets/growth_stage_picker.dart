import 'package:flutter/material.dart';

import '../models/growth_stage.dart';
import '../state/field_controller.dart';
import '../theme/app_theme.dart';

/// The three growth stages as cards at the top of the home screen. Tapping a
/// stage saves it; the current stage is highlighted.
class GrowthStageButtons extends StatefulWidget {
  const GrowthStageButtons({super.key, required this.controller});
  final FieldController controller;

  @override
  State<GrowthStageButtons> createState() => _GrowthStageButtonsState();
}

class _GrowthStageButtonsState extends State<GrowthStageButtons> {
  /// The stage being saved, so its card can show progress.
  String? _saving;

  Future<void> _choose(GrowthStage stage) async {
    final current = widget.controller.latest?.growthStage;
    if (_saving != null || stage.value == current) return;
    setState(() => _saving = stage.value);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.setGrowthStage(stage.value);
      messenger.showSnackBar(SnackBar(content: Text('Growth stage set to ${stage.label}.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('The growth stage could not be saved. Check the internet connection.'),
      ));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final current = widget.controller.latest?.growthStage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Growth stage', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Choose the stage the watermelons are in now. '
            'The model uses it for its advice.',
            style: t.bodySmall?.copyWith(color: Palette.muted)),
        const SizedBox(height: 8),
        for (final (i, stage) in growthStages.indexed) ...[
          if (i > 0) const SizedBox(height: 6),
          _StageOption(
            number: i + 1,
            stage: stage,
            selected: stage.value == current,
            saving: stage.value == _saving,
            onTap: () => _choose(stage),
          ),
        ],
      ],
    );
  }
}

class _StageOption extends StatelessWidget {
  const _StageOption({
    required this.number,
    required this.stage,
    required this.selected,
    required this.saving,
    required this.onTap,
  });

  final int number;
  final GrowthStage stage;
  final bool selected;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Palette.leafTint : Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? Palette.rind : Palette.line, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: selected ? Palette.rind : Palette.stoneTint,
                  child: Text('$number',
                      style: t.labelMedium?.copyWith(
                          color: selected ? Colors.white : Palette.ink,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stage.label,
                          style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      Text(stage.description,
                          style: t.bodySmall?.copyWith(color: Palette.muted)),
                    ],
                  ),
                ),
                if (saving) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Palette.rind),
                  ),
                ] else if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: Palette.rind, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
