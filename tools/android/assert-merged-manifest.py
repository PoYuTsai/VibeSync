#!/usr/bin/env python3
"""merged release manifest 語意守門（Round1 P2）。

真合併後 manifest 的語意斷言（不只留檔）：
  1. 凍結 scheme 唯一擁有者是 dispatcher「activity」——activity-alias
     也算候選擁有者，出現即擋（alias 可被 merge 帶進來搶深連結）。
  2. dispatcher 的 data 規則必須恰為 scheme＋host，且不得帶任何額外
     URI 限制屬性（port、path、pathPrefix、pathPattern、
     pathAdvancedPattern、pathSuffix、mimeType…）——多一個屬性就會
     窄化比對讓真 callback 掉到別的 handler，一律 fail closed。
  3. plugin CallbackActivity 不得被 manifest merge 帶回來。
  4. MAIN/LAUNCHER 唯一且是 MainActivity activity（alias 持有也擋）。

用法：assert-merged-manifest.py <merged-AndroidManifest.xml>
"""
import sys
# 輸入只會是本 repo CI 自己 build 出的 merged manifest（信任邊界內），
# 不收外部 XML，stdlib ElementTree 即可，不為此加 defusedxml 依賴。
import xml.etree.ElementTree as ET

A = '{http://schemas.android.com/apk/res/android}'
SCHEME, HOST = 'com.poyutsai.vibesync', 'login-callback'
DISPATCHER = 'com.vibesync.app.AuthCallbackDispatcherActivity'
MAIN = 'com.vibesync.app.MainActivity'
# data 元素只允許這兩個屬性；其餘一律視為未預期的 URI 限制
ALLOWED_DATA_ATTRS = {A + 'scheme', A + 'host'}


def main(path):
    app = ET.parse(path).getroot().find('application')
    # VIEW owner／launcher 的候選是 activity「與」activity-alias
    comps = [c for c in app if c.tag in ('activity', 'activity-alias')]

    def scheme_filters(c):
        return [f for f in c.findall('intent-filter') if any(
            d.get(A + 'scheme') == SCHEME for d in f.findall('data'))]

    owners = [(c.tag, c.get(A + 'name')) for c in comps if scheme_filters(c)]
    assert owners == [('activity', DISPATCHER)], \
        f'凍結 scheme 擁有者必須唯一且是 dispatcher activity（alias 也不行），得到 {owners}'

    disp = next(c for c in comps if c.get(A + 'name') == DISPATCHER)
    assert disp.get(A + 'exported') == 'true', \
        'dispatcher 必須 exported=true（瀏覽器／郵件 App 要能開）'
    fs = scheme_filters(disp)
    assert len(fs) == 1, f'凍結 scheme intent-filter 必須恰一個，得到 {len(fs)}'
    f = fs[0]
    datas = f.findall('data')
    pairs = {(d.get(A + 'scheme'), d.get(A + 'host')) for d in datas}
    assert pairs == {(SCHEME, HOST)}, \
        f'data 必須恰為 {SCHEME}://{HOST}，得到 {pairs}'
    for d in datas:
        extra = sorted(k.replace(A, 'android:') for k in d.keys()
                       if k not in ALLOWED_DATA_ATTRS)
        assert not extra, \
            f'data 不得帶額外 URI 限制屬性（會窄化深連結比對），得到 {extra}'
    actions = {x.get(A + 'name') for x in f.findall('action')}
    assert 'android.intent.action.VIEW' in actions, f'缺 VIEW action：{actions}'
    cats = {c.get(A + 'name') for c in f.findall('category')}
    assert {'android.intent.category.DEFAULT',
            'android.intent.category.BROWSABLE'} <= cats, \
        f'缺 DEFAULT/BROWSABLE category：{cats}'

    plugin = [c.get(A + 'name') for c in comps
              if 'flutter_web_auth_2' in (c.get(A + 'name') or '')]
    assert not plugin, f'plugin CallbackActivity 不得出現在 merged manifest：{plugin}'

    launchers = [(c.tag, c.get(A + 'name')) for c in comps
                 for lf in c.findall('intent-filter')
                 if any(x.get(A + 'name') == 'android.intent.category.LAUNCHER'
                        for x in lf.findall('category'))
                 and any(x.get(A + 'name') == 'android.intent.action.MAIN'
                         for x in lf.findall('action'))]
    assert launchers == [('activity', MAIN)], \
        f'MAIN/LAUNCHER 必須唯一且是 MainActivity activity（alias 也不行），得到 {launchers}'
    print('merged manifest 語意斷言 OK：唯一 dispatcher（exported、exact '
          'scheme/host、無額外 URI 限制、VIEW、DEFAULT＋BROWSABLE，含 '
          'alias 掃描）、無 plugin CallbackActivity、唯一 MAIN/LAUNCHER='
          'MainActivity')


if __name__ == '__main__':
    main(sys.argv[1])
