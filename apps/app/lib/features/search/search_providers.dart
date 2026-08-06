import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

final searchChannelsProvider = Provider<SearchChannels>((ref) {
  return SearchChannels(ref.watch(channelSearchPortProvider));
});
