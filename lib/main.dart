import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(const SahibiVisionApp());

const navy = Color(0xFF071A31);
const gold = Color(0xFFD5AD59);
const teal = Color(0xFF21B6A8);

class SahibiVisionApp extends StatelessWidget {
  const SahibiVisionApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sahibi Vision AI Studio',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: gold),
      ),
      home: const StudioHome(),
    );
  }
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  final FlutterTts tts = FlutterTts();
  final TextEditingController topic = TextEditingController(text: 'Never lose hope in Allah');
  final TextEditingController script = TextEditingController();
  String language = 'English';
  String status = 'Ready to create';
  bool speaking = false;

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

  void generateScript() {
    final t = templates[language]!;
    script.text = '${t['opening']}\n\n${t['middle']}\n\n${t['ending']}';
    setState(() => status = 'Script created from the offline $language template.');
  }

  Future<void> speak() async {
    if (script.text.trim().isEmpty) generateScript();
    try {
      final locale = {'English': 'en-US', 'Dari': 'fa-IR', 'Pashto': 'ps-AF'}[language]!;
      await tts.setLanguage(locale);
      await tts.setSpeechRate(0.43);
      await tts.setPitch(0.92);
      await tts.speak(script.text);
      setState(() => status = 'Android text-to-speech started. Voice depends on installed device voices.');
    } catch (e) {
      setState(() => status = 'Speech engine unavailable for this language. Check Android Text-to-speech settings.');
    }
  }

  @override
  void dispose() {
    topic.dispose();
    script.dispose();
    tts.stop();
    super.dispose();
  }

  Widget tile(IconData icon, String title, String subtitle, VoidCallback action) {
    return Card(
      color: const Color(0xFF102944),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: gold.withOpacity(.15), child: Icon(icon, color: gold)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing: const Icon(Icons.chevron_right, color: teal),
        onTap: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAHIBI VISION', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [IconButton(onPressed: () => setState(() => status = 'Version 0.1 — offline starter'), icon: const Icon(Icons.info_outline))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF173B56), navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: gold.withOpacity(.65)),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome, color: gold, size: 34),
              SizedBox(height: 12),
              Text('AI VIDEO STUDIO', style: TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
              SizedBox(height: 6),
              Text('Create meaningful videos. Share faith, knowledge and inspiration.', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 12),
              Text('FREE STARTER • NO API KEY REQUIRED', style: TextStyle(color: teal, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 18),
          const Text('CREATE A SCRIPT', style: TextStyle(color: gold, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: language,
            decoration: const InputDecoration(labelText: 'Language', border: OutlineInputBorder()),
            items: templates.keys.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) => setState(() => language = v!),
          ),
          const SizedBox(height: 10),
          TextField(controller: topic, decoration: const InputDecoration(labelText: 'Video topic', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: navy),
            onPressed: generateScript,
            icon: const Icon(Icons.edit_note),
            label: const Text('Generate starter script'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: script, minLines: 5, maxLines: 10,
            decoration: const InputDecoration(labelText: 'Your script', hintText: 'Generate a script or write your own...', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: speak, icon: const Icon(Icons.record_voice_over), label: const Text('Speak script'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: script.text));
              setState(() => status = 'Script copied.');
            }, icon: const Icon(Icons.copy), label: const Text('Copy script'))),
          ]),
          const SizedBox(height: 18),
          const Text('STUDIO MODULES', style: TextStyle(color: gold, fontWeight: FontWeight.bold, letterSpacing: 1)),
          tile(Icons.subtitles, 'Subtitle workspace', 'Prepare captions from your script', () => setState(() => status = 'Subtitle workspace is planned for the next build.')),
          tile(Icons.video_library, 'Video editor', 'Import and arrange video clips', () => setState(() => status = 'Video timeline and clip editing are planned for the next build.')),
          tile(Icons.movie_creation, 'AI video generation', 'Create scenes from prompts', () => setState(() => status = 'Generative video requires a compatible on-device model or external service; not included in this offline starter.')),
          tile(Icons.high_quality, '1080p export', 'Render a finished MP4 video', () => setState(() => status = '1080p rendering is planned for the next build.')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0E2A40), borderRadius: BorderRadius.circular(12)),
            child: Text(status, style: const TextStyle(color: teal)),
          ),
          const SizedBox(height: 12),
          const Text('Note: Android speech languages depend on the voices installed on your phone. Dari and Pashto TTS may not be available by default.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
