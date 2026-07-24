import 'package:flutter/material.dart';

import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class GenerateButton extends StatelessWidget {
  const GenerateButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final status = LiveEditorScope.of(context).generateStatus;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: status == GenerateStatus.processing ? null : onPressed,
        icon: switch (status) {
          GenerateStatus.processing => const SizedBox.square(
            dimension: 19,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.black,
            ),
          ),
          GenerateStatus.success => const Icon(Icons.check_rounded),
          GenerateStatus.failed => const Icon(Icons.refresh_rounded),
          GenerateStatus.idle => const Icon(Icons.ios_share_rounded),
        },
        label: Text(switch (status) {
          GenerateStatus.processing => '正在封装动态记忆…',
          GenerateStatus.success => '生成成功',
          GenerateStatus.failed => '生成失败，重试',
          GenerateStatus.idle => '生成 AfterFrame Live',
        }),
      ),
    );
  }
}
