@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scglow/core/client_id_provider.dart';
import 'package:scglow/core/sc_api.dart';
import 'package:scglow/core/storage.dart';

void main() {
  test('client_id extraction and public stream resolve', () async {
    final client = http.Client();
    final ids = ClientIdProvider(client: client, store: MemoryKeyValueStore());
    final id = await ids.refresh();
    expect(id, matches(RegExp(r'^[a-zA-Z0-9]{32}$')));

    final api = ScApi(client: client, clientId: ids, readToken: () async => null);
    final track =
        await api.resolveUrl('https://soundcloud.com/forss/flickermood');
    expect(track.title, isNotEmpty);
    final stream = await api.resolveStream(track);
    expect(stream.url, contains('.m3u8'));

    final playlist = await client.get(Uri.parse(stream.url));
    expect(playlist.statusCode, 200);
    expect(playlist.body, startsWith('#EXTM3U'));
    // ignore: avoid_print
    print('client_id ok, stream ok: ${track.title}, '
        '${playlist.body.split('\n').where((l) => l.startsWith('#EXTINF')).length} segments');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
