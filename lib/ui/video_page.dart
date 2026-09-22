import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/video_bloc.dart';
import '../bloc/video_event.dart';
import '../bloc/video_state.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  int _selectedResolution = 720;
  bool _use360pForMidi = true;
  bool _nativeResolutionForMidi = false;
  bool _detectHandSwitch = true;
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      double? manualTime = double.tryParse(_manualTimeController.text);
                      context
                          .read<VideoBloc>()
                          .add(AnalyzeVideo(targetHeight: _selectedResolution, manualStartTime: manualTime));
                    },
                    child: const Text('Analyze Frames'),
                  ),
                ],
              );
            } else if (state is VideoAnalyzing) {
              return const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing... This might take a while.'),
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
                              onChanged: _nativeResolutionForMidi ? null : (val) {
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
                            const Text('Use native resolution (uncompressed, slow)'),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _detectHandSwitch,
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _detectHandSwitch = val;
                                  });
                                }
                              },
                            ),
                            const Text('Detect Left/Right Hand Switch (split on brightness drop)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: () {
                        context
                            .read<VideoBloc>()
                            .add(GenerateMidi(use360p: _use360pForMidi, nativeResolution: _nativeResolutionForMidi, detectHandSwitch: _detectHandSwitch));
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
                  Text(state.midiPath, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
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
