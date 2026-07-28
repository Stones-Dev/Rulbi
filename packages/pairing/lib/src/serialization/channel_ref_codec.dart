import 'package:iptv_core/iptv_core.dart';

extension ChannelRefCodec on ChannelRef {
  Map<String, Object?> toJson() => {'source': sourceId, 'key': key};
}

ChannelRef channelRefFromJson(Map<String, Object?> json) => ChannelRef(
      sourceId: json['source'] as String,
      key: json['key'] as String,
    );
