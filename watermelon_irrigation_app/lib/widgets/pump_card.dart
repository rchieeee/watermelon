import 'package:flutter/material.dart';

import '../state/field_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'layout.dart';

/// Pump status with one button that matches it: "Turn pump on" while the
/// pump is off, "Turn pump off" while it runs. Both states share one layout.
class PumpCard extends StatelessWidget {
  const PumpCard({super.key, required this.controller});
  final FieldController controller;

  Future<void> _send(BuildContext context, Future<void> Function() command) async {
    try {
      await command();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The command could not be sent. Check the internet connection.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = controller.pumpOn;
    final c = controller;
    final _PumpLook look;
    if (on) {
      look = _PumpLook(
        accent: Palette.water,
        icon: Icons.water_drop,
        title: 'Pump is on',
        message: c.stopRequested
            ? 'Off command sent. Waiting for the field controller to turn the pump off.'
            : 'Watering now. If you turned it on, it stays on until you tap below. '
                'Automatic watering pauses for 1 hour after you turn it off.',
        button: Palette.flesh,
        buttonTint: Palette.fleshTint,
        buttonIcon: Icons.stop_circle_outlined,
        label: c.stopRequested ? 'Turning off…' : 'Turn pump off',
        busy: c.stopRequested,
        onPressed: () => _send(context, c.stopWatering),
      );
    } else {
      look = _PumpLook(
        accent: Palette.leaf,
        icon: Icons.water_drop_outlined,
        title: 'Pump is off',
        message: c.startRequested
            ? 'On command sent. Waiting for the field controller to start the pump.'
            : c.startNotConfirmed
                ? 'The pump did not start. Check that the field controller is '
                    'powered and online.'
                : 'Tap below to turn the pump on. It stays on until you tap '
                    'Turn pump off.',
        button: Palette.leaf,
        buttonTint: Palette.leafTint,
        buttonIcon: Icons.play_circle_outline,
        label: c.startRequested ? 'Turning on…' : 'Turn pump on',
        busy: c.startRequested,
        onPressed: () => _send(context, c.startWatering),
      );
    }
    // No live reading lately: say so instead of trusting the old pump state.
    final last = c.latest?.timestamp;
    if (!c.controllerOnline && !look.busy && last != null) {
      return _PumpPanel(
        look: look.withMessage(
          'Field controller offline. Last reading: ${Fmt.updated(last)}. '
          'Check that the ESP32 is powered and on Wi-Fi.',
        ),
        warning: true,
      );
    }
    return _PumpPanel(look: look, warning: !on && c.startNotConfirmed && !c.startRequested);
  }
}

class _PumpLook {
  const _PumpLook({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.button,
    required this.buttonTint,
    required this.buttonIcon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final Color button;
  final Color buttonTint;
  final IconData buttonIcon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  _PumpLook withMessage(String text) => _PumpLook(
        accent: accent,
        icon: icon,
        title: title,
        message: text,
        button: button,
        buttonTint: buttonTint,
        buttonIcon: buttonIcon,
        label: label,
        busy: busy,
        onPressed: onPressed,
      );
}

class _PumpPanel extends StatelessWidget {
  const _PumpPanel({required this.look, required this.warning});
  final _PumpLook look;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      borderColor: look.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(look.icon, color: look.accent, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(look.title, style: t.titleLarge)),
          ]),
          const SizedBox(height: 4),
          Text(
            look.message,
            style: t.bodyMedium?.copyWith(color: warning ? Palette.flesh : Palette.muted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: look.busy ? null : look.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: look.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: look.buttonTint,
                disabledForegroundColor: look.button,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              icon: look.busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: look.button),
                    )
                  : Icon(look.buttonIcon, size: 26),
              label: Text(look.label),
            ),
          ),
        ],
      ),
    );
  }
}
