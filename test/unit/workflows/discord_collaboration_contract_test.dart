import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;

  setUpAll(() {
    workflow = File('.github/workflows/discord-notify.yml').readAsStringSync();
  });

  test('next-owner label is the only PR handoff trigger', () {
    expect(workflow, contains('types: [labeled, closed]'));
    expect(workflow, isNot(contains('ready_for_review')));
    expect(workflow, isNot(contains('pull_request_review:')));
    expect(workflow, isNot(contains(r'$Pr.draft')));
  });

  test('next-owner labels ping the matching Discord owner', () {
    expect(
      workflow,
      contains(
        r"if ($Label -eq 'next:bruce') {"
        '\n'
        r'                    $MentionIds = @($env:DISCORD_BRUCE_USER_ID)',
      ),
    );
    expect(
      workflow,
      contains(
        r"} elseif ($Label -eq 'next:eric-ai') {"
        '\n'
        r'                    $MentionIds = @($env:DISCORD_ERIC_USER_ID)',
      ),
    );
    expect(
      workflow,
      contains(
        r"} elseif ($Label -eq 'next:discuss') {"
        '\n'
        r'                    $MentionIds = @($env:DISCORD_ERIC_USER_ID, $env:DISCORD_BRUCE_USER_ID)',
      ),
    );
  });

  test('required Flutter CI failure resolves the current owner', () {
    expect(
      workflow,
      contains(
        r"if ($Names -contains 'next:eric-ai') { return @($env:DISCORD_ERIC_USER_ID) }",
      ),
    );
    expect(
      workflow,
      contains(
        r"if ($Names -contains 'next:bruce') { return @($env:DISCORD_BRUCE_USER_ID) }",
      ),
    );
    expect(workflow, contains('必要 CI 失敗'));
  });
}
