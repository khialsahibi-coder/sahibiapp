import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

const navy = Color(0xFF071A31), gold = Color(0xFFD5AD59), teal = Color(0xFF21B6A8);
void main() => runApp(const SahibiApp());

class SahibiApp extends StatelessWidget {
  const SahibiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SAHIBI VISION AI STUDIO', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: navy,
      colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: gold)),
    home: const StudioHome());
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  final topic = TextEditingController(), script = TextEditingController(), aiPrompt = TextEditingController();
  final tts = FlutterTts(), recorder = AudioRecorder(), voicePlayer = AudioPlayer();
  final picker = ImagePicker();

  String language = 'English', status = 'Ready';
  String? voicePath, musicPath, subtitlePath;
  final List<String> clips = [];
  VideoPlayerController? preview;
  Duration videoDuration = Duration.zero;
  double trimStart = 0, trimEnd = 0, musicVolume = .25;
  int outputHeight = 1080;
  bool recording = false, exporting = false, loadingPreview = false, ttsPlaying = false;
  String? exportPath;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this);
    voicePlayer.onPlayerComplete.listen((_) { if (mounted) setState(() {}); });
    tts.setCompletionHandler(() { if (mounted) setState(() => ttsPlaying = false); });
  }

  @override
  void dispose() {
    tabs.dispose(); topic.dispose(); script.dispose(); aiPrompt.dispose();
    recorder.dispose(); voicePlayer.dispose(); tts.stop(); preview?.dispose(); super.dispose();
  }

  Future<Directory> workDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/SahibiVision');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
  Future<String> newPath(String name) async => '${(await workDir()).path}/$name';
  String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
  String _time(int ms) {
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000, s = (ms % 60000) ~/ 1000, milli = ms % 1000;
    return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')},${milli.toString().padLeft(3,'0')}';
  }

  String scriptTemplate() {
    final t = topic.text.trim().isEmpty ? 'our topic' : topic.text.trim();
    if (language == 'Dari') return 'به برنامهٔ ما خوش آمدید.\n\nامروز دربارهٔ $t صحبت می‌کنیم. نکات مهم این موضوع را به زبان ساده بررسی می‌کنیم.\n\nبا ما همراه باشید و اگر این ویدیو برای شما مفید بود، آن را با دوستان خود شریک سازید. تشکر از همراهی شما.';
    if (language == 'Pashto') return 'زموږ خپرونې ته ښه راغلاست.\n\nنن د $t په اړه خبرې کوو او مهم ټکي به په ساده ژبه بیان کړو.\n\nله موږ سره پاتې شئ، او که دا ویډیو درته ګټوره وي، له خپلو ملګرو سره یې شریکه کړئ. ستاسو له ملتیا مننه.';
    return 'Welcome to our program.\n\nToday we are talking about $t. We will explain the important points in a simple way.\n\nStay with us, and share this video with your friends if you find it useful. Thank you for watching.';
  }

  Future<void> speakScript() async {
    if (script.text.trim().isEmpty) { note('Write or generate a script first.'); return; }
    final locale = language == 'Dari' ? 'fa-IR' : language == 'Pashto' ? 'ps-AF' : 'en-US';
    try {
      await tts.stop();
      if (await tts.isLanguageAvailable(locale) != true) { note('Phone TTS does not have $locale installed. Add that voice in Android speech settings.'); return; }
      await tts.setLanguage(locale); await tts.setSpeechRate(.48);
      setState(() { ttsPlaying = true; status = 'Playing text-to-speech…'; });
      await tts.speak(script.text);
    } catch (e) { note('TTS error: $e'); }
  }

  Future<void> recordVoice() async {
    try {
      if (!await recorder.hasPermission()) { note('Microphone permission was not granted.'); return; }
      final path = await newPath('voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: path);
      setState(() { recording = true; voicePath = path; status = 'Recording your voice…'; });
    } catch (e) { note('Recording failed: $e'); }
  }
  Future<void> stopVoice() async {
    try { final p = await recorder.stop(); setState(() { recording = false; voicePath = p ?? voicePath; status = 'Voice recording saved.'; }); }
    catch (e) { note('Could not save recording: $e'); }
  }
  Future<void> playVoice() async {
    if (voicePath == null || !File(voicePath!).existsSync()) { note('Record your voice first.'); return; }
    await voicePlayer.stop(); await voicePlayer.play(DeviceFileSource(voicePath!)); note('Playing your voice recording.');
  }

  Future<void> pickClips() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true, withData: false);
      if (result == null) return;
      final paths = result.files.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) { note('No local video file path was returned.'); return; }
      clips.addAll(paths);
      await loadPreview(clips.first);
      note('${paths.length} video clip(s) added to the project.');
    } catch (e) { note('Could not import video: $e'); }
  }

  Future<void> loadPreview(String path) async {
    try {
      setState(() => loadingPreview = true);
      await preview?.dispose();
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) { await c.dispose(); return; }
      setState(() {
        preview = c; videoDuration = c.value.duration;
        trimStart = 0; trimEnd = videoDuration.inMilliseconds.toDouble(); loadingPreview = false;
      });
    } catch (e) { setState(() => loadingPreview = false); note('Preview failed: $e'); }
  }

  Future<void> pickMusic() async {
    final f = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
    if (f?.files.single.path != null) { setState(() => musicPath = f!.files.single.path); note('Background audio selected.'); }
  }
  Future<void> pickSrt() async {
    final f = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['srt'], allowMultiple: false);
    if (f?.files.single.path != null) { setState(() => subtitlePath = f!.files.single.path); note('Subtitle file selected.'); }
  }

  String buildSrt() {
    final words = script.text.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final out = StringBuffer();
    const perCaption = 7;
    for (var i = 0; i < words.length; i += perCaption) {
      final start = (i ~/ perCaption) * 4000, end = start + 4000;
      out.writeln(i ~/ perCaption + 1);
      out.writeln('${_time(start)} --> ${_time(end)}');
      out.writeln(words.skip(i).take(perCaption).join(' ')); out.writeln();
    }
    return out.toString();
  }
  Future<void> saveSrt() async {
    if (script.text.trim().isEmpty) { note('Create a script first.'); return; }
    final p = await newPath('captions_${DateTime.now().millisecondsSinceEpoch}.srt');
    await File(p).writeAsString(buildSrt());
    setState(() => subtitlePath = p); note('Estimated SRT draft saved. Adjust timing before using it.');
  }

  Future<void> exportVideo() async {
    if (clips.isEmpty) { note('Import at least one MP4 clip first.'); return; }
    if (clips.length > 1 && (trimStart > 0 || (preview != null && trimEnd < videoDuration.inMilliseconds))) {
      note('For this version, trim a single clip or join clips without trimming.'); return;
    }
    setState(() { exporting = true; status = 'Preparing MP4 export…'; exportPath = null; });
    try {
      final out = await newPath('export_${DateTime.now().millisecondsSinceEpoch}_${outputHeight}p.mp4');
      String command;
      if (clips.length == 1) {
        final input = clips.first;
        final start = (trimStart / 1000).toStringAsFixed(3);
        final end = (trimEnd / 1000).toStringAsFixed(3);
        final dur = ((trimEnd - trimStart).clamp(1, 1e12) / 1000).toStringAsFixed(3);
        final args = StringBuffer('-y -ss $start -i ${q(input)} -t $dur ');
        if (musicPath != null) {
          args.write('-i ${q(musicPath!)} -filter_complex "[1:a]volume=${musicVolume.toStringAsFixed(2)}[bg];[0:a][bg]amix=inputs=2:duration=first:dropout_transition=2[a]" -map 0:v:0 -map "[a]" ');
        } else {
          args.write('-map 0:v:0 -map 0:a? ');
        }
        String videoFilter = 'scale=-2:$outputHeight';
        if (subtitlePath != null) {
          final sub = subtitlePath!.replaceAll('\\', '/').replaceAll(':', r'\:').replaceAll("'", r"\'");
          videoFilter = "subtitles='$sub',scale=-2:$outputHeight";
        }
        args.write('-vf ${q(videoFilter)} -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 192k -movflags +faststart ${q(out)}');
        command = args.toString();
      } else {
        final list = await newPath('concat_${DateTime.now().millisecondsSinceEpoch}.txt');
        final content = clips.map((p) => "file '${p.replaceAll("'", r"'\''")}'").join('\n');
        await File(list).writeAsString(content);
        final args = StringBuffer('-y -f concat -safe 0 -i ${q(list)} ');
        if (musicPath != null) {
          args.write('-i ${q(musicPath!)} -filter_complex "[1:a]volume=${musicVolume.toStringAsFixed(2)}[bg];[0:a][bg]amix=inputs=2:duration=first[a]" -map 0:v:0 -map "[a]" ');
        } else { args.write('-map 0:v:0 -map 0:a? '); }
        args.write('-vf scale=-2:$outputHeight -c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${q(out)}');
        command = args.toString();
      }
      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(out).existsSync()) {
        setState(() { exportPath = out; status = 'MP4 export completed: $out'; });
      } else {
        final logs = (await session.getOutput()) ?? 'No FFmpeg output was returned.';
        note('Export failed. Details: ${logs.length > 900 ? logs.substring(logs.length - 900) : logs}');
      }
    } catch (e) { note('Export error: $e'); }
    finally { if (mounted) setState(() => exporting = false); }
  }

  Future<void> shareExport() async {
    if (exportPath == null) return;
    await Share.shareXFiles([XFile(exportPath!)], text: 'Created with SAHIBI VISION AI STUDIO');
  }

  Future<void> openFreeAi() async {
    if (aiPrompt.text.trim().isEmpty) { note('Write your AI video prompt first.'); return; }
    await Clipboard.setData(ClipboardData(text: aiPrompt.text.trim()));
    final uri = Uri.parse('https://fal.ai/flux-video-free');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    note(ok
      ? 'Prompt copied. In fal, sign in, choose FLUX 3 Draft, paste your prompt and generate. Download the result, then import it here.'
      : 'Could not open fal.ai. Prompt copied; visit fal.ai/flux-video-free in your browser.');
  }

  void note(String s) { if (mounted) setState(() => status = s); }
  Widget panel(Widget child) => Container(width: double.infinity, padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: const Color(0xFF102943), borderRadius: BorderRadius.circular(17),
      border: Border.all(color: teal.withValues(alpha: .28))), child: child);
  Widget heading(String a, String b) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(a, style: const TextStyle(color: gold, fontSize: 21, fontWeight: FontWeight.bold)),
      Text(b, style: const TextStyle(color: Colors.white70))]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SAHIBI VISION AI STUDIO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .6, fontSize: 16)),
      actions: [IconButton(onPressed: () => showAboutDialog(context: context, applicationName: 'SAHIBI VISION AI STUDIO',
        applicationVersion: '2.0.0', applicationLegalese: 'Developed by Khial Muhammad Sahibi\nContact: +93 77 111 0 555\nEmail: khialsahibi@gmail.com'),
        icon: const Icon(Icons.info_outline))],
      bottom: TabBar(controller: tabs, isScrollable: true, indicatorColor: gold, labelColor: gold, tabs: const [
        Tab(icon: Icon(Icons.auto_awesome), text: 'AI Create'),
        Tab(icon: Icon(Icons.edit_note), text: 'Script'),
        Tab(icon: Icon(Icons.mic), text: 'Voice'),
        Tab(icon: Icon(Icons.movie_edit), text: 'Editor'),
      ])),
    body: Column(children: [
      Expanded(child: TabBarView(controller: tabs, children: [aiTab(), scriptTab(), voiceTab(), editorTab()])),
      Container(width: double.infinity, color: const Color(0xFF061426), padding: const EdgeInsets.all(9),
        child: Text(status, style: const TextStyle(color: teal, fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis))
    ]));

  Widget aiTab() => ListView(padding: const EdgeInsets.all(16), children: [
    heading('Online AI Video Creation', 'Generate a video online, then bring it into your local editor.'),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('FLUX 3 Draft — free daily allowance', style: TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('fal.ai currently advertises five free 720p text-to-video draft generations per 24 hours in its web Sandbox. Sign-in and a card on file are required to activate the allowance. This free allowance is for the Sandbox workflow, not a free unlimited API entitlement.'),
      const SizedBox(height: 12),
      TextField(controller: aiPrompt, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: 'Describe your video', hintText: 'A cinematic 9:16 shot of… Include camera movement, lighting, action and sound.')),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: openFreeAi,
        icon: const Icon(Icons.open_in_new), label: const Text('Copy prompt & open free AI generator'))),
      const SizedBox(height: 8),
      const Text('Workflow: open fal → sign in → paste prompt → generate → download MP4 → return to Editor → import the downloaded clip.', style: TextStyle(color: teal, fontSize: 12)),
    ])),
    const SizedBox(height: 12),
    panel(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Important free-tier details', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
      SizedBox(height: 6),
      Text('• Five free FLUX 3 Draft generations per rolling 24 hours, as advertised by fal.\n• Draft output is 720p; full-quality 1080p enhancement is paid.\n• fal requires an account and card on file to activate the free allowance.\n• The app does not start paid generations or charge your account.'),
    ])),
  ]);

  Widget scriptTab() => ListView(padding: const EdgeInsets.all(16), children: [
    heading('Script Studio', 'Draft narration in English, Dari or Pashto.'),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(value: language, decoration: const InputDecoration(labelText: 'Language'),
        items: ['English','Dari','Pashto'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
        onChanged: (v) => setState(() => language = v ?? 'English')),
      const SizedBox(height: 10),
      TextField(controller: topic, decoration: const InputDecoration(labelText: 'Video topic')),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () { script.text = scriptTemplate(); note('Offline script draft created. Edit it as needed.'); },
        icon: const Icon(Icons.auto_awesome), label: const Text('Generate script draft'))),
    ])),
    const SizedBox(height: 12),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Edit narration', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      TextField(controller: script, minLines: 8, maxLines: 16, decoration: const InputDecoration(hintText: 'Write or edit your narration…')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ElevatedButton.icon(onPressed: speakScript, icon: const Icon(Icons.volume_up), label: const Text('Preview TTS')),
        OutlinedButton.icon(onPressed: () async { await tts.stop(); setState(() => ttsPlaying = false); note('TTS stopped.'); }, icon: const Icon(Icons.stop), label: const Text('Stop')),
        OutlinedButton.icon(onPressed: saveSrt, icon: const Icon(Icons.subtitles), label: const Text('Create SRT draft')),
        OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: script.text)); note('Script copied.'); }, icon: const Icon(Icons.copy), label: const Text('Copy')),
      ])
    ])),
    const SizedBox(height: 8),
    const Text('The built-in script draft is template-based and offline, not a connected LLM.', style: TextStyle(color: Colors.white60, fontSize: 12))
  ]);

  Widget voiceTab() => ListView(padding: const EdgeInsets.all(16), children: [
    heading('Voice Studio', 'Record and replay your own voice or preview TTS.'),
    panel(Column(children: [
      Icon(recording ? Icons.mic : Icons.mic_none, size: 74, color: recording ? Colors.redAccent : teal),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: recording ? Colors.redAccent : gold, foregroundColor: recording ? Colors.white : navy),
        onPressed: recording ? stopVoice : recordVoice, icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
        label: Text(recording ? 'Stop & save recording' : 'Record my voice'))),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: playVoice, icon: const Icon(Icons.play_arrow), label: const Text('Play saved recording')),
      if (voicePath != null) ...[
        OutlinedButton.icon(onPressed: () {
          setState(() => musicPath = voicePath);
          tabs.animateTo(3);
          note('Your recorded voice is selected as the export audio track. It will be mixed with the clip audio.');
        }, icon: const Icon(Icons.graphic_eq), label: const Text('Use my voice in video export')),
        SelectableText(voicePath!, style: const TextStyle(color: teal, fontSize: 10)),
      ],
    ])),
    const SizedBox(height: 10),
    panel(const Text('Your recording is saved in the app documents folder. In this build you can add a background audio track to the video export; direct voice-track selection will be available by choosing your saved recording as an audio track in the next integration step.', style: TextStyle(color: Colors.white70)))
  ]);

  Widget editorTab() {
    final c = preview;
    final maxMs = videoDuration.inMilliseconds.toDouble().clamp(1, 1e12);
    return ListView(padding: const EdgeInsets.all(16), children: [
      heading('Video Editor & MP4 Export', 'Import one or more clips, trim a single clip, add music/subtitles and export MP4.'),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: pickClips, icon: const Icon(Icons.video_library), label: const Text('Import MP4 video clip(s)'))),
        if (clips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${clips.length} clip(s) in project', style: const TextStyle(color: teal, fontWeight: FontWeight.bold)),
          ...clips.asMap().entries.map((e) => ListTile(dense: true, contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.movie, color: gold), title: Text(e.value.split(Platform.pathSeparator).last, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () async {
              setState(() { clips.removeAt(e.key); });
              if (clips.isNotEmpty) await loadPreview(clips.first); else { await preview?.dispose(); setState(() { preview = null; videoDuration = Duration.zero; }); }
            }),
            onTap: () => loadPreview(e.value))),
        ],
        if (loadingPreview) const LinearProgressIndicator(),
        if (c != null && c.value.isInitialized) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
          Row(children: [
            IconButton(onPressed: () async { if (c.value.isPlaying) { await c.pause(); } else { await c.play(); } setState(() {}); },
              icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle, color: gold, size: 34)),
            Expanded(child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: teal, bufferedColor: Colors.white30, backgroundColor: Colors.white12)))
          ]),
          Text('Trim start: ${(trimStart/1000).toStringAsFixed(1)} sec'),
          Slider(value: trimStart.clamp(0, (trimEnd - 500).clamp(0, maxMs)), min: 0, max: maxMs,
            onChanged: (v) => setState(() { trimStart = v.clamp(0, trimEnd - 500); })),
          Text('Trim end: ${(trimEnd/1000).toStringAsFixed(1)} sec'),
          Slider(value: trimEnd.clamp((trimStart + 500).clamp(1, maxMs), maxMs), min: 1, max: maxMs,
            onChanged: (v) => setState(() { trimEnd = v.clamp(trimStart + 500, maxMs); })),
        ],
      ])),
      const SizedBox(height: 10),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Audio & subtitles', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: pickMusic, icon: const Icon(Icons.music_note), label: const Text('Add music')),
          OutlinedButton.icon(onPressed: pickSrt, icon: const Icon(Icons.subtitles), label: const Text('Import SRT')),
        ]),
        if (musicPath != null) Text('Audio: ${musicPath!.split(Platform.pathSeparator).last}', style: const TextStyle(color: teal, fontSize: 11)),
        if (subtitlePath != null) Text('Subtitles: ${subtitlePath!.split(Platform.pathSeparator).last}', style: const TextStyle(color: teal, fontSize: 11)),
        if (musicPath != null) ...[
          const SizedBox(height: 8), Text('Music volume: ${(musicVolume*100).round()}%'),
          Slider(value: musicVolume, min: 0, max: 1, onChanged: (v) => setState(() => musicVolume = v)),
        ],
      ])),
      const SizedBox(height: 10),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Export settings', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
        DropdownButtonFormField<int>(value: outputHeight, decoration: const InputDecoration(labelText: 'Resolution'),
          items: const [DropdownMenuItem(value: 720, child: Text('720p')), DropdownMenuItem(value: 1080, child: Text('1080p'))],
          onChanged: (v) => setState(() => outputHeight = v ?? 1080)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: exporting ? null : exportVideo,
          icon: const Icon(Icons.movie_creation), label: Text(exporting ? 'Exporting…' : 'Render & export MP4'))),
        if (exporting) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        if (exportPath != null) ...[
          const SizedBox(height: 8),
          const Text('Export completed', style: TextStyle(color: teal, fontWeight: FontWeight.bold)),
          SelectableText(exportPath!, style: const TextStyle(fontSize: 10)),
          OutlinedButton.icon(onPressed: shareExport, icon: const Icon(Icons.share), label: const Text('Share exported MP4')),
        ]
      ])),
      const SizedBox(height: 8),
      const Text('Current export supports trimming one clip, concatenating multiple untrimmed clips, optional music mixing and optional SRT burn-in. Complex multi-track timelines, animated titles and transition effects are not in this release.', style: TextStyle(color: Colors.white60, fontSize: 11))
    ]);
  }
}
