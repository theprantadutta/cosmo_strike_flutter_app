import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';

class AudioService {
  static AudioService? _instance;
  AudioPlayer? _musicPlayer;
  final StorageService _storageService = StorageService();

  // SoLoud for low-latency game sound effects
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _loadedSounds = {};

  // List of sounds to pre-load
  static const List<String> _soundsToPreload = [
    'eat',
    'level_up',
    'game_over',
    'game_start',
    'power_up',
    'button_click',
  ];

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _initialized = false;

  AudioService._internal();

  factory AudioService() {
    _instance ??= AudioService._internal();
    return _instance!;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _soundEnabled = await _storageService.isSoundEnabled();
    _musicEnabled = await _storageService.isMusicEnabled();

    // Initialize SoLoud engine
    try {
      await _soloud.init();
      debugPrint('SoLoud engine initialized');

      // Pre-load all sounds
      await _preloadSounds();
    } catch (e) {
      debugPrint('Failed to initialize SoLoud: $e');
    }

    _initialized = true;
    debugPrint(
      'AudioService initialized with SoLoud - ${_loadedSounds.length} sounds loaded',
    );
  }

  /// Pre-load all sound effects into SoLoud
  Future<void> _preloadSounds() async {
    for (final soundName in _soundsToPreload) {
      try {
        final source = await _soloud.loadAsset('assets/audio/$soundName.wav');
        _loadedSounds[soundName] = source;
      } catch (e) {
        debugPrint('Failed to preload sound $soundName: $e');
      }
    }
  }

  /// Play a sound effect - instant, non-blocking
  void playSound(String soundName) {
    if (!_initialized || !_soundEnabled) return;

    final source = _loadedSounds[soundName];
    if (source != null) {
      // SoLoud.play() is non-blocking and low-latency
      _soloud.play(source);
    } else {
      // Fallback to system sound if not pre-loaded
      _playSystemSound(soundName);
    }
  }

  void _playSystemSound(String soundName) {
    switch (soundName) {
      case 'eat':
      case 'button_click':
        SystemSound.play(SystemSoundType.click);
        break;
      case 'game_over':
        SystemSound.play(SystemSoundType.alert);
        break;
      case 'level_up':
      case 'high_score':
      case 'game_start':
      case 'power_up':
        SystemSound.play(SystemSoundType.click);
        break;
    }
  }

  Future<void> playBackgroundMusic() async {
    if (!_initialized || !_musicEnabled) return;

    _musicPlayer ??= AudioPlayer();

    try {
      await _musicPlayer!.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer!.setVolume(0.4);
      await _musicPlayer!.play(AssetSource('audio/background_music.mp3'));
    } catch (e) {
      debugPrint('Background music not available: $e');
    }
  }

  Future<void> stopBackgroundMusic() async {
    try {
      await _musicPlayer?.stop();
    } catch (e) {
      debugPrint('Error stopping music: $e');
    }
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    await _storageService.setSoundEnabled(enabled);
  }

  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;
    await _storageService.setMusicEnabled(enabled);

    if (enabled) {
      await playBackgroundMusic();
    } else {
      await stopBackgroundMusic();
    }
  }

  bool get isSoundEnabled => _soundEnabled;
  bool get isMusicEnabled => _musicEnabled;

  void dispose() {
    // Dispose all loaded sounds
    for (final source in _loadedSounds.values) {
      _soloud.disposeSource(source);
    }
    _loadedSounds.clear();

    _soloud.deinit();
    _musicPlayer?.dispose();
    _musicPlayer = null;
    _initialized = false;
  }
}
