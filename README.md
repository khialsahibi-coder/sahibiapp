# SAHIBI VISION AI STUDIO — Android starter

This is Version 0.1: a Flutter starter app with a branded interface, offline script templates in English/Dari/Pashto, copy-to-clipboard, and Android text-to-speech through `flutter_tts`.

## Important scope notes
- This starter does **not** yet implement a real video timeline, clip trimming, subtitle timing, MP4 rendering, or generative AI video.
- It does not use paid APIs or require an API key.
- Android TTS uses voices installed on the device. English is commonly available; Dari/Persian and Pashto support varies by Android speech engine.
- The "AI script" button currently uses editable offline starter templates, not a large language model.

## Build APK on a computer with Flutter + Android SDK
1. Install Flutter stable and Android Studio (Android SDK + platform tools).
2. Extract this project.
3. In the project folder run:
   ```bash
   flutter pub get
   flutter doctor
   flutter build apk --release
   ```
4. APK output:
   `build/app/outputs/flutter-apk/app-release.apk`

## Android setup
Create a Flutter project using `flutter create --platforms=android .` if the generated project lacks platform folders. Ensure Android minSdk is compatible with the current `flutter_tts` plugin. Then run the build commands above.

## Roadmap
- v0.2: media picker, clip list, timeline model, subtitle editor.
- v0.3: FFmpeg-based rendering and 1080x1920 export.
- v0.4: subtitle timing and audio/video synchronization.
- v0.5: optional on-device AI models where hardware permits.
