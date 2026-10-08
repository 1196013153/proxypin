import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/config_backup.dart';

void main() {
  late Directory tempHome;
  late Directory tempTarget;

  setUp(() async {
    tempHome = await Directory.systemTemp.createTemp('proxypin_backup_src');
    tempTarget = await Directory.systemTemp.createTemp('proxypin_backup_dst');
  });

  tearDown(() async {
    await tempHome.delete(recursive: true);
    await tempTarget.delete(recursive: true);
  });

  test('export collects config files and rule attachment dirs', () async {
    File('${tempHome.path}/hosts.json').writeAsStringSync('[{"host":"a.com"}]');
    File('${tempHome.path}/report_servers.json').writeAsStringSync('[]');
    final scriptDir = Directory('${tempHome.path}/scripts');
    scriptDir.createSync();
    File('${scriptDir.path}/abc.js').writeAsStringSync('console.log(1)');
    // 不应被打包的文件
    File('${tempHome.path}/histories.json').writeAsStringSync('[]');

    final bundle = await ConfigBackup.exportFromDir(tempHome.path);

    expect(bundle['app'], ConfigBackup.bundleType);
    expect((bundle['files'] as Map).containsKey('hosts.json'), isTrue);
    expect((bundle['files'] as Map).containsKey('histories.json'), isFalse);
    final dirs = bundle['dirs'] as Map;
    expect(dirs['scripts']['scripts/abc.js'], 'console.log(1)');
  });

  test('import restores files, round trip preserves content', () async {
    File('${tempHome.path}/hosts.json').writeAsStringSync('[{"host":"a.com"}]');
    final rewriteDir = Directory('${tempHome.path}/rewrite');
    rewriteDir.createSync();
    File('${rewriteDir.path}/rule1.json').writeAsStringSync('{"op":"updateBody"}');

    final json = jsonEncode(await ConfigBackup.exportFromDir(tempHome.path));
    final count = await ConfigBackup.importData(jsonDecode(json), tempTarget.path);

    expect(count, 2);
    expect(File('${tempTarget.path}/hosts.json').readAsStringSync(), '[{"host":"a.com"}]');
    expect(File('${tempTarget.path}/rewrite/rule1.json').readAsStringSync(), '{"op":"updateBody"}');
  });

  test('importFromJson rejects foreign bundles', () async {
    expect(() => ConfigBackup.importFromJson('{"app":"something-else"}'), throwsFormatException);
    expect(() => ConfigBackup.importFromJson('not json'), throwsFormatException);
  });

  test('importData skips path traversal and unknown entries', () async {
    final bundle = {
      'app': ConfigBackup.bundleType,
      'version': 1,
      'files': {
        'hosts.json': 'ok',
        '../evil.json': 'evil',
        '/abs/path.json': 'evil',
        'unknown_config.json': 'skipped',
      },
      'dirs': {
        'scripts': {
          'scripts/a.js': 'ok',
          'scripts/../../evil.js': 'evil',
          'outside/b.js': 'skipped',
        },
        'not_allowed_dir': {'x.txt': 'skipped'},
      },
    };

    final count = await ConfigBackup.importData(bundle, tempTarget.path);

    expect(count, 2);
    expect(File('${tempTarget.path}/hosts.json').existsSync(), isTrue);
    expect(File('${tempTarget.path}/../evil.json').existsSync(), isFalse);
    expect(File('${tempTarget.path}/unknown_config.json').existsSync(), isFalse);
    expect(File('${tempTarget.path}/scripts/a.js').existsSync(), isTrue);
  });
}
