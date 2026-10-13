import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/video_bloc.dart';
import '../bloc/video_event.dart';
import '../bloc/video_state.dart';
import '../domain/color_group.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  int _selectedResolution = 720;
  bool _use360pForMidi = true;
  bool _nativeResolutionForMidi = false;
  ExtractionMode _extractionMode = ExtractionMode.monoColor;
  final TextEditingController _manualTimeController = TextEditingController();

  @override
  void dispose() {
    _manualTimeController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      context.read<VideoBloc>().add(VideoSelected(result.files.single.path!));
    }
  }

  Widget _buildResolutionSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.tune, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        const Text(
          'Resolution: ',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        DropdownButton<int>(
          value: _selectedResolution,
          underline: Container(height: 1, color: Colors.blue),
          items: const [
            DropdownMenuItem(
              value: 720,
              child: Text('720p (High Quality)'),
            ),
            DropdownMenuItem(
              value: 360,
              child: Text('360p (Fast / Low Memory)'),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedResolution = val;
              });
            }
          },
        ),
      ],
    );
  }

  void _showColorAnalysisDialog(
      BuildContext context, ColorAnalysisResult? analysis) {
    if (analysis == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ColorAnalysisModal(analysis: analysis),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Frame Analyzer'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Resolution Downscale Menu',
            icon: const Icon(Icons.settings),
            initialValue: _selectedResolution,
            onSelected: (val) {
              setState(() {
                _selectedResolution = val;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 720,
                child: Row(
                  children: [
                    Icon(Icons.hd, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('720p (High Quality)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 360,
                child: Row(
                  children: [
                    Icon(Icons.speed, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('360p (Fast / Low Memory)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: BlocBuilder<VideoBloc, VideoState>(
          builder: (context, state) {
            if (state is VideoInitial) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Select a video to get started.'),
                  const SizedBox(height: 16),
                  _buildResolutionSelector(),
                ],
              );
            } else if (state is VideoLoaded) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_file, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  Text(
                      'Video Selected: ${state.videoPath.split(Platform.isWindows ? r'\' : '/').last}'),
                  const SizedBox(height: 16),
                  _buildResolutionSelector(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64.0),
                    child: TextField(
                      controller: _manualTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Manual Start Time (seconds, e.g. 0.5)',
                        helperText: 'Leave empty for auto-detect',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      double? manualTime =
                          double.tryParse(_manualTimeController.text);
                      context.read<VideoBloc>().add(AnalyzeVideo(
                          targetHeight: _selectedResolution,
                          manualStartTime: manualTime));
                    },
                    child: const Text('Analyze Frames'),
                  ),
                ],
              );
            } else if (state is VideoAnalyzing) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    state.message ?? 'Analyzing... This might take a while.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              );
            } else if (state is KeyMappingComplete) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Mapping Complete! All 88 keys found (${state.targetHeight}p).',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                  Expanded(
                    child: InteractiveViewer(
                      minScale: 0.1,
                      maxScale: 5.0,
                      child: Image.file(
                        File(state.imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _use360pForMidi,
                              onChanged:
                                  _nativeResolutionForMidi ? null : (val) {
                                if (val != null) {
                                  setState(() {
                                    _use360pForMidi = val;
                                  });
                                }
                              },
                            ),
                            const Text('Downscale to 360p for faster processing'),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _nativeResolutionForMidi,
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _nativeResolutionForMidi = val;
                                  });
                                }
                              },
                            ),
                            const Text(
                                'Use native resolution (uncompressed, slow)'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 12.0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Extraction Colour Mode',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<ExtractionMode>(
                                segments: const [
                                  ButtonSegment<ExtractionMode>(
                                    value: ExtractionMode.monoColor,
                                    label: Text('Mono Colour Mode'),
                                    icon: Icon(Icons.colorize),
                                  ),
                                  ButtonSegment<ExtractionMode>(
                                    value: ExtractionMode.duoColor,
                                    label: Text('Duo Colour Mode'),
                                    icon: Icon(Icons.palette),
                                  ),
                                ],
                                selected: {_extractionMode},
                                onSelectionChanged: (newSelection) {
                                  setState(() {
                                    _extractionMode = newSelection.first;
                                  });
                                },
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _extractionMode == ExtractionMode.monoColor
                                    ? 'Single keypress color mode: isolates real note color across black & white keys, filtering resting keys and light spills.'
                                    : 'Dual keypress colors mode: detects two note colors (e.g. left & right hands), prompting selection if ambiguous.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade700),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: () {
                        context.read<VideoBloc>().add(GenerateMidi(
                              use360p: _use360pForMidi,
                              nativeResolution: _nativeResolutionForMidi,
                              extractionMode: _extractionMode,
                            ));
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                      ),
                      child: const Text('Looks Good? Generate MIDI',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              );
            } else if (state is ColorSelectionRequired) {
              return _ColorSelectionWidget(state: state);
            } else if (state is MidiGenerationComplete) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_note, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text('MIDI Generated Successfully!',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(state.midiPath, textAlign: TextAlign.center),
                  ),
                  if (state.detectedColors != null &&
                      state.detectedColors!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Keypress Color(s) Detected:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: state.detectedColors!.map((c) {
                        final rgb = c.representativeColor;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(rgb.r, rgb.g, rgb.b, 1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.black26),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(rgb.hexCode,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (state.analysisResult != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.insights),
                      label: const Text('View Color Analysis Steps'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade50,
                        foregroundColor: Colors.blue.shade800,
                        elevation: 0,
                        side: BorderSide(color: Colors.blue.shade200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      onPressed: () =>
                          _showColorAnalysisDialog(context, state.analysisResult),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      context
                          .read<VideoBloc>()
                          .add(AnalyzeVideo(targetHeight: _selectedResolution));
                    },
                    child: const Text('Process Another'),
                  ),
                ],
              );
            } else if (state is VideoError) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${state.message}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _buildResolutionSelector(),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context
                          .read<VideoBloc>()
                          .add(AnalyzeVideo(targetHeight: _selectedResolution));
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickVideo(context),
        tooltip: 'Upload Video',
        child: const Icon(Icons.upload),
      ),
    );
  }
}

class _ColorSelectionWidget extends StatefulWidget {
  final ColorSelectionRequired state;

  const _ColorSelectionWidget({required this.state});

  @override
  State<_ColorSelectionWidget> createState() => _ColorSelectionWidgetState();
}

class _ColorSelectionWidgetState extends State<_ColorSelectionWidget> {
  final Set<ColorGroup> _selected = {};

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final totalFrames = state.frames.length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.palette, size: 28, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.preselectedGroup != null
                      ? 'Duo Colour Mode: Select 2nd Color'
                      : 'Duo Colour Mode: Select 2 Colors',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.insights, size: 18),
                label: const Text('View Steps'),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) =>
                        _ColorAnalysisModal(analysis: state.analysisResult),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.preselectedGroup != null
                ? 'One note color was automatically identified. Please select the 2nd keypress color from the list below (${_selected.length}/${state.neededCount} selected):'
                : 'Please select 2 keypress colors from the detected candidate groups (${_selected.length}/${state.neededCount} selected):',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          const SizedBox(height: 12),
          if (state.preselectedGroup != null) ...[
            Card(
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.green.shade400, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(
                      state.preselectedGroup!.representativeColor.r,
                      state.preselectedGroup!.representativeColor.g,
                      state.preselectedGroup!.representativeColor.b,
                      1.0,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                title: Text(
                  'Color 1 (Auto-Identified): ${state.preselectedGroup!.representativeColor.hexCode}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Appeared across ${state.preselectedGroup!.frameCount} frames ($totalFrames total) on both black and white keys',
                ),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: ListView.builder(
              itemCount: state.selectionOptions.length,
              itemBuilder: (context, index) {
                final group = state.selectionOptions[index];
                final rgb = group.representativeColor;
                final isSelected = _selected.contains(group);
                final recurrencePct = totalFrames > 0
                    ? ((group.frameCount / totalFrames) * 100).toStringAsFixed(1)
                    : '0';

                return Card(
                  elevation: isSelected ? 3 : 1,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(group);
                        } else {
                          if (state.neededCount == 1) {
                            _selected.clear();
                            _selected.add(group);
                          } else {
                            if (_selected.length < state.neededCount) {
                              _selected.add(group);
                            }
                          }
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Color.fromRGBO(rgb.r, rgb.g, rgb.b, 1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      rgb.hexCode,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'RGB(${rgb.r}, ${rgb.g}, ${rgb.b})',
                                      style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Recurrence: ${group.frameCount} frames ($recurrencePct%)',
                                      style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12),
                                    ),
                                    const SizedBox(width: 8),
                                    if (group.operatesOnBothKeys)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.green.shade300),
                                        ),
                                        child: Text(
                                          'Both Keys',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green.shade800,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      )
                                    else if (group.blackKeysSeen.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Black Keys Only',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade800),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'White Keys Only',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue.shade800),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (isSelected) {
                                  _selected.remove(group);
                                } else {
                                  if (state.neededCount == 1) {
                                    _selected.clear();
                                    _selected.add(group);
                                  } else {
                                    if (_selected.length < state.neededCount) {
                                      _selected.add(group);
                                    }
                                  }
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_selected.length}/${state.neededCount} selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Confirm & Extract Notes'),
                onPressed: _selected.length == state.neededCount
                    ? () {
                        context
                            .read<VideoBloc>()
                            .add(ConfirmColorSelection(_selected.toList()));
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorAnalysisModal extends StatelessWidget {
  final ColorAnalysisResult analysis;

  const _ColorAnalysisModal({required this.analysis});

  Widget _buildColorCard(ColorGroup group, {String? tag, Color? tagColor}) {
    final rgb = group.representativeColor;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color.fromRGBO(rgb.r, rgb.g, rgb.b, 1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(rgb.hexCode,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      Text('RGB(${rgb.r}, ${rgb.g}, ${rgb.b})',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                      if (tag != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor ?? Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(tag,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Frames: ${group.frameCount} | Area: ${group.totalPixels} px | Keys: ${group.operatesOnBothKeys ? "Both Keys" : (group.blackKeysSeen.isNotEmpty ? "Black Only" : "White Only")}',
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                const Text('Color Analysis Steps & Breakdown',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'Pipeline Steps (Visual)'),
                      Tab(text: 'Console Logs'),
                    ],
                    labelColor: Colors.blue.shade800,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: Colors.blue,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildVisualPipelineTab(context),
                        _buildLogsTab(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualPipelineTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // STEP 1: Resting Key Colors Discarded
        _buildSectionHeader(
          stepNumber: 1,
          title: 'Resting Keyboard Keys (Discarded)',
          description:
              'The 2 non-pressed baseline colors (black & white keys) were identified and excluded from candidate evaluation.',
          icon: Icons.remove_circle_outline,
          iconColor: Colors.red.shade400,
        ),
        _buildColorCard(analysis.restingWhiteGroup,
            tag: 'DISCARDED (White Keys)', tagColor: Colors.red.shade50),
        _buildColorCard(analysis.restingBlackGroup,
            tag: 'DISCARDED (Black Keys)', tagColor: Colors.red.shade50),
        const SizedBox(height: 20),

        // STEP 2: Candidate Groups
        _buildSectionHeader(
          stepNumber: 2,
          title:
              'Candidate Active Groups (${analysis.candidateGroups.length})',
          description:
              'Colors that actively lit up during the video (real notes, light spills, and special effects).',
          icon: Icons.palette_outlined,
          iconColor: Colors.indigo,
        ),
        ...analysis.candidateGroups.map((g) => _buildColorCard(g)),
        const SizedBox(height: 20),

        // STEP 3: Both-Key Presence Filter FIRST (if Mono Mode)
        if (analysis.monoMaxRecurrence != null) ...[
          _buildSectionHeader(
            stepNumber: 3,
            title: 'Both-Key Presence Filter (First)',
            description:
                'Light spills appear on black keys only (dark) or white keys only (light). We discard single-key spills and retain colors operating on BOTH key types.',
            icon: Icons.compare_arrows,
            iconColor: Colors.purple,
          ),
          if (analysis.monoBothKeysGroups.isNotEmpty) ...[
            const Text('Passed Both-Key Presence (Real Note Candidates):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ...analysis.monoBothKeysGroups
                .map((g) => _buildColorCard(g, tag: 'BOTH KEYS', tagColor: Colors.green.shade100)),
          ],
          if (analysis.monoSingleKeyGroups.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Discarded (Single Key Type Only / Light Spills):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            ...analysis.monoSingleKeyGroups.map((g) => _buildColorCard(g,
                tag: 'DISCARDED (Light Spill)', tagColor: Colors.orange.shade50)),
          ],
          const SizedBox(height: 20),

          // STEP 4: 80% Recurrence Tolerance Filter
          _buildSectionHeader(
            stepNumber: 4,
            title: '80% Recurrence Tolerance Filter',
            description:
                'Max recurrence is ${analysis.monoMaxRecurrence} frames. Candidates must be within 80% tolerance of max (cutoff: >= ${analysis.monoThreshold?.toStringAsFixed(0)} frames, retaining >= 20% of max).',
            icon: Icons.filter_alt_outlined,
            iconColor: Colors.orange,
          ),
          if (analysis.monoTopRecurringGroups.isNotEmpty) ...[
            const Text('Passed 80% Recurrence Tolerance:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ...analysis.monoTopRecurringGroups
                .map((g) => _buildColorCard(g, tag: 'PASS', tagColor: Colors.green.shade100)),
          ],
          if (analysis.monoDiscardedByRecurrence.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Discarded (Recurrence < 20% of Max):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            ...analysis.monoDiscardedByRecurrence.map((g) =>
                _buildColorCard(g, tag: 'DISCARDED (Low Recurrence)', tagColor: Colors.grey.shade200)),
          ],
          const SizedBox(height: 20),
        ],

        // STEP 5: Final Selection Winner (The Brightest)
        _buildSectionHeader(
          stepNumber: 5,
          title: 'Final Chosen Keypress Color (The Brightest)',
          description: analysis.monoSelectionReason ??
              analysis.duoSelectionReason ??
              'Selected keypress color.',
          icon: Icons.check_circle_outline,
          iconColor: Colors.green,
        ),
        if (analysis.monoSelectedGroup != null)
          _buildColorCard(analysis.monoSelectedGroup!,
              tag: 'CHOSEN COLOR', tagColor: Colors.green.shade200)
        else if (analysis.duoAutoSelectedGroups != null)
          ...analysis.duoAutoSelectedGroups!.map((g) =>
              _buildColorCard(g, tag: 'CHOSEN DUO COLOR', tagColor: Colors.green.shade200)),
      ],
    );
  }

  Widget _buildSectionHeader({
    required int stepNumber,
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Step $stepNumber: $title',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: iconColor.withOpacity(0.9)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Logs'),
                onPressed: () {
                  final text = analysis.logs.join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logs copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.grey.shade900,
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              itemCount: analysis.logs.length,
              itemBuilder: (context, index) {
                return Text(
                  analysis.logs[index],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
