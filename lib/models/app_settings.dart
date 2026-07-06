import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 4)
@JsonSerializable()
class AppSettings {
  @HiveField(0)
  final String themeMode;
  
  @HiveField(1)
  final bool notificationsEnabled;
  
  @HiveField(2)
  final bool soundEnabled;
  
  @HiveField(3)
  final bool vibrationEnabled;
  
  @HiveField(4)
  final DateTime lastUpdated;
  
  AppSettings({
    this.themeMode = 'system',
    this.notificationsEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    required this.lastUpdated,
  });
  
  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
  
  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);
  
  AppSettings copyWith({
    String? themeMode,
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    DateTime? lastUpdated,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
  
  static AppSettings createDefault() {
    return AppSettings(
      lastUpdated: DateTime.now(),
    );
  }
}
