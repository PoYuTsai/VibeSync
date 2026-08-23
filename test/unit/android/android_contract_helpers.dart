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
class _CallbackContractBase {
  const _CallbackContractBase({
    required this.scheme,
    required this.host,
    required this.callbackActivity,
  });

  factory _CallbackContractBase.fromJson(Map<String, dynamic> json) {
    return _CallbackContractBase(
      scheme: json['scheme'] as String,
      host: json['host'] as String,
      callbackActivity: json['androidCallbackActivity'] as String,
    );
  }

  final String scheme;
  final String host;
  final String callbackActivity;

  String get uri => '$scheme://$host';
}

class AuthCallbackContract {
  AuthCallbackContract._(
    this._base,
    this.supabaseAllowlistEntry,
  );

  factory AuthCallbackContract.load() {
    final json = jsonDecode(readRepoFile('contracts/auth-callback.json'))
        as Map<String, dynamic>;
    return AuthCallbackContract._(
      _CallbackContractBase.fromJson(json),
      json['supabaseRedirectAllowlistEntry'] as String,
    );
  }

  final _CallbackContractBase _base;
  final String supabaseAllowlistEntry;

  String get scheme => _base.scheme;
  String get host => _base.host;
  String get callbackActivity => _base.callbackActivity;
  String get uri => _base.uri;
}

/// AUTH-01 Email deep-link contract. Kept separate from the frozen OAuth
/// contract because the two callbacks deliberately have different Android
/// activity owners.
class EmailAuthCallbackContract {
  EmailAuthCallbackContract._(
    this._base,
    this.purposes,
    this.markerParameter,
    this.markerValues,
    this.supabaseAllowlistEntries,
  );

  factory EmailAuthCallbackContract.load() {
    final json = jsonDecode(
      readRepoFile('contracts/email-auth-callback.json'),
    ) as Map<String, dynamic>;
    return EmailAuthCallbackContract._(
      _CallbackContractBase.fromJson(json),
      (json['purposes'] as List<dynamic>).cast<String>(),
      (json['flowMarker']['parameter'] as String),
      (json['flowMarker']['values'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      ),
      (json['supabaseRedirectAllowlistEntries'] as List<dynamic>)
          .cast<String>(),
    );
  }

  final _CallbackContractBase _base;
  final List<String> purposes;
  final String markerParameter;
  final Map<String, String> markerValues;
  final List<String> supabaseAllowlistEntries;

  String get scheme => _base.scheme;
  String get host => _base.host;
  String get callbackActivity => _base.callbackActivity;
  String get supabaseAllowlistEntry => _base.uri;
  String get uri => _base.uri;
}

/// supabase/config.toml 的 additional_redirect_urls 陣列原始內容
/// （最小 TOML 擷取：只取該賦值的 [ … ] 區塊，夠契約對帳用）
String supabaseAdditionalRedirectUrlsBlock() {
  final config = readRepoFile('supabase/config.toml');
  final match = RegExp(
    r'additional_redirect_urls\s*=\s*\[(.*?)\]',
    dotAll: true,
  ).firstMatch(config);
  expect(match, isNotNull,
      reason: 'supabase/config.toml 找不到 additional_redirect_urls');
  return match!.group(1)!;
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

bool hasCategory(XmlElement filter, String category) => filter
    .findElements('category')
    .any((c) => androidAttr(c, 'name') == category);

/// activity 內所有宣告 [scheme] 的 intent-filter data host
Set<String> schemeHosts(XmlElement activity, String scheme) => activity
    .findElements('intent-filter')
    .expand((f) => f.findElements('data'))
    .where((d) => androidAttr(d, 'scheme') == scheme)
    .map((d) => androidAttr(d, 'host') ?? '')
    .toSet();

bool callbackFilterMayMatch(
  XmlElement filter, {
  required String scheme,
  required String host,
}) {
  final data = filter.findElements('data').toList();
  final schemes =
      data.map((d) => androidAttr(d, 'scheme')).whereType<String>().toSet();
  final hosts =
      data.map((d) => androidAttr(d, 'host')).whereType<String>().toSet();
  bool hostMayMatch(String pattern) {
    if (pattern == host) return true;
    if (!pattern.startsWith('*')) return false;
    return host.endsWith(pattern.substring(1));
  }

  final hostMatches = hosts.any(hostMayMatch);

  return (schemes.contains(scheme) && (hosts.isEmpty || hostMatches)) ||
      (hostMatches && (schemes.isEmpty || schemes.contains(scheme)));
}

List<XmlElement> matchingCallbackFilters(
  XmlElement component, {
  required String scheme,
  required String host,
}) =>
    component
        .findElements('intent-filter')
        .where(
          (filter) => callbackFilterMayMatch(
            filter,
            scheme: scheme,
            host: host,
          ),
        )
        .toList();

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
