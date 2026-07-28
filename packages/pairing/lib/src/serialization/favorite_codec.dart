import 'package:iptv_core/iptv_core.dart';

import 'channel_ref_codec.dart';

extension FavoriteCodec on Favorite {
  Map<String, Object?> toJson() => {
    'channel': channel.toJson(),
    'order': order,
    'updatedAt': updatedAt.toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
  };
}

Favorite favoriteFromJson(Map<String, Object?> json) => Favorite(
  channel: channelRefFromJson(json['channel'] as Map<String, Object?>),
  order: json['order'] as int? ?? 0,
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
);
