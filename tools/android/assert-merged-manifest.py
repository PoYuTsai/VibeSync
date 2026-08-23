#!/usr/bin/env python3
"""merged release manifest 語意守門（AND-03／AUTH-01）。

真合併後 manifest 的語意斷言（不只留檔），凍結值以
contracts/auth-callback.json 與 contracts/email-auth-callback.json 為各自
URI 的唯一真相源：
  1. OAuth 凍結 URI 唯一擁有者是 flutter_web_auth_2 的 CallbackActivity
     「activity」；Email 凍結 URI 唯一擁有者是 MainActivity。兩者都把
     activity-alias 視為候選擁有者，出現即擋。
  2. 兩個 callback 的 data 規則都必須恰為 scheme＋host，且不得帶任何
     額外 URI 限制屬性（port、path、pathPrefix、pathPattern、
     pathAdvancedPattern、pathSuffix、mimeType…）——多一個屬性就會
     窄化比對讓真 callback 掉到別的 handler，一律 fail closed。
  3. MAIN/LAUNCHER 唯一且是 MainActivity activity（alias 持有也擋）。
  4. 不得出現任何自訂 dispatcher／第二個 auth callback 元件。

用法：assert-merged-manifest.py <merged-AndroidManifest.xml>
"""
import json
import os
import sys
# 輸入只會是本 repo CI 自己 build 出的 merged manifest（信任邊界內），
# 不收外部 XML，stdlib ElementTree 即可，不為此加 defusedxml 依賴。
import xml.etree.ElementTree as ET

A = '{http://schemas.android.com/apk/res/android}'
_contract = json.load(open(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '..',
    'contracts', 'auth-callback.json')))
SCHEME, HOST = _contract['scheme'], _contract['host']
CALLBACK = _contract['androidCallbackActivity']
_email_contract = json.load(open(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '..',
    'contracts', 'email-auth-callback.json')))
EMAIL_SCHEME = _email_contract['scheme']
EMAIL_HOST = _email_contract['host']
EMAIL_CALLBACK = _email_contract['androidCallbackActivity']
MAIN = EMAIL_CALLBACK
# data 元素只允許這兩個屬性；其餘一律視為未預期的 URI 限制
ALLOWED_DATA_ATTRS = {A + 'scheme', A + 'host'}


def main(path):
    app = ET.parse(path).getroot().find('application')
    # VIEW owner／launcher 的候選是 activity「與」activity-alias
    comps = [c for c in app if c.tag in ('activity', 'activity-alias')]

    def host_may_match(pattern, expected):
        """Conservatively model Android's leading-* host matching."""
        return (pattern == expected or
                (pattern.startswith('*') and
                 expected.endswith(pattern[1:])))

    def filter_may_match(filter_element, scheme, host):
        """Conservatively model Android's merged <data> matching.

        Multiple <data> elements and attributes in one intent-filter are
        combined by Android. A scheme-only or host-only declaration can
        therefore still claim a callback, as can a split scheme/host pair.
        Treat every such candidate as an owner so a chooser cannot be hidden
        by a too-narrow exact-pair scan.
        """
        data = filter_element.findall('data')
        schemes = {d.get(A + 'scheme') for d in data
                   if d.get(A + 'scheme') is not None}
        hosts = {d.get(A + 'host') for d in data
                 if d.get(A + 'host') is not None}
        host_matches = any(host_may_match(pattern, host) for pattern in hosts)
        return ((scheme in schemes and (not hosts or host_matches)) or
                (host_matches and (not schemes or scheme in schemes)))

    def matching_filters(c, scheme, host):
        return [f for f in c.findall('intent-filter')
                if filter_may_match(f, scheme, host)]

    def assert_filter_contract(filters, scheme, host, label):
        assert len(filters) == 1, (
            f'{label} intent-filter 必須恰一個，得到 {len(filters)}')
        filter_element = filters[0]
        datas = filter_element.findall('data')
        pairs = {(d.get(A + 'scheme'), d.get(A + 'host')) for d in datas}
        assert pairs == {(scheme, host)}, (
            f'{label} data 必須恰為 {scheme}://{host}，得到 {pairs}')
        for d in datas:
            extra = sorted(k.replace(A, 'android:') for k in d.keys()
                           if k not in ALLOWED_DATA_ATTRS)
            assert not extra, (
                f'{label} data 不得帶額外 URI 限制屬性，得到 {extra}')
        actions = {x.get(A + 'name') for x in filter_element.findall('action')}
        assert 'android.intent.action.VIEW' in actions, (
            f'{label} 缺 VIEW action：{actions}')
        cats = {c.get(A + 'name') for c in filter_element.findall('category')}
        assert {'android.intent.category.DEFAULT',
                'android.intent.category.BROWSABLE'} <= cats, (
            f'{label} 缺 DEFAULT/BROWSABLE category：{cats}')
        return filter_element

    # A contract host may never be declared under a different scheme. This
    # catches an early/incorrect callback filter before Android can resolve it.
    for component in comps:
        for filter_element in component.findall('intent-filter'):
            data = filter_element.findall('data')
            schemes = {d.get(A + 'scheme') for d in data
                       if d.get(A + 'scheme') is not None}
            hosts = {d.get(A + 'host') for d in data
                     if d.get(A + 'host') is not None}
            if any(host_may_match(pattern, HOST) for pattern in hosts) and \
                    schemes and SCHEME not in schemes:
                raise AssertionError(
                    f'OAuth host {HOST} 不得搭配錯誤 scheme')
            if any(host_may_match(pattern, EMAIL_HOST) for pattern in hosts) and \
                    schemes and EMAIL_SCHEME not in schemes:
                raise AssertionError(
                    f'Email host {EMAIL_HOST} 不得搭配錯誤 scheme')

    owners = [(c.tag, c.get(A + 'name')) for c in comps
              if matching_filters(c, SCHEME, HOST)]
    assert owners == [('activity', CALLBACK)], \
        f'OAuth URI 擁有者必須唯一且是 {CALLBACK}（alias 也不行），得到 {owners}'

    cb = next(c for c in comps if c.get(A + 'name') == CALLBACK)
    assert cb.get(A + 'exported') == 'true', \
        'CallbackActivity 必須 exported=true（瀏覽器要能開）'
    assert_filter_contract(
        matching_filters(cb, SCHEME, HOST), SCHEME, HOST,
        'OAuth callback')

    email_owners = [(c.tag, c.get(A + 'name')) for c in comps
                    if matching_filters(c, EMAIL_SCHEME, EMAIL_HOST)]
    assert email_owners == [('activity', EMAIL_CALLBACK)], \
        f'Email URI 擁有者必須唯一且是 {EMAIL_CALLBACK}（alias 也不行），得到 {email_owners}'
    email_activity = next(c for c in comps if c.get(A + 'name') == EMAIL_CALLBACK)
    assert email_activity.get(A + 'exported') == 'true', \
        'MainActivity 必須 exported=true（Email link 要能開）'
    assert_filter_contract(
        matching_filters(email_activity, EMAIL_SCHEME, EMAIL_HOST),
        EMAIL_SCHEME,
        EMAIL_HOST,
        'Email callback',
    )

    dispatchers = [c.get(A + 'name') for c in comps
                   if 'Dispatcher' in (c.get(A + 'name') or '')]
    assert not dispatchers, \
        f'不得出現自訂 dispatcher 元件（Frozen Spec 指定 plugin CallbackActivity）：{dispatchers}'

    launchers = [(c.tag, c.get(A + 'name')) for c in comps
                 for lf in c.findall('intent-filter')
                 if any(x.get(A + 'name') == 'android.intent.category.LAUNCHER'
                        for x in lf.findall('category'))
                 and any(x.get(A + 'name') == 'android.intent.action.MAIN'
                         for x in lf.findall('action'))]
    assert launchers == [('activity', MAIN)], \
        f'MAIN/LAUNCHER 必須唯一且是 MainActivity activity（alias 也不行），得到 {launchers}'
    print('merged manifest 語意斷言 OK：OAuth 唯一 CallbackActivity owner、'
          'Email 唯一 MainActivity owner（皆 exported、exact scheme/host、'
          '無額外 URI 限制、VIEW、DEFAULT＋BROWSABLE，含 alias 掃描）、'
          '無自訂 dispatcher、唯一 MAIN/LAUNCHER=MainActivity')


if __name__ == '__main__':
    main(sys.argv[1])
