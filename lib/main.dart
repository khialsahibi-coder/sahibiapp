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

const templates = <String, Map<String, String>>{
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
