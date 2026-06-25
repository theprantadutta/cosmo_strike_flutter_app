import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

enum SoundType { sfx, music, ambient, ui }

enum AudioEnvironment {
  classic,
  modern,
  neon,
  retro,
  space,
  ocean,
  cyberpunk,
  forest,
  desert,
  crystal,
}

class SpatialAudioPosition {
  final double x; // -1.0 to 1.0 (left to right)
  final double y; // -1.0 to 1.0 (bottom to top)
  final double distance; // 0.0 to 1.0 (close to far)

  const SpatialAudioPosition({
    required this.x,
    required this.y,
    this.distance = 0.5,
  });

  static const center = SpatialAudioPosition(x: 0.0, y: 0.0);
  static const left = SpatialAudioPosition(x: -1.0, y: 0.0);
  static const right = SpatialAudioPosition(x: 1.0, y: 0.0);
  static const top = SpatialAudioPosition(x: 0.0, y: 1.0);
  static const bottom = SpatialAudioPosition(x: 0.0, y: -1.0);
}

class EnhancedAudioService {
  static final EnhancedAudioService _instance =
      EnhancedAudioService._internal();
  factory EnhancedAudioService() => _instance;
  EnhancedAudioService._internal();

  // Audio players for different channels
  final Map<String, AudioPlayer> _sfxPlayers = {};
  final Map<String, AudioPlayer> _musicPlayers = {};
  final Map<String, AudioPlayer> _ambientPlayers = {};
  final Map<String, AudioPlayer> _uiPlayers = {};

  // Volume controls
  double _masterVolume = 1.0;
  double _sfxVolume = 1.0;
  double _musicVolume = 0.7;
  double _ambientVolume = 0.5;
  double _uiVolume = 0.8;

  bool _sfxEnabled = true;
  bool _musicEnabled = true;
  bool _ambientEnabled = true;
  bool _spatialAudioEnabled = true;

  AudioEnvironment _currentEnvironment = AudioEnvironment.classic;

  // Audio environment settings
  final Map<AudioEnvironment, Map<String, dynamic>> _environmentSettings = {
    AudioEnvironment.classic: {
      'reverb': 0.1,
      'echo': 0.05,
      'bass': 1.0,
      'treble': 1.0,
    },
    AudioEnvironment.cyberpunk: {
      'reverb': 0.3,
      'echo': 0.4,
      'bass': 1.2,
      'treble': 1.1,
    },
    AudioEnvironment.forest: {
      'reverb': 0.2,
      'echo': 0.1,
      'bass': 0.9,
      'treble': 1.0,
    },
    AudioEnvironment.ocean: {
      'reverb': 0.4,
      'echo': 0.3,
      'bass': 1.1,
      'treble': 0.9,
    },
    AudioEnvironment.crystal: {
      'reverb': 0.5,
      'echo': 0.2,
      'bass': 0.8,
      'treble': 1.3,
    },
    // Add more environments as needed
  };

  bool get sfxEnabled => _sfxEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get ambientEnabled => _ambientEnabled;
  bool get spatialAudioEnabled => _spatialAudioEnabled;

  double get masterVolume => _masterVolume;
  double get sfxVolume => _sfxVolume;
  double get musicVolume => _musicVolume;
  double get ambientVolume => _ambientVolume;
  double get uiVolume => _uiVolume;

  AudioEnvironment get currentEnvironment => _currentEnvironment;

  Future<void> initialize() async {
    try {
      // Pre-warm audio players
      await _createAudioPlayers();

      if (kDebugMode) {
        print('Enhanced Audio Service initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Audio initialization error: $e');
      }
    }
  }

  Future<void> _createAudioPlayers() async {
    // Create dedicated players for different sound categories
    for (int i = 0; i < 5; i++) {
      _sfxPlayers['sfx_$i'] = AudioPlayer();
      _uiPlayers['ui_$i'] = AudioPlayer();
    }

    for (int i = 0; i < 2; i++) {
      _musicPlayers['music_$i'] = AudioPlayer();
      _ambientPlayers['ambient_$i'] = AudioPlayer();
    }
  }

  // Volume Controls

  Future<void> setMasterVolume(double volume) async {
    _masterVolume = volume.clamp(0.0, 1.0);
    await _updateAllVolumes();
  }

  Future<void> setSfxVolume(double volume) async {
    _sfxVolume = volume.clamp(0.0, 1.0);
    await _updatePlayerVolumes(_sfxPlayers, _sfxVolume);
  }

  Future<void> setMusicVolume(double volume) async {
    _musicVolume = volume.clamp(0.0, 1.0);
    await _updatePlayerVolumes(_musicPlayers, _musicVolume);
  }

  Future<void> setAmbientVolume(double volume) async {
    _ambientVolume = volume.clamp(0.0, 1.0);
    await _updatePlayerVolumes(_ambientPlayers, _ambientVolume);
  }

  Future<void> setUiVolume(double volume) async {
    _uiVolume = volume.clamp(0.0, 1.0);
    await _updatePlayerVolumes(_uiPlayers, _uiVolume);
  }

  Future<void> _updateAllVolumes() async {
    await _updatePlayerVolumes(_sfxPlayers, _sfxVolume);
    await _updatePlayerVolumes(_musicPlayers, _musicVolume);
    await _updatePlayerVolumes(_ambientPlayers, _ambientVolume);
    await _updatePlayerVolumes(_uiPlayers, _uiVolume);
  }

  Future<void> _updatePlayerVolumes(
    Map<String, AudioPlayer> players,
    double baseVolume,
  ) async {
    final effectiveVolume = baseVolume * _masterVolume;
    for (final player in players.values) {
      await player.setVolume(effectiveVolume);
    }
  }

  // Enable/Disable Controls

  void setSfxEnabled(bool enabled) {
    _sfxEnabled = enabled;
    if (!enabled) {
      _stopAllInCategory(_sfxPlayers);
    }
  }

  void setMusicEnabled(bool enabled) {
    _musicEnabled = enabled;
    if (!enabled) {
      _stopAllInCategory(_musicPlayers);
    }
  }

  void setAmbientEnabled(bool enabled) {
    _ambientEnabled = enabled;
    if (!enabled) {
      _stopAllInCategory(_ambientPlayers);
    }
  }

  void setSpatialAudioEnabled(bool enabled) {
    _spatialAudioEnabled = enabled;
  }

  Future<void> _stopAllInCategory(Map<String, AudioPlayer> players) async {
    for (final player in players.values) {
      await player.stop();
    }
  }

  // Environment Control

  Future<void> setAudioEnvironment(AudioEnvironment environment) async {
    _currentEnvironment = environment;
    await _applyEnvironmentSettings();
  }

  Future<void> _applyEnvironmentSettings() async {
    final settings = _environmentSettings[_currentEnvironment] ?? {};

    // Apply environment-specific audio processing
    // Note: This is a simplified implementation
    // In a real app, you might use audio effects libraries

    if (kDebugMode) {
      print('Applied audio environment: $_currentEnvironment');
      print('Settings: $settings');
    }
  }

  // Core Audio Playback

  /// Play SFX - fire and forget, non-blocking
  void playSfx(
    String soundId, {
    double? volume,
    SpatialAudioPosition? position,
    double? pitch,
    bool loop = false,
  }) {
    if (!_sfxEnabled) return;

    // Fire and forget - don't block game loop
    _playSfxAsync(
      soundId,
      volume: volume,
      position: position,
      pitch: pitch,
      loop: loop,
    );
  }

  Future<void> _playSfxAsync(
    String soundId, {
    double? volume,
    SpatialAudioPosition? position,
    double? pitch,
    bool loop = false,
  }) async {
    try {
      final player = _getAvailablePlayer(_sfxPlayers);
      if (player == null) return;

      final effectiveVolume = _calculateEffectiveVolume(
        baseVolume: volume ?? 1.0,
        categoryVolume: _sfxVolume,
        position: position,
      );

      await player.setVolume(effectiveVolume);

      if (pitch != null) {
        await player.setPlaybackRate(pitch);
      }

      await player.play(AssetSource('audio/$soundId.wav'));

      if (loop) {
        await player.setReleaseMode(ReleaseMode.loop);
      }
    } catch (e) {
      if (kDebugMode) print('SFX playback error: $e');
    }
  }

  Future<void> playMusic(
    String musicId, {
    double? volume,
    bool loop = true,
    Duration? fadeInDuration,
  }) async {
    if (!_musicEnabled) return;

    try {
      final player = _getAvailablePlayer(_musicPlayers);
      if (player == null) return;

      final effectiveVolume = (volume ?? 1.0) * _musicVolume * _masterVolume;

      if (fadeInDuration != null) {
        await player.setVolume(0.0);
        await player.play(AssetSource('audio/$musicId.mp3'));
        await _fadeVolume(player, 0.0, effectiveVolume, fadeInDuration);
      } else {
        await player.setVolume(effectiveVolume);
        await player.play(AssetSource('audio/$musicId.mp3'));
      }

      if (loop) {
        await player.setReleaseMode(ReleaseMode.loop);
      }
    } catch (e) {
      if (kDebugMode) print('Music playback error: $e');
    }
  }

  Future<void> playAmbient(
    String ambientId, {
    double? volume,
    bool loop = true,
  }) async {
    if (!_ambientEnabled) return;

    try {
      final player = _getAvailablePlayer(_ambientPlayers);
      if (player == null) return;

      final effectiveVolume = (volume ?? 1.0) * _ambientVolume * _masterVolume;
      await player.setVolume(effectiveVolume);
      await player.play(AssetSource('audio/$ambientId.wav'));

      if (loop) {
        await player.setReleaseMode(ReleaseMode.loop);
      }
    } catch (e) {
      if (kDebugMode) print('Ambient playback error: $e');
    }
  }

  /// Play UI sound - fire and forget, non-blocking
  void playUi(String soundId, {double? volume}) {
    _playUiAsync(soundId, volume: volume);
  }

  Future<void> _playUiAsync(String soundId, {double? volume}) async {
    try {
      final player = _getAvailablePlayer(_uiPlayers);
      if (player == null) return;

      final effectiveVolume = (volume ?? 1.0) * _uiVolume * _masterVolume;
      await player.setVolume(effectiveVolume);
      await player.play(AssetSource('audio/$soundId.wav'));
    } catch (e) {
      if (kDebugMode) print('UI audio playback error: $e');
    }
  }

  // Spatial Audio Helpers

  double _calculateEffectiveVolume({
    required double baseVolume,
    required double categoryVolume,
    SpatialAudioPosition? position,
  }) {
    double volume = baseVolume * categoryVolume * _masterVolume;

    if (_spatialAudioEnabled && position != null) {
      // Apply distance attenuation
      volume *= (1.0 - position.distance * 0.3);

      // Apply stereo positioning (simplified)
      // In a real implementation, you'd use proper spatial audio APIs
      if (position.x != 0.0) {
        volume *= (1.0 - (position.x.abs()) * 0.1);
      }
    }

    return volume.clamp(0.0, 1.0);
  }

  AudioPlayer? _getAvailablePlayer(Map<String, AudioPlayer> players) {
    for (final player in players.values) {
      if (player.state != PlayerState.playing) {
        return player;
      }
    }
    return players.values.first; // Fallback to first player
  }

  Future<void> _fadeVolume(
    AudioPlayer player,
    double fromVolume,
    double toVolume,
    Duration duration,
  ) async {
    const steps = 20;
    final stepDuration = Duration(
      milliseconds: duration.inMilliseconds ~/ steps,
    );
    final volumeStep = (toVolume - fromVolume) / steps;

    for (int i = 0; i <= steps; i++) {
      final currentVolume = fromVolume + (volumeStep * i);
      await player.setVolume(currentVolume);
      await Future.delayed(stepDuration);
    }
  }

  // Game-Specific Audio Methods - all fire and forget, non-blocking

  void playFoodEaten({SpatialAudioPosition? position}) {
    playSfx('food_eat', position: position);
  }

  void playBonusFoodEaten({SpatialAudioPosition? position}) {
    playSfx('bonus_food_eat', position: position, pitch: 1.2);
  }

  void playSpecialFoodEaten({SpatialAudioPosition? position}) {
    playSfx('special_food_eat', position: position, pitch: 1.4);
  }

  void playPowerUpCollected({SpatialAudioPosition? position}) {
    playSfx('power_up_collect', position: position);
  }

  void playLevelUp() {
    playSfx('level_up', volume: 1.2);
  }

  void playGameOver() {
    playSfx('game_over', volume: 1.0);
  }

  void playWallHit({SpatialAudioPosition? position}) {
    playSfx('wall_hit', position: position, pitch: 0.8);
  }

  void playSelfCollision({SpatialAudioPosition? position}) {
    playSfx('self_collision', position: position, pitch: 0.9);
  }

  void playAchievementUnlocked() {
    playSfx('achievement_unlock', volume: 1.1);
  }

  void playButtonClick() {
    playUi('button_click');
  }

  void playMenuNavigation() {
    playUi('menu_navigate');
  }

  void playScoreMilestone() {
    playSfx('score_milestone', volume: 1.1);
  }

  // Theme-Specific Audio

  Future<void> playThemeMusic(GameTheme theme) async {
    String musicId;
    switch (theme) {
      case GameTheme.classic:
        musicId = 'classic_theme';
        break;
      case GameTheme.modern:
        musicId = 'modern_theme';
        break;
      case GameTheme.neon:
        musicId = 'neon_theme';
        break;
      case GameTheme.retro:
        musicId = 'retro_theme';
        break;
      case GameTheme.space:
        musicId = 'space_theme';
        break;
      case GameTheme.ocean:
        musicId = 'ocean_theme';
        break;
      case GameTheme.cyberpunk:
        musicId = 'cyberpunk_theme';
        break;
      case GameTheme.forest:
        musicId = 'forest_theme';
        break;
      case GameTheme.desert:
        musicId = 'desert_theme';
        break;
      case GameTheme.crystal:
        musicId = 'crystal_theme';
        break;
      case GameTheme.accessible:
        // Accessibility skin has no bespoke track — reuse the default theme.
        musicId = 'classic_theme';
        break;
    }

    await setAudioEnvironment(_themeToAudioEnvironment(theme));
    await playMusic(musicId, fadeInDuration: const Duration(seconds: 2));
  }

  Future<void> playThemeAmbient(GameTheme theme) async {
    String ambientId;
    switch (theme) {
      case GameTheme.ocean:
        ambientId = 'ocean_waves';
        break;
      case GameTheme.forest:
        ambientId = 'forest_birds';
        break;
      case GameTheme.desert:
        ambientId = 'desert_wind';
        break;
      case GameTheme.space:
        ambientId = 'space_ambient';
        break;
      case GameTheme.cyberpunk:
        ambientId = 'cyberpunk_ambient';
        break;
      default:
        return; // No ambient for other themes
    }

    await playAmbient(ambientId, volume: 0.3);
  }

  AudioEnvironment _themeToAudioEnvironment(GameTheme theme) {
    switch (theme) {
      case GameTheme.classic:
        return AudioEnvironment.classic;
      case GameTheme.modern:
        return AudioEnvironment.modern;
      case GameTheme.neon:
        return AudioEnvironment.neon;
      case GameTheme.retro:
        return AudioEnvironment.retro;
      case GameTheme.space:
        return AudioEnvironment.space;
      case GameTheme.ocean:
        return AudioEnvironment.ocean;
      case GameTheme.cyberpunk:
        return AudioEnvironment.cyberpunk;
      case GameTheme.forest:
        return AudioEnvironment.forest;
      case GameTheme.desert:
        return AudioEnvironment.desert;
      case GameTheme.crystal:
        return AudioEnvironment.crystal;
      case GameTheme.accessible:
        return AudioEnvironment.classic;
    }
  }

  // Advanced Audio Features

  Future<void> playSequentialSfx(
    List<String> soundIds, {
    Duration delay = const Duration(milliseconds: 200),
  }) async {
    for (final soundId in soundIds) {
      playSfx(soundId); // Fire and forget
      await Future.delayed(delay);
    }
  }

  void playRandomVariation(
    String baseSoundId, {
    int variations = 3,
    SpatialAudioPosition? position,
  }) {
    final random = math.Random();
    final variation = random.nextInt(variations) + 1;
    playSfx('${baseSoundId}_$variation', position: position);
  }

  Future<void> stopAll() async {
    await _stopAllInCategory(_sfxPlayers);
    await _stopAllInCategory(_musicPlayers);
    await _stopAllInCategory(_ambientPlayers);
    await _stopAllInCategory(_uiPlayers);
  }

  Future<void> stopMusic({Duration? fadeOutDuration}) async {
    for (final player in _musicPlayers.values) {
      if (player.state == PlayerState.playing) {
        if (fadeOutDuration != null) {
          final currentVolume = await _getCurrentVolume(player);
          await _fadeVolume(player, currentVolume, 0.0, fadeOutDuration);
        }
        await player.stop();
      }
    }
  }

  Future<double> _getCurrentVolume(AudioPlayer player) async {
    // This is a simplified implementation
    // In practice, you might need to track volume state
    return _musicVolume * _masterVolume;
  }

  void dispose() {
    for (final player in _sfxPlayers.values) {
      player.dispose();
    }
    for (final player in _musicPlayers.values) {
      player.dispose();
    }
    for (final player in _ambientPlayers.values) {
      player.dispose();
    }
    for (final player in _uiPlayers.values) {
      player.dispose();
    }
  }
}
