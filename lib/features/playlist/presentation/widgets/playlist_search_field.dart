import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../l10n/app_localizations.dart';

/// 歌单详情页搜索框。
///
/// 搜索框始终保留在 widget tree 中，只切换 [Offstage] 状态。这样搜索结果异步
/// 刷新时不会重新挂载 [TextField]，也不会反复触发 autofocus 打断输入法组合状态。
class PlaylistSearchField extends StatefulWidget {
  const PlaylistSearchField({
    super.key,
    required this.visible,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final bool visible;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<PlaylistSearchField> createState() => _PlaylistSearchFieldState();
}

class _PlaylistSearchFieldState extends State<PlaylistSearchField> {
  int _focusRequestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _scheduleFocus();
  }

  @override
  void didUpdateWidget(covariant PlaylistSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;

    if (widget.visible) {
      _scheduleFocus();
    } else {
      _focusRequestId++;
      widget.focusNode.unfocus();
    }
  }

  void _scheduleFocus() {
    final requestId = ++_focusRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canApplyFocusRequest(requestId)) return;
      FocusScope.of(context).requestFocus(widget.focusNode);
    });
  }

  bool _canApplyFocusRequest(int requestId) {
    return mounted &&
        widget.visible &&
        requestId == _focusRequestId &&
        widget.focusNode.canRequestFocus;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Offstage(
      offstage: !widget.visible,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon:
                widget.controller.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.clearSearch,
                      onPressed: widget.onClear,
                    )
                    : null,
            hintText: l10n.playlistSearchHint,
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
