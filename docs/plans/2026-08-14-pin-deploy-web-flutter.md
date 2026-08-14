# Pin deploy-web Flutter

## Outcome

Make the web deployment workflow use the same exact Flutter version as every other Flutter workflow, so a future `stable` channel update cannot silently break or change the production web build.

## Changes

1. Add `flutter-version: 3.47.0` to `.github/workflows/deploy-web.yml` while retaining `channel: stable` and the existing action digest.
2. Add `.github/workflows/deploy-web.yml` as an exact Flutter pin source in `.agent/environment.json`, so the environment doctor rejects drift across all four workflows.
3. Do not change triggers, credentials, build commands, deployment commands, or any product/runtime code.

## Verification

- Parse and validate the environment contract.
- Run the environment doctor on the WSL artifact owner and confirm all four pin sources resolve to Flutter 3.47.0.
- Statically verify every `subosito/flutter-action` setup in the four workflows carries the exact pin.
- Run `git diff --check`, commit only the plan, workflow, and contract, bind security-harness evidence, and request Fable 5 read-only review.

## Delivery boundary

This is a local candidate only. Do not push, deploy, merge, install, globally apply the environment control plane, or move the repository.
