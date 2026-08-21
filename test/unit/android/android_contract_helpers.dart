// test/unit/android/android_contract_helpers.dart
// Slice 2 Android 契約靜態測試共用工具（依領域拆分：launcher／
// auth_callback／signing／backup／ci_workflow）。
// manifest／backup XML 用 package:xml、workflow 用 package:yaml 做結構化
// 解析，不對整段原文做字串切片。Gradle kts 與 shell 腳本沒有結構化解析器，
// 維持關鍵字對帳；其動態行為由 CI 的 SEC-01／AND-02 gate、
// signing-gate-negative-check.sh 與 install smoke 提供可執行證據。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

const kAndroidPackage = 'com.vibesync.app';

/// AND-03 凍結契約唯一真相源
class AuthCallbackContract {
  AuthCallbackContract._(this.scheme, this.host, this.callbackActivity);

  factory AuthCallbackContract.load() {
    final json = jsonDecode(readRepoFile('contracts/auth-callback.json'))
        as Map<String, dynamic>;
    return AuthCallbackContract._(
      json['scheme'] as String,
      json['host'] as String,
      json['androidCallbackActivity'] as String,
    );
  }

  final String scheme;
  final String host;
  final String callbackActivity;

  String get uri => '$scheme://$host';
}

// 缺檔直接丟 FileSystemException（訊息含路徑）
String readRepoFile(String path) => File(path).readAsStringSync();

XmlDocument loadAndroidManifest() =>
    XmlDocument.parse(readRepoFile('android/app/src/main/AndroidManifest.xml'));

// ---------- XML helpers ----------

String? androidAttr(XmlElement e, String name) =>
    e.getAttribute('android:$name');

XmlElement applicationElement(XmlDocument manifest) =>
    manifest.rootElement.findElements('application').single;

List<XmlElement> manifestActivities(XmlDocument manifest) =>
    applicationElement(manifest).findElements('activity').toList();

XmlElement activityByName(XmlDocument manifest, String name) {
  final matches = manifestActivities(manifest)
      .where((a) => androidAttr(a, 'name') == name)
      .toList();
  expect(matches, hasLength(1), reason: '應恰有一個 $name activity');
  return matches.first;
}

bool hasCategory(XmlElement filter, String category) =>
    filter.findElements('category').any((c) => androidAttr(c, 'name') == category);

/// activity 內所有宣告 [scheme] 的 intent-filter data host
Set<String> schemeHosts(XmlElement activity, String scheme) => activity
    .findElements('intent-filter')
    .expand((f) => f.findElements('data'))
    .where((d) => androidAttr(d, 'scheme') == scheme)
    .map((d) => androidAttr(d, 'host') ?? '')
    .toSet();

Set<String> excludedDomains(XmlElement parent) => parent
    .findElements('exclude')
    .where((e) => e.getAttribute('path') == '.')
    .map((e) => e.getAttribute('domain') ?? '')
    .toSet();

// ---------- YAML helpers ----------

YamlMap loadWorkflow(String path) => loadYaml(readRepoFile(path)) as YamlMap;

YamlMap workflowJob(YamlMap workflow, String id) {
  final job = (workflow['jobs'] as YamlMap)[id];
  expect(job, isNotNull, reason: '找不到 job $id');
  return job as YamlMap;
}

List<YamlMap> jobSteps(YamlMap workflow, String id) =>
    (workflowJob(workflow, id)['steps'] as YamlList).cast<YamlMap>().toList();

String stepRun(YamlMap step) => (step['run'] ?? '').toString();

/// job 子樹內所有 scalar（key 與 value），供禁用字串掃描
Iterable<String> yamlScalars(Object? node) sync* {
  if (node is YamlMap) {
    for (final entry in node.entries) {
      yield entry.key.toString();
      yield* yamlScalars(entry.value);
    }
  } else if (node is YamlList) {
    for (final item in node) {
      yield* yamlScalars(item);
    }
  } else if (node != null) {
    yield node.toString();
  }
}

List<String> jobNeeds(YamlMap job) {
  final needs = job['needs'];
  if (needs == null) return const [];
  if (needs is YamlList) return needs.map((n) => n.toString()).toList();
  return [needs.toString()];
}
