import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/video_bloc.dart';
import 'ui/video_page.dart';
import 'service/video_analyzer_service.dart';
import 'service/key_mapper_service.dart';
import 'service/note_extractor_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Frame Analyzer',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: BlocProvider(
        create: (context) => VideoBloc(
          analyzerService: VideoAnalyzerService(),
          mapperService: KeyMapperService(),
          noteExtractorService: NoteExtractorService(),
        ),
        child: const VideoPage(),
      ),
    );
  }
}

