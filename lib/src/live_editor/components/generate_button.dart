import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class GenerateButton extends StatefulWidget {
  const GenerateButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends State<GenerateButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final status = LiveEditorScope.of(context).generateStatus;
    final l10n = context.l10n;
    final enabled =
        widget.onPressed != null && status != GenerateStatus.processing;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Listener(
        onPointerDown: enabled ? (_) => _setPressed(true) : null,
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? .975 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : .5,
            duration: const Duration(milliseconds: 180),
            child: Container(
              height: 72,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE3FF68), AfterFrameColors.lime],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AfterFrameColors.lime.withValues(
                      alpha: _pressed ? .12 : .23,
                    ),
                    blurRadius: _pressed ? 12 : 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled ? widget.onPressed : null,
                  borderRadius: BorderRadius.circular(36),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      switch (status) {
                        GenerateStatus.processing => const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                        GenerateStatus.success => const Icon(
                          Icons.check_rounded,
                          color: Colors.black,
                        ),
                        GenerateStatus.failed => const Icon(
                          Icons.refresh_rounded,
                          color: Colors.black,
                        ),
                        GenerateStatus.idle => const Icon(
                          Icons.motion_photos_on_rounded,
                          color: Colors.black,
                        ),
                      },
                      const SizedBox(width: 11),
                      Text(
                        switch (status) {
                          GenerateStatus.processing => l10n.text(
                            'creatingLive',
                          ),
                          GenerateStatus.success => l10n.text('createdLive'),
                          GenerateStatus.failed => l10n.text('retryCreate'),
                          GenerateStatus.idle => l10n.text('createLive'),
                        },
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
