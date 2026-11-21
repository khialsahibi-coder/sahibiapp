import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:video_player/video_player.dart';

// ---------------------------------------------------------------------------
// SAHIBI VISION AI STUDIO  -  upgraded local workflow + generative clips
// ---------------------------------------------------------------------------

const navy = Color(0xFF071A31);
const panel = Color(0xFF102944);
const gold = Color(0xFFD5AD59);
const teal = Color(0xFF21B6A8);

const langLocales = {'English': 'en-US', 'Dari': 'fa-IR', 'Pashto': 'ps-AF'};
const sttLocales = {'English': 'en_US', 'Dari': 'fa_IR', 'Pashto': 'ps_AF'};
const langPrefix = {'English': 'en', 'Dari': 'fa', 'Pashto': 'ps'};

};

const sceneThemes = <List<Color>>[
  [Color(0xFF071A31), Color(0xFF1F5A7A)],
  [Color(0xFF0B3D3A), Color(0xFF21B6A8)],
  [Color(0xFF2A1B3D), Color(0xFF7A4FB5)],
  [Color(0xFF3B2A0B), Color(0xFFD5AD59)],
];

const visualIdeas = <String>[
  'sunrise over quiet mountains, soft golden light',
  'a person praying at dawn, silhouette, calm mood',
  'calm sea at golden hour, slow gentle waves',
  'light shining through a window onto an open book',
  'walking on a quiet path through a green valley',
  'open sky with slow moving clouds, peaceful',
  'desert dunes at dusk, warm colours',
  'rain on leaves turning into sunlight, hopeful mood',
];

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class MediaClip {
  MediaClip({
    required this.path,
    required this.isImage,
    required this.source,
    this.thumb,
    double? from,
    double? to,
  })  : start = from ?? 0,
        end = to ?? (isImage ? 4.0 : source);

  final String path;
  final bool isImage;
  final double source;
  String? thumb;
  double start;
  double end;

  /// Extra seconds the last frame is held (used when an AI clip is shorter than its scene).
  double hold = 0;

  double get playLength => end - start;
  double get length => end - start + hold;
  String get name => path.split('/').last;
}

class Caption {
  Caption(this.start, this.end, this.text);
  double start;
  double end;
  String text;
}

class TextLayer {
  TextLayer({
    required this.text,
    required this.start,
    required this.end,
    this.position = 'bottom',
    this.size = 72,
    this.color = Colors.white,
  });
  String text;
  double start;
  double end;
  String position;
  double size;
  Color color;
}

class Scene {
  Scene({required this.text, this.theme = 0, this.prompt = '', this.imagePath});
  String? videoPath;
  double videoDuration = 0;
  String? thumb;
  String text;
  int theme;
  String prompt;
  String? imagePath;
}

// ---------------------------------------------------------------------------
// Shared app state (one project at a time)
// ---------------------------------------------------------------------------

class AppState extends ChangeNotifier {
  String language = 'Dari';
  final TextEditingController topic =
      TextEditingController(text: 'you can add');
  final TextEditingController script = TextEditingController();
  final TextEditingController genSpace =
      TextEditingController(text: 'Lightricks/ltx-video-distilled');
  final TextEditingController genToken = TextEditingController();
  final TextEditingController genEndpoint = TextEditingController();

  String? voicePath;
  String voiceLabel = 'None selected';
  double voiceDuration = 0;
  double voiceVolume = 1.0;

  String? musicPath;
  String musicLabel = 'None';
  double musicVolume = 0.25;

  final List<Caption> captions = [];
  final List<MediaClip> clips = [];
  final List<TextLayer> layers = [];
  final List<Scene> scenes = [];

  String transition = 'none';
  double transitionLen = 0.5;
  String framing = 'blur'; // blur | fit | crop
  bool burnCaptions = true;
  String? lastExport;

  void changed() => notifyListeners();

  double get effectiveTransition {
    if (clips.length < 2 || transition == 'none') return 0;
    final minLen = clips.map((c) => c.length).reduce(math.min);
    return math.max(0.1, math.min(transitionLen, minLen / 2 - 0.05));
  }

  double get timelineLength {
    if (clips.isEmpty) return 0;
    final sum = clips.fold<double>(0, (a, c) => a + c.length);
    return sum - (clips.length - 1) * effectiveTransition;
  }
}

final AppState app = AppState();
final AudioPlayer audio = AudioPlayer();

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

String ts() => DateTime.now().millisecondsSinceEpoch.toString();
String _f(double v) => v.toStringAsFixed(3);
double? pd(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
bool isRtl(String s) => RegExp(r'[\u0590-\u08FF]').hasMatch(s);

String fmtDur(double s) {
  final m = s ~/ 60;
  final r = s - m * 60;
  return '$m:${r.toStringAsFixed(1).padLeft(4, '0')}';
}

String srtTime(double sec) {
  final ms = (sec * 1000).round();
  String two(int v) => v.toString().padLeft(2, '0');
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final r = ms % 1000;
  return '${two(h)}:${two(m)}:${two(s)},${r.toString().padLeft(3, '0')}';
}

String buildSrt(List<Caption> list) {
  final b = StringBuffer();
  for (var i = 0; i < list.length; i++) {
    b
      ..writeln(i + 1)
      ..writeln('${srtTime(list[i].start)} --> ${srtTime(list[i].end)}')
      ..writeln(list[i].text)
      ..writeln();
  }
  return b.toString().trim();
}

List<String> splitText(String text) => text
    .split(RegExp(r'(?<=[.!?؟۔])\s+|\n+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

void toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<Directory> workDir(String sub) async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}/$sub');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

String generateScriptText() {
  final t = templates[app.language]!;
  final subject = app.topic.text.trim().isEmpty
      ? 'this important reminder'
      : app.topic.text.trim();
  return '${t['opening']}\n\n$subject. ${t['middle']}\n\n${t['ending']}';
}

String currentScript() {
  final s = app.script.text.trim();
  return s.isNotEmpty ? s : generateScriptText();
}

// ---------------------------------------------------------------------------
// Media engines
// ---------------------------------------------------------------------------

Future<double> probeDuration(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final d = info?.getDuration();
    return double.tryParse('${d ?? ''}') ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<String?> makeThumb(String video) async {
  try {
    final dir = await workDir('thumbs');
    final out = '${dir.path}/th_${ts()}.jpg';
    final s = await FFmpegKit.executeWithArguments(
        ['-y', '-ss', '0.5', '-i', video, '-frames:v', '1', '-vf', 'scale=160:-2', out]);
    final rc = await s.getReturnCode();
    if (ReturnCode.isSuccess(rc) && File(out).existsSync()) return out;
  } catch (_) {}
  return null;
}

Future<void> useVoice(String path, String label) async {
  app.voicePath = path;
  app.voiceLabel = label;
  app.voiceDuration = await probeDuration(path);
  app.changed();
}

/// Draws text with Flutter's own text engine (correct Arabic-script shaping)
/// onto a transparent 1080x1920 PNG that FFmpeg overlays on the video.
Future<String> renderTextPng({
  required String text,
  required String outPath,
  double fontSize = 64,
  Color color = Colors.white,
  String position = 'bottom',
}) async {
  const width = 1080.0;
  const height = 1920.0;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1.3,
        shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
      ),
    ),
    textDirection: isRtl(text) ? TextDirection.rtl : TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 8,
  )..layout(maxWidth: width * 0.84);

  final dx = (width - tp.width) / 2;
  double dy;
  if (position == 'top') {
    dy = height * 0.10;
  } else if (position == 'center') {
    dy = (height - tp.height) / 2;
  } else {
    dy = height * 0.80 - tp.height;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(dx - 28, dy - 18, tp.width + 56, tp.height + 36),
      const Radius.circular(26),
    ),
    Paint()..color = const Color(0x99000000),
  );
  tp.paint(canvas, Offset(dx, dy));
  final img = await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  await File(outPath).writeAsBytes(data!.buffer.asUint8List());
  return outPath;
}

/// Template-based scene card: gradient (or your picture) + text. Not generative AI.
Future<String> renderSceneCard(Scene s, String outPath) async {
  const w = 1080.0;
  const h = 1920.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
  final colors = sceneThemes[s.theme % sceneThemes.length];

  var drewImage = false;
  if (s.imagePath != null && File(s.imagePath!).existsSync()) {
    try {
      final bytes = await File(s.imagePath!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final im = frame.image;
      final iw = im.width.toDouble();
      final ih = im.height.toDouble();
      final sc = math.max(w / iw, h / ih);
      canvas.save();
      canvas.clipRect(const Rect.fromLTWH(0, 0, w, h));
      canvas.drawImageRect(
        im,
        Rect.fromLTWH(0, 0, iw, ih),
        Rect.fromLTWH((w - iw * sc) / 2, (h - ih * sc) / 2, iw * sc, ih * sc),
        Paint(),
      );
      canvas.restore();
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x99000000));
      drewImage = true;
    } catch (_) {}
  }
  if (!drewImage) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(w, h), colors),
    );
  }
  canvas.drawRect(
    const Rect.fromLTWH(40, 40, w - 80, h - 80),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = gold.withOpacity(.7),
  );

  final len = s.text.length;
  final size = len > 160 ? 50.0 : len > 110 ? 58.0 : len > 60 ? 68.0 : 82.0;
  final tp = TextPainter(
    text: TextSpan(
      text: s.text,
      style: TextStyle(
        color: Colors.white,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.45,
        shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
      ),
    ),
    textDirection: isRtl(s.text) ? TextDirection.rtl : TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: 840);
  tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));

  final brand = TextPainter(
    text: const TextSpan(
      text: 'SAHIBI VISION',
      style: TextStyle(color: gold, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  brand.paint(canvas, Offset((w - brand.width) / 2, h - 150));

  final img = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  await File(outPath).writeAsBytes(data!.buffer.asUint8List());
  return outPath;
}

// ---------------------------------------------------------------------------
// 1080p export engine (FFmpeg)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Generative AI footage via an open-model Gradio Space (Hugging Face)
// ---------------------------------------------------------------------------

class GenResult {
  GenResult({this.path, this.error});
  final String? path;
  final String? error;
}

String spaceBaseUrl(String input) {
  final s = input.trim();
  if (s.isEmpty) return '';
  String clean(String x) => x.toLowerCase().replaceAll('_', '-').replaceAll('.', '-');
  final hf = RegExp(r'huggingface\.co/spaces/([\w.-]+)/([\w.-]+)').firstMatch(s);
  final plain = RegExp(r'^([\w.-]+)/([\w.-]+)$').firstMatch(s);
  final m = hf ?? plain;
  if (m != null) return 'https://${clean(m.group(1)!)}-${clean(m.group(2)!)}.hf.space';
  if (s.startsWith('http')) return s.replaceAll(RegExp(r'/+$'), '');
  return '';
}

Future<HttpClientResponse> _open(HttpClient c, String method, String url,
    {String token = '', Object? body}) async {
  final req = await c.openUrl(method, Uri.parse(url));
  if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
  if (body != null) {
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(body)));
  }
  return req.close();
}

Future<String> _readAll(HttpClientResponse r) => r.transform(utf8.decoder).join();
String _short(String s) => s.length > 300 ? s.substring(0, 300) : s;

String _pname(Map p) => '${p['parameter_name'] ?? p['label'] ?? ''}'.toLowerCase();

String _ptype(Map p) {
  final t = p['type'];
  final raw = t is Map ? t['type'] : t;
  return '${raw ?? ''}'.toLowerCase();
}

Future<Map<String, dynamic>?> _gradioInfo(
    HttpClient c, String base, String token, void Function(String) say) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    for (final prefix in const ['/gradio_api', '']) {
      try {
        final r = await _open(c, 'GET', '$base$prefix/info', token: token);
        final text = await _readAll(r);
        if (r.statusCode == 200) {
          final j = jsonDecode(text);
          if (j is Map && j['named_endpoints'] is Map) {
            return {'prefix': prefix, 'info': j};
          }
        }
      } catch (_) {}
    }
    say('Waking up the Space... (${attempt + 1}/8)');
    await Future.delayed(const Duration(seconds: 10));
  }
  return null;
}

String? pickEndpoint(Map named, String override) {
  if (override.trim().isNotEmpty) {
    final k = override.trim().startsWith('/') ? override.trim() : '/${override.trim()}';
    return named.containsKey(k) ? k : null;
  }
  String? best;
  var bestScore = -999;
  named.forEach((k, v) {
    final returns = (v is Map && v['returns'] is List) ? v['returns'] as List : const [];
    final hasVideo = returns.any((r) => r is Map && '${r['component']}'.toLowerCase().contains('video'));
    if (!hasVideo) return;
    final n = '$k'.toLowerCase();
    var score = 0;
    if (n.contains('text') || n.contains('t2v')) score += 3;
    if (n.contains('image') || n.contains('i2v') || n.contains('v2v') || n.contains('video_to') || n.contains('video-to')) {
      score -= 3;
    }
    if (score > bestScore) {
      best = '$k';
      bestScore = score;
    }
  });
  return best;
}

String describeEndpoints(Map named) {
  final b = StringBuffer();
  named.forEach((k, v) {
    final returns = (v is Map && v['returns'] is List) ? v['returns'] as List : const [];
    final kinds = returns.map((r) => r is Map ? '${r['component']}' : '?').join(', ');
    b.writeln('$k  ->  $kinds');
  });
  return b.toString().trim();
}

List<dynamic> buildGradioInputs(List params, String prompt, double seconds, bool portrait) {
  int? promptIdx;
  for (var i = 0; i < params.length; i++) {
    final p = params[i];
    if (p is Map && promptIdx == null) {
      final n = _pname(p);
      if (n.contains('prompt') && !n.contains('negative')) promptIdx = i;
    }
  }
  if (promptIdx == null) {
    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      if (p is Map && !_pname(p).contains('negative') && _ptype(p) == 'string') {
        promptIdx = i;
        break;
      }
    }
  }
  final data = <dynamic>[];
  int? wi;
  int? hi;
  for (var i = 0; i < params.length; i++) {
    final raw = params[i];
    final Map map = raw is Map ? raw : <String, dynamic>{};
    final name = _pname(map);
    final type = _ptype(map);
    final hasDef = map['parameter_has_default'] == true;
    dynamic value = hasDef ? map['parameter_default'] : null;
    if (!hasDef) {
      if (type == 'string') {
        value = '';
      } else if (type == 'number' || type == 'integer') {
        value = 0;
      } else if (type == 'boolean') {
        value = false;
      }
    }
    if (i == promptIdx) {
      value = prompt;
    } else if (name.contains('duration') && (type == 'number' || type == 'integer')) {
      var sec = seconds;
      final t = map['type'];
      final desc = t is Map ? '${t['description'] ?? ''}' : '';
      final m = RegExp(r'between\s+(-?[\d.]+)\s+and\s+(-?[\d.]+)').firstMatch(desc);
      if (m != null) {
        final lo = double.tryParse(m.group(1)!) ?? sec;
        final up = double.tryParse(m.group(2)!) ?? sec;
        sec = math.max(lo, math.min(up, sec));
      }
      value = type == 'integer' ? sec.round() : sec;
    } else if (type == 'number' || type == 'integer') {
      if (name.contains('width')) wi = i;
      if (name.contains('height')) hi = i;
    }
    data.add(value);
  }
  if (portrait && wi != null && hi != null) {
    final w = data[wi];
    final h = data[hi];
    if (w is num && h is num && w > h) {
      data[wi] = h;
      data[hi] = w;
    }
  }
  return data;
}

bool _isVideoRef(String s) => RegExp(r'\.(mp4|webm|mov)(\?.*)?$', caseSensitive: false).hasMatch(s);

String? _findVideoRef(dynamic v) {
  if (v is Map) {
    final url = v['url'];
    final path = v['path'];
    if (url is String && _isVideoRef(url)) return url;
    if (path is String && _isVideoRef(path)) return path;
    for (final x in v.values) {
      final r = _findVideoRef(x);
      if (r != null) return r;
    }
  } else if (v is List) {
    for (final x in v) {
      final r = _findVideoRef(x);
      if (r != null) return r;
    }
  } else if (v is String && _isVideoRef(v)) {
    return v;
  }
  return null;
}

Future<String> describeSpace(String spaceInput, String token, void Function(String) say) async {
  final base = spaceBaseUrl(spaceInput);
  if (base.isEmpty) return 'Enter the Space as owner/name (for example Lightricks/ltx-video-distilled) or paste its link.';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final got = await _gradioInfo(client, base, token, say);
    if (got == null) {
      return 'Could not reach $base\nThe Space may be sleeping, paused, private, or the name may be wrong. Open it once in a browser, then test again.';
    }
    final named = (got['info'] as Map)['named_endpoints'] as Map;
    final pick = pickEndpoint(named, '');
    return 'Connected to $base\nVideo endpoint chosen: ${pick ?? 'none found'}\n\nAll endpoints:\n${describeEndpoints(named)}';
  } catch (e) {
    return 'Connection test failed: $e';
  } finally {
    client.close(force: true);
  }
}

/// Sends the prompt to a Gradio Space, waits for the generated clip and downloads it.
Future<GenResult> generateClip({
  required String spaceInput,
  required String prompt,
  required void Function(String) say,
  String token = '',
  String endpointOverride = '',
  double seconds = 3,
  bool portrait = true,
}) async {
  final base = spaceBaseUrl(spaceInput);
  if (base.isEmpty) {
    return GenResult(error: 'Enter the Space as owner/name (for example Lightricks/ltx-video-distilled) or paste its link.');
  }
  if (prompt.trim().isEmpty) return GenResult(error: 'The scene prompt is empty.');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    say('Connecting to the Space...');
    final got = await _gradioInfo(client, base, token, say);
    if (got == null) {
      return GenResult(error: 'Could not reach the Space. It may be sleeping, paused, private, or the name is wrong. Open it once in a browser, then try again.');
    }
    final prefix = got['prefix'] as String;
    final named = (got['info'] as Map)['named_endpoints'] as Map;
    final ep = pickEndpoint(named, endpointOverride);
    if (ep == null) {
      return GenResult(error: 'No video-generating endpoint was found. Available endpoints:\n${describeEndpoints(named)}');
    }
    final epInfo = named[ep];
    final params = (epInfo is Map && epInfo['parameters'] is List) ? epInfo['parameters'] as List : const [];
    final data = buildGradioInputs(params, prompt, seconds, portrait);
    final name = ep.startsWith('/') ? ep.substring(1) : ep;

    say('Sending your prompt...');
    final post = await _open(client, 'POST', '$base$prefix/call/$name', token: token, body: {'data': data});
    final postText = await _readAll(post);
    if (post.statusCode != 200) {
      return GenResult(error: 'The Space refused the request (HTTP ${post.statusCode}). ${_short(postText)}');
    }
    final eventId = (jsonDecode(postText) as Map)['event_id'];
    if (eventId == null) return GenResult(error: 'The Space did not return a job id.');

    say('Waiting in the queue and generating (usually 1–3 minutes)...');
    final sse = await _open(client, 'GET', '$base$prefix/call/$name/$eventId', token: token);
    if (sse.statusCode != 200) {
      return GenResult(error: 'Could not read the result (HTTP ${sse.statusCode}).');
    }
    var event = '';
    dynamic result;
    String? errorText;
    final lines = sse.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(minutes: 8));
    await for (final line in lines) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
        if (event == 'heartbeat' || event == 'generating') say('Generating on the Space GPU...');
      } else if (line.startsWith('data:')) {
        final d = line.substring(5).trim();
        if (event == 'complete') {
          result = jsonDecode(d);
          break;
        }
        if (event == 'error') {
          errorText = d;
          break;
        }
      }
    }
    if (errorText != null) {
      return GenResult(
          error: 'The Space reported an error: ${_short(errorText)}\n'
              'Common reasons: the free GPU quota is used up (add a free Hugging Face token or try later), the Space is busy, or the prompt was rejected.');
    }
    if (result == null) return GenResult(error: 'The Space finished without returning a video.');

    var ref = _findVideoRef(result);
    if (ref == null) {
      return GenResult(error: 'The Space answered but no video file was found in its reply: ${_short('$result')}');
    }
    if (!ref.startsWith('http')) ref = '$base$prefix/file=$ref';

    say('Downloading the clip...');
    final dl = await _open(client, 'GET', ref, token: token);
    if (dl.statusCode != 200) return GenResult(error: 'Could not download the clip (HTTP ${dl.statusCode}).');
    final dir = await workDir('aiclips');
    final out = File('${dir.path}/gen_${ts()}.mp4');
    await dl.pipe(out.openWrite());
    if (!out.existsSync() || out.lengthSync() < 5000) {
      return GenResult(error: 'The downloaded clip was empty or incomplete.');
    }
    return GenResult(path: out.path);
  } on TimeoutException {
    return GenResult(error: 'The Space took too long to answer. Try again later.');
  } catch (e) {
    return GenResult(error: 'Generation failed: $e');
  } finally {
    client.close(force: true);
  }
}

class ExportResult {
  ExportResult({this.path, this.error});
  final String? path;
  final String? error;
}

Future<ExportResult> runExport(void Function(double) onProgress) async {
  final clips = List<MediaClip>.from(app.clips);
  if (clips.isEmpty) {
    return ExportResult(error: 'Add at least one video or picture in the Video Editor first.');
  }
  for (final c in clips) {
    if (!File(c.path).existsSync()) {
      return ExportResult(error: 'A file is missing: ${c.name}. Remove it from the timeline and add it again.');
    }
    if (c.length < 0.8) {
      return ExportResult(error: 'The clip ${c.name} is shorter than 0.8 seconds. Adjust its trim.');
    }
  }
  final n = clips.length;
  final td = app.effectiveTransition;
  final total = app.timelineLength;
  final tmp = await getTemporaryDirectory();
  final work = Directory('${tmp.path}/render_${ts()}');
  await work.create(recursive: true);

  final args = <String>['-y'];
  for (final c in clips) {
    if (c.isImage) {
      args.addAll(['-loop', '1', '-framerate', '30', '-t', _f(c.length), '-i', c.path]);
    } else {
      args.addAll(['-ss', _f(c.start), '-t', _f(c.playLength), '-i', c.path]);
    }
  }
  var idx = n;

  // Text layers and (optionally) burned-in captions become transparent PNGs.
  final overlays = <List<double>>[]; // [inputIndex, start, end]
  try {
    for (final l in app.layers) {
      final p = await renderTextPng(
        text: l.text,
        outPath: '${work.path}/layer_$idx.png',
        fontSize: l.size,
        color: l.color,
        position: l.position,
      );
      args.addAll(['-i', p]);
      overlays.add([idx.toDouble(), l.start, math.min(l.end, total)]);
      idx++;
    }
    if (app.burnCaptions) {
      for (final c in app.captions) {
        if (c.text.trim().isEmpty || c.start >= total) continue;
        final p = await renderTextPng(
          text: c.text,
          outPath: '${work.path}/cap_$idx.png',
          fontSize: 58,
          position: 'bottom',
        );
        args.addAll(['-i', p]);
        overlays.add([idx.toDouble(), c.start, math.min(c.end, total)]);
        idx++;
      }
    }
  } catch (e) {
    return ExportResult(error: 'Could not prepare text layers: $e');
  }

  int? vIdx;
  int? mIdx;
  if (app.voicePath != null && File(app.voicePath!).existsSync()) {
    args.addAll(['-i', app.voicePath!]);
    vIdx = idx++;
  }
  if (app.musicPath != null && File(app.musicPath!).existsSync()) {
    args.addAll(['-stream_loop', '-1', '-i', app.musicPath!]);
    mIdx = idx++;
  }

  final parts = <String>[];
  final fit = app.framing == 'crop'
      ? 'scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920'
      : 'scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black';
  for (var i = 0; i < n; i++) {
    final hold = clips[i].hold > 0.05
        ? ',tpad=stop_mode=clone:stop_duration=${_f(clips[i].hold)}'
        : '';
    if (app.framing == 'blur') {
      // whole picture in the middle, a blurred enlarged copy behind it (nothing is cropped)
      parts.add('[$i:v]split=2[bg$i][fg$i]');
      parts.add('[bg$i]scale=270:480:force_original_aspect_ratio=increase,crop=270:480,boxblur=8:2,scale=1080:1920,setsar=1[bb$i]');
      parts.add('[fg$i]scale=1080:1920:force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1[ff$i]');
      parts.add('[bb$i][ff$i]overlay=(W-w)/2:(H-h)/2,setsar=1,fps=30$hold,format=yuv420p[v$i]');
    } else {
      parts.add('[$i:v]$fit,setsar=1,fps=30$hold,format=yuv420p[v$i]');
    }
  }

  var cur = 'v0';
  if (n > 1) {
    if (td <= 0) {
      final ins = List.generate(n, (i) => '[v$i]').join();
      parts.add('${ins}concat=n=$n:v=1:a=0[vc]');
      cur = 'vc';
    } else {
      var acc = 0.0;
      for (var k = 1; k < n; k++) {
        acc += clips[k - 1].length;
        final offset = acc - k * td;
        parts.add('[$cur][v$k]xfade=transition=${app.transition}:duration=${_f(td)}:offset=${_f(offset)}[x$k]');
        cur = 'x$k';
      }
    }
  }
  for (var j = 0; j < overlays.length; j++) {
    final o = overlays[j];
    parts.add("[$cur][${o[0].toInt()}:v]overlay=0:0:enable='between(t,${_f(o[1])},${_f(o[2])})'[o$j]");
    cur = 'o$j';
  }
  parts.add('[$cur]format=yuv420p[vout]');

  final fadeStart = _f(math.max(0.0, total - 2));
  String? aLabel;
  if (vIdx != null && mIdx != null) {
    parts.add('[$vIdx:a]volume=${_f(app.voiceVolume)},aresample=44100[va]');
    parts.add('[$mIdx:a]volume=${_f(app.musicVolume)},aresample=44100[ma]');
    parts.add('[va][ma]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[am]');
    parts.add('[am]afade=t=out:st=$fadeStart:d=2[aout]');
    aLabel = 'aout';
  } else if (vIdx != null) {
    parts.add('[$vIdx:a]volume=${_f(app.voiceVolume)},aresample=44100[aout]');
    aLabel = 'aout';
  } else if (mIdx != null) {
    parts.add('[$mIdx:a]volume=${_f(app.musicVolume)},aresample=44100,afade=t=out:st=$fadeStart:d=2[aout]');
    aLabel = 'aout';
  }

  final outDir = await workDir('exports');
  final out = '${outDir.path}/SahibiVision_${ts()}.mp4';
  args.addAll(['-filter_complex', parts.join(';'), '-map', '[vout]']);
  if (aLabel != null) {
    args.addAll(['-map', '[$aLabel]', '-c:a', 'aac', '-b:a', '192k']);
  }
  args.addAll([
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
    '-pix_fmt', 'yuv420p', '-r', '30', '-movflags', '+faststart',
    '-t', _f(total), out,
  ]);

  final done = Completer<ExportResult>();
  await FFmpegKit.executeWithArgumentsAsync(args, (session) async {
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc) && File(out).existsSync()) {
      done.complete(ExportResult(path: out));
    } else if (ReturnCode.isCancel(rc)) {
      done.complete(ExportResult(error: 'Export cancelled.'));
    } else {
      final logs = (await session.getAllLogsAsString()) ?? '';
      final tail = logs.length > 1400 ? logs.substring(logs.length - 1400) : logs;
      done.complete(ExportResult(error: 'FFmpeg failed (code ${rc?.getValue()}).\n$tail'));
    }
  }, null, (stats) {
    final t = stats.getTime() / 1000.0;
    if (total > 0) onProgress((t / total).clamp(0.0, 1.0).toDouble());
  });
  final result = await done.future;
  try {
    await work.delete(recursive: true);
  } catch (_) {}
  return result;
}

// ---------------------------------------------------------------------------
// App shell
// ---------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SahibiVisionApp());
}

class SahibiVisionApp extends StatelessWidget {
  const SahibiVisionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sahibi Vision AI Studio',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: navy,
          colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: gold),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const HomePage(),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, this.subtitle, required this.icon, required this.child});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
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
                      style: const TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ]),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: const TextStyle(color: Colors.white70)),
              ],
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class PageShell extends StatelessWidget {
  const PageShell({super.key, required this.title, required this.body});
  final String title;
  final List<Widget> Function(BuildContext) body;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListenableBuilder(
          listenable: app,
          builder: (c, _) => ListView(padding: const EdgeInsets.all(16), children: body(c)),
        ),
      );
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.color = Colors.white60});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: color, fontSize: 12.5, height: 1.4));
}

class LangDropdown extends StatelessWidget {
  const LangDropdown({super.key, this.onChanged});
  final void Function(String)? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: app.language,
        decoration: const InputDecoration(labelText: 'Language'),
        items: langLocales.keys.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
        onChanged: (v) {
          if (v == null) return;
          app.language = v;
          app.changed();
          onChanged?.call(v);
        },
      );
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class _Module {
  const _Module(this.title, this.subtitle, this.icon, this.builder);
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = <_Module>[
      _Module('Script Studio', 'English • Dari • Pashto', Icons.edit_note, () => const ScriptPage()),
      _Module('My Voice', 'Record • replay • save', Icons.mic, () => const VoicePage()),
      _Module('Subtitle Studio', 'Auto captions • edit • SRT', Icons.subtitles, () => const SubtitlePage()),
      _Module('Video Editor', 'Clips • trim • text • music', Icons.video_library, () => const EditorPage()),
      _Module('AI Video', 'Storyboard & scenes', Icons.auto_awesome, () => const AiVideoPage()),
      _Module('Export 1080p', 'Render MP4 with progress', Icons.high_quality, () => const ExportPage()),
      _Module('About Us', 'Developer & contact', Icons.info_outline, () => const AboutPage()),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAHIBI VISION',
            style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
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
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.auto_awesome, color: gold, size: 34),
                SizedBox(height: 10),
                Text('AI VIDEO STUDIO',
                    style: TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
                SizedBox(height: 6),
                Text('Create meaningful videos. Share faith, knowledge and inspiration.',
                    style: TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E2A40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: teal.withOpacity(.3)),
              ),
              child: Text(
                'Project: ${app.script.text.trim().isEmpty ? 'no script' : 'script ready'}'
                ' • voice: ${app.voicePath == null ? 'none' : 'ready'}'
                ' • captions: ${app.captions.length}'
                ' • clips: ${app.clips.length}'
                ' • length: ${fmtDur(app.timelineLength)}',
                style: const TextStyle(color: teal, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.12,
              children: [
                for (final m in modules)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => m.builder())),
                    child: Ink(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: gold.withOpacity(.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(m.icon, color: gold, size: 30),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(m.subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
                          ]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Note('Suggested order: Script → Voice → Subtitles → Editor (or AI Video) → Export.'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Script Studio
// ---------------------------------------------------------------------------

class ScriptPage extends StatelessWidget {
  const ScriptPage({super.key});

  @override
  Widget build(BuildContext context) => PageShell(
        title: 'Script Studio',
        body: (context) {
          final words = app.script.text.trim().isEmpty
              ? 0
              : app.script.text.trim().split(RegExp(r'\s+')).length;
          final rtl = app.language != 'English';
          return [
            Panel(
              title: 'Write your script',
              subtitle: 'Choose a language, type a topic, then write or paste your script.',
              icon: Icons.edit_note,
              child: Column(children: [
                const LangDropdown(),
                const SizedBox(height: 10),
                TextField(
                  controller: app.topic,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'Video topic'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: app.script,
                  minLines: 8,
                  maxLines: 18,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  onChanged: (_) => app.changed(),
                  decoration: const InputDecoration(
                    labelText: 'Your script',
                    hintText: 'Write or paste your script here...',
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Note('$words words • about ${(words / 2.4).round()} seconds of speech'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: app.script.text));
                        toast(context, 'Script copied.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        app.script.clear();
                        app.changed();
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Note(
                    'Review Dari and Pashto wording carefully before publishing.'),
              ]),
            ),
          ];
        },
      );
}

// ---------------------------------------------------------------------------
// 2. My Voice: record, replay, save and use in videos
// ---------------------------------------------------------------------------

class VoicePage extends StatelessWidget {
  const VoicePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Voice')),
        body: const _MyVoiceTab(),
      );
}

Widget currentVoiceBanner() => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2A40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: teal.withOpacity(.3)),
      ),
      child: Row(children: [
        const Icon(Icons.audiotrack, color: teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Voice used in videos: ${app.voiceLabel}'
            '${app.voicePath == null ? '' : '  (${fmtDur(app.voiceDuration)})'}',
            style: const TextStyle(color: teal),
          ),
        ),
        if (app.voicePath != null)
          IconButton(
            tooltip: 'Remove',
            onPressed: () {
              app.voicePath = null;
              app.voiceLabel = 'None selected';
              app.voiceDuration = 0;
              app.changed();
            },
            icon: const Icon(Icons.close),
          ),
      ]),
    );

class _MyVoiceTab extends StatefulWidget {
  const _MyVoiceTab();
  @override
  State<_MyVoiceTab> createState() => _MyVoiceTabState();
}

class _MyVoiceTabState extends State<_MyVoiceTab> {
  final AudioRecorder rec = AudioRecorder();
  final Stopwatch sw = Stopwatch();
  Timer? ticker;
  bool recording = false;
  List<File> files = [];
  String? playing;
  StreamSubscription<void>? sub;

  @override
  void initState() {
    super.initState();
    _refresh();
    sub = audio.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = null);
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    sub?.cancel();
    rec.dispose();
    audio.stop();
    super.dispose();
  }

  Future<void> _refresh() async {
    final d = await workDir('recordings');
    final list = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.m4a') || f.path.endsWith('.wav') || f.path.endsWith('.mp3'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (mounted) setState(() => files = list);
  }

  Future<void> _start() async {
    try {
      if (!await rec.hasPermission()) {
        if (mounted) toast(context, 'Microphone permission was denied. Allow it in Android Settings → Apps → Sahibi Vision.');
        return;
      }
      await audio.stop();
      final dir = await workDir('recordings');
      final path = '${dir.path}/voice_${ts()}.m4a';
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      sw
        ..reset()
        ..start();
      ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (mounted) setState(() {});
      });
      setState(() => recording = true);
    } catch (e) {
      if (mounted) toast(context, 'Could not start recording: $e');
    }
  }

  Future<void> _stop() async {
    try {
      await rec.stop();
    } catch (e) {
      if (mounted) toast(context, 'Could not stop recording: $e');
    }
    sw.stop();
    ticker?.cancel();
    if (mounted) setState(() => recording = false);
    await _refresh();
    if (mounted) toast(context, 'Recording saved.');
  }

  Future<void> _play(File f) async {
    try {
      await audio.stop();
      if (playing == f.path) {
        setState(() => playing = null);
        return;
      }
      await audio.play(DeviceFileSource(f.path));
      setState(() => playing = f.path);
    } catch (e) {
      if (mounted) toast(context, 'Could not play this file: $e');
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final p = res?.files.single.path;
    if (p == null) return;
    final dir = await workDir('recordings');
    final ext = p.contains('.') ? p.substring(p.lastIndexOf('.')) : '.m4a';
    await File(p).copy('${dir.path}/voice_${ts()}$ext');
    await _refresh();
    if (mounted) toast(context, 'Audio imported.');
  }

  String _label(File f) {
    final name = f.path.split('/').last.replaceAll('voice_', '').split('.').first;
    final t = DateTime.fromMillisecondsSinceEpoch(int.tryParse(name) ?? 0);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}  ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final secs = sw.elapsed.inSeconds;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
        currentVoiceBanner(),
        const SizedBox(height: 14),
        Panel(
          title: 'Record your own voice',
          subtitle: 'Read your script, then use the recording as the voiceover.',
          icon: Icons.mic,
          child: Column(children: [
            Center(
              child: Text(
                '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: gold),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: recording ? Colors.redAccent : gold,
                foregroundColor: recording ? Colors.white : navy,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: recording ? _stop : _start,
              icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(recording ? 'Stop & save' : 'Start recording'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: recording ? null : _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import an audio file instead'),
            ),
          ]),
        ),
        Panel(
          title: 'Saved recordings (${files.length})',
          icon: Icons.library_music,
          child: files.isEmpty
              ? const Note('No recordings yet.')
              : Column(children: [
                  for (final f in files)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        onPressed: () => _play(f),
                        icon: Icon(playing == f.path ? Icons.stop_circle : Icons.play_circle, color: gold, size: 34),
                      ),
                      title: Text(_label(f), style: const TextStyle(fontSize: 14)),
                      subtitle: Text(app.voicePath == f.path ? 'Selected for video' : '${(f.lengthSync() / 1024).round()} KB',
                          style: TextStyle(color: app.voicePath == f.path ? teal : Colors.white54)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: () async {
                            await useVoice(f.path, 'My recording ${_label(f)}');
                            if (mounted) toast(context, 'Recording selected as the video voiceover.');
                          },
                          child: const Text('Use'),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () async {
                            await audio.stop();
                            if (app.voicePath == f.path) {
                              app.voicePath = null;
                              app.voiceLabel = 'None selected';
                              app.voiceDuration = 0;
                              app.changed();
                            }
                            await f.delete();
                            await _refresh();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Subtitle Studio
// ---------------------------------------------------------------------------

class SubtitlePage extends StatefulWidget {
  const SubtitlePage({super.key});
  @override
  State<SubtitlePage> createState() => _SubtitlePageState();
}

class _SubtitlePageState extends State<SubtitlePage> {
  final SpeechToText stt = SpeechToText();
  final Stopwatch clock = Stopwatch();
  bool active = false;
  bool listeningNow = false;
  bool playVoice = false;
  String partial = '';
  double? speechStart;
  double? lastPartialAt;
  double segStart = 0;

  @override
  void dispose() {
    active = false;
    stt.cancel();
    audio.stop();
    super.dispose();
  }

  double get _now => clock.elapsedMilliseconds / 1000.0;

  Future<void> _startAsr() async {
    try {
      final ok = await stt.initialize(
        onStatus: _onStatus,
        onError: (e) {
          if (mounted) toast(context, 'Speech recognition: ${e.errorMsg}');
        },
      );
      if (!ok) {
        if (mounted) toast(context, 'Speech recognition is not available. Allow the microphone and install Google speech services.');
        return;
      }
      final locales = await stt.locales();
      final prefix = langPrefix[app.language]!;
      final supported = locales.any((l) => l.localeId.toLowerCase().startsWith(prefix));
      if (!supported) {
        if (mounted) {
          toast(context,
              'Speech recognition for ${app.language} is not installed on this phone. Try English, or use "Create captions from script".');
        }
        return;
      }
      active = true;
      clock
        ..reset()
        ..start();
      segStart = 0;
      speechStart = null;
      lastPartialAt = null;
      if (playVoice && app.voicePath != null) {
        await audio.play(DeviceFileSource(app.voicePath!));
      }
      setState(() {});
      _listenOnce();
    } catch (e) {
      if (mounted) toast(context, 'Could not start recognition: $e');
    }
  }

  void _onStatus(String s) {
    if (active && (s == 'done' || s == 'notListening')) {
      listeningNow = false;
      Future.delayed(const Duration(milliseconds: 350), _listenOnce);
    }
  }

  Future<void> _listenOnce() async {
    if (!active || listeningNow || !mounted) return;
    listeningNow = true;
    try {
      await stt.listen(
        localeId: sttLocales[app.language],
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onResult: (r) {
          final words = r.recognizedWords.trim();
          if (words.isEmpty) return;
          speechStart ??= _now;
          lastPartialAt = _now;
          if (r.finalResult) {
            final start = speechStart ?? segStart;
            var end = lastPartialAt ?? _now;
            if (end < start + 0.8) end = start + 0.8;
            app.captions.add(Caption(start, end, words));
            segStart = end;
            speechStart = null;
            lastPartialAt = null;
            partial = '';
            app.changed();
          } else if (mounted) {
            setState(() => partial = words);
          }
        },
      );
    } catch (_) {
      listeningNow = false;
    }
  }

  Future<void> _stopAsr() async {
    active = false;
    listeningNow = false;
    clock.stop();
    await stt.stop();
    await audio.stop();
    if (mounted) setState(() => partial = '');
  }

  void _fromScript() {
    final chunks = splitText(currentScript());
    if (chunks.isEmpty) return;
    final total = app.voiceDuration > 0 ? app.voiceDuration : chunks.length * 3.5;
    final weights = chunks.map((c) => math.max(12, c.length).toDouble()).toList();
    final wsum = weights.fold<double>(0, (a, b) => a + b);
    var t = 0.0;
    app.captions.clear();
    for (var i = 0; i < chunks.length; i++) {
      final len = math.max(1.2, total * weights[i] / wsum);
      app.captions.add(Caption(t, t + len, chunks[i]));
      t += len;
    }
    app.changed();
    toast(context,
        app.voiceDuration > 0
            ? 'Captions created and spread across your voiceover. Timing is estimated — check and adjust.'
            : 'Captions created with estimated timing (no voiceover selected).');
  }

  void _shift() async {
    final c = TextEditingController(text: '0.0');
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shift all captions'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Seconds (e.g. 0.5 or -0.5)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, pd(c.text)), child: const Text('Apply')),
        ],
      ),
    );
    if (v == null) return;
    for (final cap in app.captions) {
      cap.start = math.max(0.0, cap.start + v);
      cap.end = math.max(cap.start + 0.3, cap.end + v);
    }
    app.changed();
  }

  Future<File> _saveSrt() async {
    final dir = await workDir('exports');
    final f = File('${dir.path}/captions_${ts()}.srt');
    await f.writeAsString(buildSrt(app.captions));
    return f;
  }

  @override
  Widget build(BuildContext context) => PageShell(title: 'Subtitle Studio', body: _children);

  List<Widget> _children(BuildContext context) => [
        Panel(
          title: 'Automatic speech recognition',
          subtitle: 'Speak (or play your voiceover) and captions are created with real timing.',
          icon: Icons.hearing,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LangDropdown(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Play my selected voiceover while listening'),
              subtitle: const Text('Works best in a quiet room with the phone speaker on.'),
              value: playVoice,
              onChanged: active ? null : (v) => setState(() => playVoice = v),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: active ? Colors.redAccent : gold,
                foregroundColor: active ? Colors.white : navy,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: active ? _stopAsr : _startAsr,
              icon: Icon(active ? Icons.stop : Icons.mic),
              label: Text(active ? 'Stop listening' : 'Start automatic captions'),
            ),
            if (active) ...[
              const SizedBox(height: 8),
              Text(partial.isEmpty ? 'Listening...' : partial,
                  style: const TextStyle(color: teal),
                  textDirection: isRtl(partial) ? TextDirection.rtl : TextDirection.ltr),
            ],
            const SizedBox(height: 8),
            const Note(
                'Uses Android\'s speech recognizer, so it needs the microphone and usually an internet connection. Language support depends on your phone — Pashto is often unavailable. Recognized text always needs a human check.'),
          ]),
        ),
        Panel(
          title: 'Quick captions from script',
          subtitle: 'Works offline in any language. Timing is spread over your voiceover length.',
          icon: Icons.format_align_center,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _fromScript,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Create captions from script'),
            ),
          ),
        ),
        Panel(
          title: 'Edit captions (${app.captions.length})',
          icon: Icons.edit,
          child: Column(children: [
            for (final c in app.captions) _CaptionRow(key: ObjectKey(c), caption: c),
            if (app.captions.isEmpty) const Note('No captions yet.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () {
                  final last = app.captions.isEmpty ? 0.0 : app.captions.last.end;
                  app.captions.add(Caption(last, last + 3, ''));
                  app.changed();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add line'),
              ),
              OutlinedButton.icon(
                onPressed: app.captions.isEmpty ? null : _shift,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Shift timing'),
              ),
              OutlinedButton.icon(
                onPressed: app.captions.isEmpty
                    ? null
                    : () {
                        app.captions.clear();
                        app.changed();
                      },
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear all'),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Burn captions into exported video'),
              value: app.burnCaptions,
              onChanged: (v) {
                app.burnCaptions = v;
                app.changed();
              },
            ),
          ]),
        ),
        Panel(
          title: 'SRT file',
          icon: Icons.subtitles,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: SelectableText(
                  app.captions.isEmpty ? 'The SRT text appears here.' : buildSrt(app.captions),
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: app.captions.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: buildSrt(app.captions)));
                          if (context.mounted) toast(context, 'SRT copied.');
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: app.captions.isEmpty
                      ? null
                      : () async {
                          final f = await _saveSrt();
                          await Share.shareXFiles([XFile(f.path)], text: 'Subtitles (SRT)');
                        },
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Save & share'),
                ),
              ),
            ]),
          ]),
        ),
      ];
}

class _CaptionRow extends StatelessWidget {
  const _CaptionRow({super.key, required this.caption});
  final Caption caption;

  Widget _num(String label, double value, void Function(double) set) => SizedBox(
        width: 92,
        child: TextFormField(
          initialValue: value.toStringAsFixed(2),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: (v) {
            final d = pd(v);
            if (d != null) {
              set(d);
              app.changed();
            }
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: navy,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          TextFormField(
            initialValue: caption.text,
            minLines: 1,
            maxLines: 4,
            textDirection: isRtl(caption.text) ? TextDirection.rtl : TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'Caption text', isDense: true),
            onChanged: (v) {
              caption.text = v;
              app.changed();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            _num('Start (s)', caption.start, (d) => caption.start = d),
            const SizedBox(width: 8),
            _num('End (s)', caption.end, (d) => caption.end = d),
            const Spacer(),
            IconButton(
              tooltip: 'Delete',
              onPressed: () {
                app.captions.remove(caption);
                app.changed();
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ]),
        ]),
      );
}

// ---------------------------------------------------------------------------
// 5. Video Editor
// ---------------------------------------------------------------------------

const transitionNames = <String, String>{
  'none': 'None (hard cut)',
  'fade': 'Fade',
  'fadeblack': 'Fade through black',
  'dissolve': 'Dissolve',
  'wipeleft': 'Wipe left',
  'slideleft': 'Slide left',
  'slideright': 'Slide right',
  'circleopen': 'Circle open',
  'pixelize': 'Pixelize',
  'radial': 'Radial',
};

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  bool busy = false;

  Future<void> _addMedia() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true);
    if (res == null) return;
    setState(() => busy = true);
    var skipped = 0;
    for (final f in res.files) {
      final p = f.path;
      if (p == null) {
        skipped++;
        continue;
      }
      final lower = p.toLowerCase();
      final isImg = ['.jpg', '.jpeg', '.png', '.webp', '.bmp'].any(lower.endsWith);
      if (isImg) {
        app.clips.add(MediaClip(path: p, isImage: true, source: 0, thumb: p));
      } else {
        final d = await probeDuration(p);
        if (d <= 0.5) {
          skipped++;
          continue;
        }
        final th = await makeThumb(p);
        app.clips.add(MediaClip(path: p, isImage: false, source: d, thumb: th));
      }
    }
    app.changed();
    if (mounted) {
      setState(() => busy = false);
      if (skipped > 0) toast(context, '$skipped file(s) could not be read and were skipped.');
    }
  }

  Future<void> _pickMusic() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final p = res?.files.single.path;
    if (p == null) return;
    app.musicPath = p;
    app.musicLabel = p.split('/').last;
    app.changed();
  }

  Future<void> _editLayer([TextLayer? existing]) async {
    final textC = TextEditingController(text: existing?.text ?? '');
    final startC = TextEditingController(text: (existing?.start ?? 0).toStringAsFixed(1));
    final defaultEnd = math.max(3.0, math.min(6.0, app.timelineLength));
    final endC = TextEditingController(text: (existing?.end ?? defaultEnd).toStringAsFixed(1));
    var pos = existing?.position ?? 'bottom';
    var size = existing?.size ?? 72.0;
    var color = existing?.color ?? Colors.white;
    final colors = <Color>[Colors.white, gold, teal, Colors.yellowAccent, Colors.redAccent];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Add text' : 'Edit text'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: textC,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Text'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: startC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Start (s)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: endC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'End (s)'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: pos,
                decoration: const InputDecoration(labelText: 'Position'),
                items: const [
                  DropdownMenuItem(value: 'top', child: Text('Top')),
                  DropdownMenuItem(value: 'center', child: Text('Center')),
                  DropdownMenuItem(value: 'bottom', child: Text('Bottom')),
                ],
                onChanged: (v) => setD(() => pos = v ?? 'bottom'),
              ),
              Row(children: [
                const Text('Size'),
                Expanded(
                  child: Slider(value: size, min: 40, max: 120, onChanged: (v) => setD(() => size = v)),
                ),
              ]),
              Wrap(spacing: 8, children: [
                for (final c in colors)
                  GestureDetector(
                    onTap: () => setD(() => color = c),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: c,
                      child: color == c ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || textC.text.trim().isEmpty) return;
    final s = pd(startC.text) ?? 0;
    final e = pd(endC.text) ?? (s + 3);
    if (existing != null) {
      existing
        ..text = textC.text.trim()
        ..start = s
        ..end = math.max(e, s + 0.5)
        ..position = pos
        ..size = size
        ..color = color;
    } else {
      app.layers.add(TextLayer(
        text: textC.text.trim(),
        start: s,
        end: math.max(e, s + 0.5),
        position: pos,
        size: size,
        color: color,
      ));
    }
    app.changed();
  }

  Widget _clipTile(int i, MediaClip c) {
    return Card(
      key: ObjectKey(c),
      color: navy,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle, color: Colors.white54),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: c.thumb != null && File(c.thumb!).existsSync()
                    ? Image.file(File(c.thumb!), fit: BoxFit.cover)
                    : Container(color: panel, child: Icon(c.isImage ? Icons.image : Icons.movie, color: gold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${c.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(c.isImage ? 'Picture • ${c.length.toStringAsFixed(1)} s' : 'Video • ${c.length.toStringAsFixed(1)} s of ${c.source.toStringAsFixed(1)} s',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: () {
                app.clips.remove(c);
                app.changed();
              },
              icon: const Icon(Icons.close),
            ),
          ]),
          if (c.isImage)
            Row(children: [
              const Text('Show for', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: c.length.clamp(1.0, 15.0).toDouble(),
                  min: 1,
                  max: 15,
                  onChanged: (v) {
                    c.end = c.start + v;
                    app.changed();
                  },
                ),
              ),
            ])
          else if (c.source > 1.0)
            Row(children: [
              const Text('Trim', style: TextStyle(fontSize: 12)),
              Expanded(
                child: RangeSlider(
                  values: RangeValues(c.start.clamp(0.0, c.source).toDouble(), c.end.clamp(0.0, c.source).toDouble()),
                  min: 0,
                  max: c.source,
                  onChanged: (v) {
                    if (v.end - v.start < 0.8) return;
                    c.start = v.start;
                    c.end = v.end;
                    app.changed();
                  },
                ),
              ),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageShell(title: 'Video Editor', body: _children);

  List<Widget> _children(BuildContext context) => [
        Panel(
          title: 'Timeline (${app.clips.length} items • ${fmtDur(app.timelineLength)})',
          subtitle: 'Add videos and pictures, trim them, and drag the handle to reorder.',
          icon: Icons.video_library,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: navy),
                onPressed: busy ? null : _addMedia,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate),
                label: Text(busy ? 'Reading files...' : 'Add videos / pictures'),
              ),
            ),
            const SizedBox(height: 10),
            if (app.clips.isEmpty)
              const Note('Nothing on the timeline yet.')
            else
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = app.clips.removeAt(oldIndex);
                  app.clips.insert(newIndex, item);
                  app.changed();
                },
                children: [for (var i = 0; i < app.clips.length; i++) _clipTile(i, app.clips[i])],
              ),
          ]),
        ),
        Panel(
          title: 'Transitions & framing',
          icon: Icons.compare,
          child: Column(children: [
            DropdownButtonFormField<String>(
              value: app.transition,
              decoration: const InputDecoration(labelText: 'Transition between clips'),
              items: [
                for (final e in transitionNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                app.transition = v ?? 'none';
                app.changed();
              },
            ),
            if (app.transition != 'none')
              Row(children: [
                const Text('Length'),
                Expanded(
                  child: Slider(
                    value: app.transitionLen,
                    min: 0.2,
                    max: 1.5,
                    onChanged: (v) {
                      app.transitionLen = v;
                      app.changed();
                    },
                  ),
                ),
                Text('${app.transitionLen.toStringAsFixed(1)} s'),
              ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: app.framing,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Framing on the 16:9 screen'),
              items: const [
                DropdownMenuItem(value: 'blur', child: Text('Whole video + blurred background')),
                DropdownMenuItem(value: 'fit', child: Text('Whole video + black bars')),
                DropdownMenuItem(value: 'crop', child: Text('Fill screen (crops the edges)')),
              ],
              onChanged: (v) {
                app.framing = v ?? 'blur';
                app.changed();
              },
            ),
          ]),
        ),
        Panel(
          title: 'Text on video (${app.layers.length})',
          icon: Icons.text_fields,
          child: Column(children: [
            for (final l in app.layers)
              ListTile(
                key: ObjectKey(l),
                contentPadding: EdgeInsets.zero,
                title: Text(l.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${l.start.toStringAsFixed(1)}s – ${l.end.toStringAsFixed(1)}s • ${l.position}',
                    style: const TextStyle(color: Colors.white54)),
                onTap: () => _editLayer(l),
                trailing: IconButton(
                  onPressed: () {
                    app.layers.remove(l);
                    app.changed();
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _editLayer(),
                icon: const Icon(Icons.add),
                label: const Text('Add text'),
              ),
            ),
          ]),
        ),
        Panel(
          title: 'Audio: voiceover & music',
          icon: Icons.music_note,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Voiceover: ${app.voiceLabel}', style: const TextStyle(color: teal)),
            if (app.voicePath != null)
              Row(children: [
                const Text('Volume'),
                Expanded(
                  child: Slider(
                    value: app.voiceVolume,
                    min: 0,
                    max: 2,
                    onChanged: (v) {
                      app.voiceVolume = v;
                      app.changed();
                    },
                  ),
                ),
              ]),
            const Divider(),
            Text('Music: ${app.musicLabel}', style: const TextStyle(color: teal)),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _pickMusic,
                icon: const Icon(Icons.library_music),
                label: Text(app.musicPath == null ? 'Add music' : 'Change'),
              ),
              if (app.musicPath != null)
                TextButton(
                  onPressed: () {
                    app.musicPath = null;
                    app.musicLabel = 'None';
                    app.changed();
                  },
                  child: const Text('Remove'),
                ),
            ]),
            if (app.musicPath != null)
              Row(children: [
                const Text('Volume'),
                Expanded(
                  child: Slider(
                    value: app.musicVolume,
                    min: 0,
                    max: 1,
                    onChanged: (v) {
                      app.musicVolume = v;
                      app.changed();
                    },
                  ),
                ),
              ]),
            const SizedBox(height: 4),
            const Note(
                'Music loops to fill the video and fades out at the end. The original sound of your video clips is muted in this version. Only use music you have the right to use.'),
            if (app.voicePath != null && app.timelineLength > 0 && app.voiceDuration > app.timelineLength + 0.5)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Note('Your voiceover is longer than the timeline, so its end will be cut. Add more clips or lengthen pictures.',
                    color: Colors.orangeAccent),
              ),
          ]),
        ),
      ];
}

// ---------------------------------------------------------------------------
// 6. AI Video (storyboard + template-based scene creation)
// ---------------------------------------------------------------------------

class AiVideoPage extends StatefulWidget {
  const AiVideoPage({super.key});
  @override
  State<AiVideoPage> createState() => _AiVideoPageState();
}

class _AiVideoPageState extends State<AiVideoPage> {
  bool busy = false;
  String stage = '';

  int? genIndex;
  bool testing = false;
  String genStatus = '';
  String genNote = '';
  double genSeconds = 3;
  bool genPortrait = true;
  bool get genBusy => genIndex != null || testing;

  Future<bool> _generateScene(int i) async {
    final s = app.scenes[i];
    setState(() {
      genIndex = i;
      genStatus = 'Starting...';
      genNote = '';
    });
    final r = await generateClip(
      spaceInput: app.genSpace.text,
      prompt: s.prompt,
      token: app.genToken.text.trim(),
      endpointOverride: app.genEndpoint.text.trim(),
      seconds: genSeconds,
      portrait: genPortrait,
      say: (m) {
        if (mounted) setState(() => genStatus = m);
      },
    );
    if (!mounted) return false;
    if (r.path == null) {
      setState(() {
        genIndex = null;
        genStatus = '';
        genNote = r.error ?? 'Unknown error.';
      });
      return false;
    }
    final d = await probeDuration(r.path!);
    final th = await makeThumb(r.path!);
    s.videoPath = r.path;
    s.videoDuration = d;
    s.thumb = th;
    app.changed();
    if (mounted) {
      setState(() {
        genIndex = null;
        genStatus = '';
        genNote = d > 0.5 ? '' : 'The clip was downloaded but could not be read (length 0).';
      });
    }
    return d > 0.5;
  }

  Future<void> _generateAll() async {
    for (var i = 0; i < app.scenes.length; i++) {
      if (app.scenes[i].videoPath != null) continue;
      final ok = await _generateScene(i);
      if (!ok || !mounted) break;
    }
  }

  Future<void> _testSpace() async {
    setState(() {
      testing = true;
      genNote = '';
      genStatus = 'Testing the connection...';
    });
    final text = await describeSpace(app.genSpace.text, app.genToken.text.trim(), (m) {
      if (mounted) setState(() => genStatus = m);
    });
    if (!mounted) return;
    setState(() {
      testing = false;
      genStatus = '';
      genNote = text;
    });
  }

  void _draft() {
    final parts = splitText(currentScript());
    if (parts.isEmpty) return;
    final group = (parts.length / 8).ceil();
    final texts = <String>[];
    for (var i = 0; i < parts.length; i += group) {
      texts.add(parts.skip(i).take(group).join(' '));
    }
    final topic = app.topic.text.trim().isEmpty ? 'a hopeful message' : app.topic.text.trim();
    app.scenes.clear();
    for (var i = 0; i < texts.length; i++) {
      app.scenes.add(Scene(
        text: texts[i],
        theme: i % sceneThemes.length,
        prompt: 'Vertical 16:9 cinematic shot, ${visualIdeas[i % visualIdeas.length]}. '
            'Theme: $topic. Respectful, calm, no text, no faces.',
      ));
    }
    app.changed();
  }

  Future<void> _pickBackground(Scene s) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final p = res?.files.single.path;
    if (p == null) return;
    s.imagePath = p;
    app.changed();
  }

  Future<void> _build(bool thenExport) async {
    if (app.scenes.isEmpty) {
      toast(context, 'Create a storyboard first.');
      return;
    }
    setState(() {
      busy = true;
      stage = 'Preparing scenes...';
    });
    try {
      final n = app.scenes.length;
      const td = 0.6;
      final hasVoice = app.voicePath != null && app.voiceDuration > 0;
      final weights = app.scenes.map((s) => math.max(20, s.text.length).toDouble()).toList();
      final wsum = weights.fold<double>(0, (a, b) => a + b);
      final lens = <double>[];
      if (hasVoice) {
        final total = app.voiceDuration + 0.6 + (n - 1) * td;
        for (var i = 0; i < n; i++) {
          lens.add(math.max(2.5, total * weights[i] / wsum));
        }
      } else {
        for (final s in app.scenes) {
          lens.add(math.max(3.0, s.text.length * 0.07));
        }
      }
      setState(() => stage = 'Preparing scenes...');
      final dir = await workDir('scenes');
      app.clips.clear();
      app.layers.clear();
      for (var i = 0; i < n; i++) {
        final sc = app.scenes[i];
        if (sc.videoPath != null && File(sc.videoPath!).existsSync() && sc.videoDuration > 0.8) {
          final playLen = math.min(sc.videoDuration, lens[i]);
          final c = MediaClip(path: sc.videoPath!, isImage: false, source: sc.videoDuration, thumb: sc.thumb, to: playLen);
          c.hold = math.max(0.0, lens[i] - playLen);
          app.clips.add(c);
        } else {
          final out = '${dir.path}/scene_${ts()}_$i.png';
          await renderSceneCard(sc, out);
          app.clips.add(MediaClip(path: out, isImage: true, source: 0, thumb: out, to: lens[i]));
        }
      }
      app.transition = 'fade';
      app.transitionLen = td;
      app.framing = 'blur';
      // Create one timed caption per scene and burn captions into the MP4.
      // Caption timing follows the generated scene timeline; review it before publishing.
      app.captions.clear();
      var captionStart = 0.0;
      for (var i = 0; i < n; i++) {
        final captionEnd = captionStart + lens[i];
        // Scenes drawn as cards already show their text; captions are added for AI-clip scenes.
        if (app.scenes[i].videoPath != null) {
          app.captions.add(Caption(captionStart, captionEnd, app.scenes[i].text));
        }
        captionStart = captionEnd - (i < n - 1 ? td : 0.0);
      }
      app.burnCaptions = true;
      app.changed();
      if (!mounted) return;
      setState(() {
        busy = false;
        stage = '';
      });
      if (thenExport) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExportPage(autoStart: true)));
      } else {
        toast(context, 'Storyboard placed on the Video Editor timeline. Open Export to render it.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          stage = '';
        });
        toast(context, 'Could not build the storyboard video: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageShell(title: 'AI Video', body: _children);

  List<Widget> _children(BuildContext context) => [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0E2A40),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gold.withOpacity(.5)),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.check_circle, color: teal, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('FREE LOCAL VIDEO ASSEMBLY (available now)',
                    style: TextStyle(color: teal, fontWeight: FontWeight.bold)),
              ),
            ]),
            SizedBox(height: 4),
            Note('Splits your script into scenes, creates visual cards or uses your selected pictures, adds your recorded voiceover, creates timed captions, and exports an MP4. Without AI clips this is automated editing, not AI-generated footage.'),
            SizedBox(height: 10),
            Row(children: [
              Icon(Icons.cloud, color: Colors.orangeAccent, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('GENERATIVE AI FOOTAGE (online, optional)',
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              ),
            ]),
            SizedBox(height: 4),
            Note('Real AI-generated clips need a GPU, so they are made online by an open-source model (LTX-Video) on a free Hugging Face Space — not on your phone. Use the AI clips panel below. Free GPU quota is limited and queues can be slow.'),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          title: '1. Storyboard',
          subtitle: 'Built from your Script Studio text. For about five minutes of narration, prepare roughly 600–700 words; actual duration depends on the installed voice and speaking speed.',
          icon: Icons.view_carousel,
          child: Column(children: [
            const LangDropdown(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: navy),
                onPressed: busy ? null : _draft,
                icon: const Icon(Icons.auto_awesome),
                label: Text(app.scenes.isEmpty ? 'Create storyboard' : 'Re-create storyboard'),
              ),
            ),
          ]),
        ),
        if (app.scenes.isNotEmpty)
          Panel(
            title: 'AI clips (generative, online)',
            subtitle: 'Open-source LTX-Video on a free Hugging Face Space turns each scene prompt into a short moving clip.',
            icon: Icons.movie_filter,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: app.genSpace,
                decoration: const InputDecoration(labelText: 'Space (owner/name or link)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: app.genToken,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Hugging Face token (optional)',
                    helperText: 'Gives a larger free GPU quota. Kept in memory only, never saved.'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: app.genEndpoint,
                decoration: const InputDecoration(labelText: 'Endpoint name (optional, advanced)'),
              ),
              Row(children: [
                const Text('Clip length'),
                Expanded(
                  child: Slider(
                    value: genSeconds,
                    min: 2,
                    max: 6,
                    divisions: 8,
                    onChanged: (v) => setState(() => genSeconds = v),
                  ),
                ),
                Text('${genSeconds.toStringAsFixed(1)} s'),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Portrait (16:9) when the Space allows'),
                value: genPortrait,
                onChanged: (v) => setState(() => genPortrait = v),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: genBusy ? null : _testSpace,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: navy),
                  onPressed: genBusy || busy ? null : _generateAll,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate all AI clips'),
                ),
              ]),
              if (genStatus.isNotEmpty) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Note(genStatus),
              ],
              if (genNote.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(genNote, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12.5)),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: genNote));
                    if (mounted) toast(context, 'Copied.');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy message'),
                ),
              ],
              const SizedBox(height: 8),
              const Note(
                  'Your prompts are sent to a community Space hosted by Hugging Face, so avoid private text. Clips are short (a few seconds), take 1–3 minutes each, and may fail when the free quota is used up or the Space is busy or changed. Scenes without an AI clip still use designed cards.'),
            ]),
          ),
        for (var i = 0; i < app.scenes.length; i++) _sceneCard(i, app.scenes[i]),
        if (app.scenes.isNotEmpty)
          Panel(
            title: '2. Build the video',
            icon: Icons.movie_creation,
            child: Column(children: [
              const Note(
                  'Narration: record your own voice first in My Voice (or import audio). Scene timing follows your recording; without one, timing is estimated from the text length.'),
              const SizedBox(height: 8),
              if (busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Note(stage),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _build(false),
                    icon: const Icon(Icons.timeline),
                    label: const Text('Build onto the timeline'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _build(true),
                    icon: const Icon(Icons.high_quality),
                    label: const Text('Build & export 1080p'),
                  ),
                ),
              ],
            ]),
          ),
      ];

  Widget _sceneCard(int i, Scene s) {
    return Card(
      key: ObjectKey(s),
      color: panel,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Scene ${i + 1}', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              tooltip: 'Delete scene',
              onPressed: () {
                app.scenes.remove(s);
                app.changed();
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ]),
          TextFormField(
            initialValue: s.text,
            minLines: 2,
            maxLines: 6,
            textDirection: isRtl(s.text) ? TextDirection.rtl : TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'Scene text'),
            onChanged: (v) => s.text = v,
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (var t = 0; t < sceneThemes.length; t++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    s.theme = t;
                    app.changed();
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: sceneThemes[t]),
                      border: Border.all(color: s.theme == t ? gold : Colors.white24, width: s.theme == t ? 3 : 1),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _pickBackground(s),
              icon: Icon(s.imagePath == null ? Icons.image : Icons.check, size: 18),
              label: Text(s.imagePath == null ? 'Background' : 'Picture set'),
            ),
            if (s.imagePath != null)
              IconButton(
                onPressed: () {
                  s.imagePath = null;
                  app.changed();
                },
                icon: const Icon(Icons.close, size: 18),
              ),
          ]),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: s.prompt,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Visual prompt (English works best)'),
            onChanged: (v) => s.prompt = v,
          ),
          const SizedBox(height: 8),
          if (genIndex == i) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Note(genStatus),
          ] else
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                onPressed: genBusy || busy ? null : () => _generateScene(i),
                icon: const Icon(Icons.movie_filter, size: 18),
                label: Text(s.videoPath == null ? 'Generate AI clip' : 'Regenerate'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.prompt));
                  if (mounted) toast(context, 'Prompt copied.');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy prompt'),
              ),
              if (s.videoPath != null) ...[
                const Icon(Icons.check_circle, color: teal, size: 18),
                Text('AI clip ready (${s.videoDuration.toStringAsFixed(1)} s)',
                    style: const TextStyle(color: teal, fontSize: 12.5)),
                TextButton(
                  onPressed: () {
                    s.videoPath = null;
                    s.videoDuration = 0;
                    s.thumb = null;
                    app.changed();
                  },
                  child: const Text('Remove'),
                ),
              ],
            ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Export 1080p MP4
// ---------------------------------------------------------------------------

class ExportPage extends StatefulWidget {
  const ExportPage({super.key, this.autoStart = false});
  final bool autoStart;
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  bool busy = false;
  double progress = 0;
  String? error;
  String? resultPath;
  VideoPlayerController? player;
  final Stopwatch sw = Stopwatch();
  bool savedToGallery = false;

  Future<void> _saveToGallery() async {
    final p = resultPath;
    if (p == null) return;
    try {
      await Gal.putVideo(p, album: 'Sahibi Vision');
      if (!mounted) return;
      setState(() => savedToGallery = true);
      toast(context, 'Saved to your Gallery (album "Sahibi Vision").');
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not save to the Gallery: $e  — allow photo/video access for the app in Android Settings and try again.');
      }
    }
  }

  Future<void> _deleteExport() async {
    final p = resultPath;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this export?'),
        content: Text(savedToGallery
            ? 'This removes the copy inside the app. The copy you saved to the Gallery stays there — delete it from the Gallery app if you no longer want it.'
            : 'The exported video will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await player?.dispose();
    player = null;
    try {
      await File(p).delete();
    } catch (_) {}
    if (app.lastExport == p) {
      app.lastExport = null;
      app.changed();
    }
    if (!mounted) return;
    setState(() {
      resultPath = null;
      savedToGallery = false;
      progress = 0;
    });
    toast(context, 'Export deleted.');
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (busy) return;
    await player?.dispose();
    player = null;
    setState(() {
      busy = true;
      progress = 0;
      error = null;
      resultPath = null;
      savedToGallery = false;
    });
    sw
      ..reset()
      ..start();
    final r = await runExport((p) {
      if (mounted) setState(() => progress = p);
    });
    sw.stop();
    if (!mounted) return;
    if (r.path != null) {
      final c = VideoPlayerController.file(File(r.path!));
      try {
        await c.initialize();
        player = c;
      } catch (_) {
        await c.dispose();
      }
      app.lastExport = r.path;
      app.changed();
    }
    setState(() {
      busy = false;
      error = r.error;
      resultPath = r.path;
      if (r.path != null) progress = 1;
    });
  }

  @override
  Widget build(BuildContext context) => PageShell(title: 'Export 1080p', body: _children);

  List<Widget> _children(BuildContext context) {
    final problems = <String>[];
    if (app.clips.isEmpty) problems.add('Add videos or pictures in the Video Editor (or build an AI Video storyboard).');
    return [
      Panel(
        title: 'Export settings',
        icon: Icons.high_quality,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('1080 × 1920 (vertical 16:9) • 30 fps • H.264 + AAC MP4'),
          const SizedBox(height: 8),
          Text('Timeline: ${app.clips.length} items • ${fmtDur(app.timelineLength)}'),
          Text('Voiceover: ${app.voiceLabel}'),
          Text('Music: ${app.musicLabel}'),
          Text('Text layers: ${app.layers.length} • Captions: ${app.captions.length}${app.burnCaptions ? ' (burned in)' : ' (not burned in)'}'),
          if (problems.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final p in problems) Note(p, color: Colors.orangeAccent),
          ],
          const SizedBox(height: 12),
          if (!busy)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: navy,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: problems.isEmpty ? _start : null,
              icon: const Icon(Icons.movie),
              label: const Text('Export MP4'),
            )
          else ...[
            LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 8),
            const SizedBox(height: 8),
            Text('Rendering ${(progress * 100).round()}% • ${sw.elapsed.inSeconds}s elapsed'),
            const SizedBox(height: 4),
            const Note('Keep the app open. A 1-minute video can take a few minutes on a phone.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => FFmpegKit.cancel(),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel export'),
            ),
          ],
        ]),
      ),
      if (error != null)
        Panel(
          title: 'Export failed',
          icon: Icons.error_outline,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12.5)),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: error!));
                  if (context.mounted) toast(context, 'Error text copied.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy error'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ]),
          ]),
        ),
      if (resultPath != null)
        Panel(
          title: 'Your video is ready',
          icon: Icons.check_circle,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (player != null && player!.value.isInitialized) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: AspectRatio(aspectRatio: player!.value.aspectRatio, child: VideoPlayer(player!)),
                ),
              ),
              Row(children: [
                IconButton(
                  onPressed: () async {
                    if (player!.value.isPlaying) {
                      await player!.pause();
                    } else {
                      await player!.play();
                    }
                    setState(() {});
                  },
                  icon: Icon(player!.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 34),
                ),
                Expanded(child: VideoProgressIndicator(player!, allowScrubbing: true)),
              ]),
            ],
            Text('Saved in the app: ${resultPath!.split('/').last}', style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: navy),
                onPressed: _saveToGallery,
                icon: Icon(savedToGallery ? Icons.check_circle : Icons.save_alt),
                label: Text(savedToGallery ? 'Saved to Gallery (tap to save again)' : 'Save to Gallery'),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.shareXFiles([XFile(resultPath!)], text: 'Made with Sahibi Vision AI Studio'),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: _deleteExport,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Note('Save to Gallery puts a normal copy in your phone Gallery. Share sends the file to WhatsApp, Telegram, Drive and other apps. Delete removes the copy inside this app only.'),
          ]),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 8. About Us
// ---------------------------------------------------------------------------

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About Us')),
        body: ListView(padding: const EdgeInsets.all(20), children: const [
          Icon(Icons.auto_awesome, color: gold, size: 56),
          SizedBox(height: 12),
          Center(
            child: Text('SAHIBI VISION AI STUDIO',
                style: TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          SizedBox(height: 4),
          Center(child: Text('Version 1.0', style: TextStyle(color: Colors.white60))),
          SizedBox(height: 24),
          Panel(
            title: 'Developer',
            icon: Icons.person,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Khial Muhammad Sahibi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              SizedBox(height: 10),
              Row(children: [Icon(Icons.phone, color: teal, size: 18), SizedBox(width: 8), SelectableText('+93 77 111 0 555')]),
              SizedBox(height: 8),
              Row(children: [Icon(Icons.email, color: teal, size: 18), SizedBox(width: 8), SelectableText('khialsahibi@gmail.com')]),
            ]),
          ),
          Panel(
            title: 'Our mission',
            icon: Icons.favorite,
            child: Text('Made for faith, knowledge and inspiration — helping you create meaningful videos in English, Dari and Pashto.'),
          ),
        ]),
      );
}
