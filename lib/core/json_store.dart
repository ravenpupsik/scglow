import 'dart:convert';
import 'dart:io';

abstract class JsonStore {
  Future<Map<String, dynamic>?> read(String name);
  Future<void> write(String name, Map<String, dynamic> data);
  Future<void> delete(String name);
}

class FileJsonStore implements JsonStore {
  FileJsonStore(this.dir);

  final Directory dir;

  File _file(String name) => File('${dir.path}${Platform.pathSeparator}$name.json');

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    try {
      final f = _file(name);
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString());
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String name, Map<String, dynamic> data) async {
    await dir.create(recursive: true);
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String name) async {
    try {
      await _file(name).delete();
    } catch (_) {}
  }
}

class MemoryJsonStore implements JsonStore {
  final Map<String, String> data = {};

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    final s = data[name];
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String name, Map<String, dynamic> value) async =>
      data[name] = jsonEncode(value);

  @override
  Future<void> delete(String name) async => data.remove(name);
}
