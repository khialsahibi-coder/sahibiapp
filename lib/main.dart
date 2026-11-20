import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const SahibiVisionApp());

const navy = Color(0xFF071A31);
const panel = Color(0xFF102944);
const gold = Color(0xFFD5AD59);
const teal = Color(0xFF21B6A8);

class SahibiVisionApp extends StatelessWidget {
  const SahibiVisionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sahibi Vision AI Studio',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: navy,
          colorScheme: ColorScheme.fromSeed(
            seedColor: gold,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: navy,
            foregroundColor: gold,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const StudioHome(),
      );
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  final FlutterTts tts = FlutterTts();
  final ImagePicker picker = ImagePicker();
  final TextEditingController topic =
      TextEditingController(text: 'Never lose hope in Allah');
  final TextEditingController script = TextEditingController();
  final TextEditingController subtitleInput = TextEditingController();
  final TextEditingController subtitleOutput = TextEditingController();

  String language = 'English';
  String status = 'Ready to create';
  double speechRate = 0.43;
  VideoPlayerController? videoController;
  bool videoLoading = false;

  final Map<String, Map<String, String>> templates = {
    'English': {
      'opening': 'Sometimes life becomes difficult, and you may feel like giving up.',
      'middle': 'Keep praying, keep trusting Allah, and keep moving forward. Your difficult days do not define your future.',
      'ending': 'Be patient, be grateful, and never lose hope. Sahibi Vision — faith, knowledge and inspiration.'
    },
    'Dari': {
      'opening': 'گاهی زندگی دشوار می‌شود و انسان احساس می‌کند که دیگر توان ادامه دادن ندارد.',
      'middle': 'به دعا کردن ادامه بده، به الله توکل کن و با امید به راهت ادامه بده. روزهای سخت، آیندهٔ تو را تعیین نمی‌کنند.',
      'ending': 'صبر داشته باش، شکرگزار باش و هرگز ناامید نشو. صاحبی ویژن؛ ایمان، دانش و الهام.'
    },
    'Pashto': {
      'opening': 'کله کله ژوند ستونزمن شي او انسان داسې احساس وکړي چې نور د دوام توان نه لري.',
      'middle': 'دعا ته دوام ورکړه، پر الله توکل وکړه او په هيله خپل سفر ته دوام ورکړه. سختې ورځې ستا راتلونکی نه ټاکي.',
      'ending': 'صبر وکړه، شکر وباسه او هېڅکله هيله مه بایله. صاحبي ویژن؛ ایمان، پوهه او الهام.'
    },
  };

  void setStatus(String value) {
    if (mounted) setState(() => status = value);
  }

  void generateScript() {
    final t = templates[language]!;
    final subject = topic.text.trim().isEmpty ? 'this important reminder' : topic.text.trim();
    script.text =
        '${t['opening']}\n\n$subject. ${t['middle']}\n\n${t['ending']}';
    setStatus('Starter script created offline in $language. Edit it as you wish.');
  }

  Future<void> speak() async {
    if (script.text.trim().isEmpty) {
      generateScript();
    }
    try {
      final locale = {
        'English': 'en-US',
        'Dari': 'fa-IR',
        'Pashto': 'ps-AF',
      }[language]!;
      await tts.stop();
      await tts.setLanguage(locale);
      await tts.setSpeechRate(speechRate);
      await tts.setPitch(0.92);
      await tts.speak(script.text);
      setStatus('Speech requested. The voice depends on languages installed on Android.');
    } catch (_) {
      setStatus('This voice is unavailable. Check Android Text-to-speech voice data.');
    }
  }

  Future<void> stopSpeaking() async {
    await tts.stop();
    setStatus('Speech stopped.');
  }

  String _srtTime(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s,000';
  }

  void makeSubtitles() {
    final text = subtitleInput.text.trim().isNotEmpty
        ? subtitleInput.text.trim()
        : script.text.trim();
    if (text.isEmpty) {
      setStatus('Write or generate a script first, then create subtitles.');
      return;
    }
    final chunks = text
        .split(RegExp(r'(?<=[.!?؟۔])\s+|\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final output = StringBuffer();
    for (var i = 0; i < chunks.length; i++) {
      final start = i * 4;
      output
        ..writeln(i + 1)
        ..writeln('${_srtTime(start)} --> ${_srtTime(start + 4)}')
        ..writeln(chunks[i])
        ..writeln();
    }
    subtitleOutput.text = output.toString().trim();
    setStatus('Subtitle draft created. Timing is estimated at 4 seconds per line; adjust before use.');
  }

  Future<void> copyText(String value, String label) async {
    if (value.trim().isEmpty) {
      setStatus('There is no $label to copy yet.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    setStatus('$label copied to clipboard.');
  }

  Future<void> chooseVideo() async {
    try {
      final file = await picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => videoLoading = true);
      await videoController?.dispose();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        videoController = controller;
        videoLoading = false;
      });
      setStatus('Video loaded. Preview and playback are ready.');
    } catch (e) {
      setState(() => videoLoading = false);
      setStatus('Could not open this video. Check gallery permission and file format.');
    }
  }

  Future<void> toggleVideo() async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  void showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'SAHIBI VISION AI STUDIO',
      applicationVersion: 'Personal edition',
      applicationIcon: const Icon(Icons.auto_awesome, color: gold, size: 36),
      children: const [
        SizedBox(height: 8),
        Text('Developed by Khial Muhammad Sahibi'),
        SizedBox(height: 6),
        SelectableText('Contact: +93 77 111 0 555'),
        SizedBox(height: 6),
        SelectableText('Email: khialsahibi@gmail.com'),
        SizedBox(height: 12),
        Text('Made for faith, knowledge and inspiration.'),
      ],
    );
  }

  Widget sectionCard(String title, String description, IconData icon,
      {required Widget child}) {
    return Card(
      color: panel,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: gold,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 5),
            Text(description, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    topic.dispose();
    script.dispose();
    subtitleInput.dispose();
    subtitleOutput.dispose();
    tts.stop();
    videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAHIBI VISION',
            style: TextStyle(
                letterSpacing: 1.6, fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'About us',
            onPressed: showAbout,
            icon: const Icon(Icons.priority_high_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF173B56), navy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: gold.withOpacity(.65)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, color: gold, size: 34),
                SizedBox(height: 12),
                Text('AI VIDEO STUDIO',
                    style: TextStyle(
                        color: gold,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4)),
                SizedBox(height: 6),
                Text(
                  'Create meaningful videos. Share faith, knowledge and inspiration.',
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 12),
                Text('FREE TOOLS • NO API KEY REQUIRED',
                    style: TextStyle(
                        color: teal,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          sectionCard(
            'Script Studio',
            'Create and edit a starter script in English, Dari or Pashto.',
            Icons.edit_note,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: language,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: templates.keys
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => language = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: topic,
                  decoration: const InputDecoration(labelText: 'Video topic'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: gold, foregroundColor: navy),
                    onPressed: generateScript,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Generate starter script'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: script,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Your script',
                    hintText: 'Generate a script or write your own...',
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: speak,
                      icon: const Icon(Icons.record_voice_over),
                      label: const Text('Speak'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: stopSpeaking,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop voice'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Voice speed'),
                  Expanded(
                    child: Slider(
                      value: speechRate,
                      min: 0.25,
                      max: 0.65,
                      onChanged: (v) => setState(() => speechRate = v),
                    ),
                  ),
                  Text(speechRate.toStringAsFixed(2)),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => copyText(script.text, 'Script'),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy script'),
                  ),
                ),
              ],
            ),
          ),
          sectionCard(
            'Subtitle Studio',
            'Turn your script into an editable SRT subtitle draft.',
            Icons.subtitles,
            child: Column(
              children: [
                TextField(
                  controller: subtitleInput,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Text for subtitles',
                    hintText: 'Leave empty to use the script above.',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: makeSubtitles,
                    icon: const Icon(Icons.subtitles),
                    label: const Text('Create subtitle draft'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subtitleOutput,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'SRT subtitle text',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        copyText(subtitleOutput.text, 'SRT subtitles'),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy SRT'),
                  ),
                ),
              ],
            ),
          ),
          sectionCard(
            'Video Studio',
            'Choose one video from your phone and preview it here.',
            Icons.video_library,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: videoLoading ? null : chooseVideo,
                    icon: const Icon(Icons.video_file),
                    label: Text(videoLoading ? 'Loading video...' : 'Import video'),
                  ),
                ),
                if (videoController != null &&
                    videoController!.value.isInitialized) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: videoController!.value.aspectRatio,
                      child: VideoPlayer(videoController!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    IconButton(
                      onPressed: toggleVideo,
                      icon: Icon(videoController!.value.isPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        videoController!,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 6),
                const Text(
                  'This build imports and previews a clip. Trimming, multi-clip editing, music mixing and final MP4 rendering are not included yet.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          sectionCard(
            '1080p Export & AI Video',
            'Export and generative video need additional processing/model components.',
            Icons.high_quality,
            child: const Text(
              'Not enabled in this build. This app does not pretend to export a finished MP4 or generate AI video yet. We can add a real rendering engine and optional on-device models in the next project update.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF0E2A40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: teal.withOpacity(.3)),
            ),
            child: Text(status, style: const TextStyle(color: teal)),
          ),
          const SizedBox(height: 10),
          const Text(
            'Note: Android speech languages depend on the voices installed on your phone. Persian (fa-IR) is not guaranteed to be Dari, and Pashto may not be installed.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
