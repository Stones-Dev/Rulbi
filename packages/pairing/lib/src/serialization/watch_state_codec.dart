import 'package:iptv_core/iptv_core.dart';

import 'channel_ref_codec.dart';

extension WatchStateCodec on WatchState {
  Map<String, Object?> toJson() => {
    'channel': channel.toJson(),
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'updatedAt': updatedAt.toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
  };
}

WatchState watchStateFromJson(Map<String, Object?> json) => WatchState(
  channel: channelRefFromJson(json['channel'] as Map<String, Object?>),
  position: Duration(milliseconds: json['positionMs'] as int? ?? 0),
  duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
);
