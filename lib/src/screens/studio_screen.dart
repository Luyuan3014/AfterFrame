import '../live_editor/live_editor_page.dart';

/// Backward-compatible route name for callers that have not migrated yet.
@Deprecated('Use LiveEditorPage instead.')
class StudioScreen extends LiveEditorPage {
  const StudioScreen({
    super.key,
    required super.assets,
    required super.engine,
    super.initialMode,
  });
}
