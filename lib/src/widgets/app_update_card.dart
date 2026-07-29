import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../services/app_update_service.dart';
import '../theme.dart';

class AppUpdateCard extends StatefulWidget {
  const AppUpdateCard({super.key, this.service = const AppUpdateService()});

  final AppUpdateService service;

  @override
  State<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<AppUpdateCard>
    with WidgetsBindingObserver {
  AppUpdateState? _state;
  Timer? _poller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(silent: true);
  }

  Future<void> _refresh({required bool silent}) async {
    try {
      final previous = _state?.status;
      final state = await widget.service.state();
      if (!mounted) return;
      setState(() => _state = state);
      _syncPolling(state);
      final finishedDownload = previous == AppUpdateStatus.downloading ||
          previous == AppUpdateStatus.verifying;
      if (finishedDownload &&
          state.status == AppUpdateStatus.ready &&
          !_busy) {
        await _install();
      }
    } catch (_) {
      if (!silent && mounted) _message('updateCheckFailed');
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    if (!widget.service.isConfigured) {
      _message('updateNotConfigured');
      return;
    }
    setState(() => _busy = true);
    try {
      final state = await widget.service.check();
      if (!mounted) return;
      setState(() => _state = state);
      if (state.status == AppUpdateStatus.available) {
        await _showAvailable(state);
      } else {
        _message('alreadyLatest');
      }
    } catch (_) {
      if (mounted) _message('updateCheckFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAvailable(AppUpdateState state) async {
    final shouldDownload = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AfterFrameColors.lime,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sheetContext.l10n.text('newVersionReady'),
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        Text(
                          'AfterFrame ${state.versionName} · ${state.abi}',
                          style: const TextStyle(color: AfterFrameColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (state.notes?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 22),
                Text(
                  sheetContext.l10n.text('updateNotes'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Text(
                      state.notes!,
                      style: const TextStyle(
                        height: 1.5,
                        color: AfterFrameColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sheetContext.l10n.text('updateSafetyHint'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AfterFrameColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(sheetContext.l10n.text('downloadInBackground')),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: Text(sheetContext.l10n.text('later')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldDownload == true && mounted) await _download();
  }

  Future<void> _download() async {
    try {
      final state = await widget.service.download();
      if (!mounted) return;
      setState(() => _state = state);
      _syncPolling(state);
      _message('downloadStarted');
    } catch (_) {
      if (mounted) _message('updateDownloadFailed');
    }
  }

  Future<void> _install() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await widget.service.install();
      if (!mounted) return;
      if (status == 'permission_required') {
        _message('allowInstallHint');
      }
      await _refresh(silent: true);
    } catch (_) {
      if (mounted) {
        _message('updateVerifyFailed');
        await _refresh(silent: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _syncPolling(AppUpdateState state) {
    final active = state.status == AppUpdateStatus.downloading ||
        state.status == AppUpdateStatus.verifying;
    if (!active) {
      _poller?.cancel();
      _poller = null;
    } else {
      _poller ??= Timer.periodic(
        const Duration(milliseconds: 900),
        (_) => _refresh(silent: true),
      );
    }
  }

  void _message(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.text(key)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final status = state?.status ?? AppUpdateStatus.idle;
    final active = status == AppUpdateStatus.downloading ||
        status == AppUpdateStatus.verifying;
    final ready = status == AppUpdateStatus.ready;
    final subtitle = switch (status) {
      AppUpdateStatus.downloading => context.l10n.text('updateDownloading'),
      AppUpdateStatus.verifying => context.l10n.text('updateVerifying'),
      AppUpdateStatus.ready => context.l10n.text('updateReadyToInstall'),
      AppUpdateStatus.available => context.l10n.text('updateAvailable'),
      AppUpdateStatus.error => context.l10n.text('updateInterrupted'),
      _ => state == null
          ? context.l10n.text('loadingVersion')
          : '${state.currentVersionName} (${state.currentVersionCode}) · ${state.abi}',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ready ? _install : active ? null : _check,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    ready ? Icons.install_mobile_rounded : Icons.system_update_rounded,
                    color: ready ? AfterFrameColors.lime : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.text(ready ? 'installUpdate' : 'checkUpdates'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AfterFrameColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (!active)
                    const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (active) ...[
                const SizedBox(height: 13),
                LinearProgressIndicator(
                  value: status == AppUpdateStatus.verifying ? null : state?.progress,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(8),
                  color: AfterFrameColors.lime,
                  backgroundColor: AfterFrameColors.glassSoft,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
