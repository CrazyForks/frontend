import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../config/constants.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/utils/responsive_snackbar.dart';
import 'song_cover_picker_modal.dart';

class PlaylistFormDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialDescription;
  final String? initialType;
  final String? initialCoverUrl;
  final int? playlistId;
  final bool isEdit;
  final bool isBuiltIn;

  const PlaylistFormDialog({
    super.key,
    required this.title,
    this.initialName,
    this.initialDescription,
    this.initialType,
    this.initialCoverUrl,
    this.playlistId,
    this.isEdit = false,
    this.isBuiltIn = false,
  });

  @override
  State<PlaylistFormDialog> createState() => PlaylistFormDialogState();
}

class PlaylistFormDialogState extends State<PlaylistFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _type;
  final _formKey = GlobalKey<FormState>();

  /// 封面选择模式（仅编辑模式）
  String? _coverMode;
  PlatformFile? _localFile;
  String? _selectedCoverUrl;
  int? _selectedCoverSongId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _type = widget.initialType ?? AppConstants.playlistTypeNormal;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 获取当前预览的封面 URL
  String? get _previewCoverUrl {
    if (_coverMode == 'clear') return null;
    if (_coverMode == 'song') {
      return _selectedCoverUrl;
    }
    // 未修改时显示原有封面
    if (_coverMode == null) {
      return widget.initialCoverUrl;
    }
    return null;
  }

  /// 上传本地图片
  Future<void> _pickLocalImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _localFile = result.files.first;
          _coverMode = 'local';
        });
      }
    } catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(
          context,
          message: AppLocalizations.of(context).playlistPickImageFailed('$e'),
        );
      }
    }
  }

  /// 从歌曲选择封面
  Future<void> _pickFromSongs() async {
    if (widget.playlistId == null) return;
    final result = await showSongCoverPicker(context, widget.playlistId!);
    if (result != null) {
      setState(() {
        _selectedCoverSongId = result['songId'] as int?;
        _selectedCoverUrl = result['coverUrl'] as String?;
        _coverMode = 'song';
        _localFile = null;
      });
    }
  }

  /// 清除封面
  void _clearCover() {
    setState(() {
      _coverMode = 'clear';
      _localFile = null;
      _selectedCoverUrl = null;
      _selectedCoverSongId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final hasCover =
        _coverMode != 'clear' &&
        (_coverMode == 'local' ||
            _coverMode == 'song' ||
            widget.initialCoverUrl?.isNotEmpty == true);
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 编辑模式显示封面选择
                if (widget.isEdit) ...[
                  // 封面预览区域
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCoverPreview(colorScheme),
                  ),
                  const SizedBox(height: 12),
                  // 封面操作按钮
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLocalImage,
                        icon: const Icon(Icons.upload, size: 18),
                        label: Text(l10n.playlistUploadImage),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickFromSongs,
                        icon: const Icon(Icons.music_note, size: 18),
                        label: Text(l10n.playlistPickFromSongs),
                      ),
                      if (hasCover)
                        TextButton.icon(
                          onPressed: _clearCover,
                          icon: Icon(
                            Icons.clear,
                            size: 18,
                            color: colorScheme.error,
                          ),
                          label: Text(
                            l10n.playlistClear,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // 歌单名称
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.playlistNameLabel,
                    hintText: l10n.playlistNameHint,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.playlistNameRequired;
                    }
                    return null;
                  },
                  autofocus: !widget.isEdit,
                  enabled: !widget.isBuiltIn,
                ),
                const SizedBox(height: 16),
                // 歌单描述
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: l10n.playlistDescLabel,
                    hintText: l10n.playlistDescHint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  enabled: !widget.isBuiltIn,
                ),
                const SizedBox(height: 16),
                // 歌单类型（仅创建时可选）
                if (!widget.isEdit)
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: AppConstants.playlistTypeNormal,
                        label: Text(l10n.playlistTypeNormalOption),
                        icon: const Icon(Icons.queue_music),
                      ),
                      ButtonSegment(
                        value: AppConstants.playlistTypeRadio,
                        label: Text(l10n.playlistTypeRadioOption),
                        icon: const Icon(Icons.radio),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _type = selected.first;
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.playlistOk)),
      ],
    );
  }

  Widget _buildCoverPreview(ColorScheme colorScheme) {
    // 本地文件预览
    if (_coverMode == 'local' && _localFile != null) {
      if (kIsWeb && _localFile!.bytes != null) {
        return Image.memory(_localFile!.bytes!, fit: BoxFit.cover);
      } else if (!kIsWeb && _localFile!.path != null) {
        return Image.file(File(_localFile!.path!), fit: BoxFit.cover);
      }
    }

    // 网络图片预览
    final previewUrl = _previewCoverUrl;
    if (previewUrl != null) {
      return ExcludeSemantics(
        child: CachedNetworkImage(
          imageUrl: UrlHelper.buildCoverUrl(previewUrl),
          fit: BoxFit.cover,
          placeholder:
              (context, url) =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (context, url, error) => _buildPlaceholder(colorScheme),
        ),
      );
    }

    // 占位图
    return _buildPlaceholder(colorScheme);
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.queue_music,
        size: 40,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      final Map<String, dynamic> result = {
        'name': _nameController.text.trim(),
        'description':
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        'type': _type,
      };

      // 编辑模式时添加封面信息
      if (widget.isEdit) {
        result['coverMode'] = _coverMode;
        result['localFile'] = _localFile;
        result['selectedCoverUrl'] = _selectedCoverUrl;
        result['selectedCoverSongId'] = _selectedCoverSongId;
      }

      Navigator.of(context).pop(result);
    }
  }
}
