/// Configuration model for the background scheduler.
class BackgroundConfig {
  /// The exact hardware alarm interval in minutes. Minimum is 1. Default is 15.
  final int intervalMinutes;

  const BackgroundConfig({this.intervalMinutes = 15});

  Map<String, dynamic> toJson() => {'intervalMinutes': intervalMinutes};

  factory BackgroundConfig.fromJson(Map<String, dynamic> json) =>
      BackgroundConfig(intervalMinutes: json['intervalMinutes'] ?? 15);
}
