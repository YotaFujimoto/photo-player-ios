# 開発作業の約束

## 現在の範囲

段階0（環境・CI）と段階1（導入検証）のみ。開始時に `SPEC.md`、`STATUS.md`、`TESTING.md` を読む。
初回IPAの実機結果を受け取るまで上書き試験版を作らない。上書き後のデータ維持まで実機で合格し、次段階の指示を受けるまで動画プレイヤーを実装しない。

## 自律作業と保護事項

- この開発リポジトリの通常の編集、commit、push、CI実行、ログ解析、修正、成果物取得は継続して行う。人にコード作成・ビルド操作・CIログの中継を求めない。
- 公開範囲の変更、既存履歴の上書き、force push、有料ランナー、API課金、追加契約は行わない。標準 `xcode-27` のみを使用する。
- `DEVELOPMENT_PLAN.md` は本人用入力であり、Git管理・CI・公開成果物から除外する。公開文書に個人の端末情報、アカウント認証情報、ローカル絶対パス、私的な契約情報を転記しない。
- Apple Account、証明書、プロビジョニングプロファイル、個人動画、署名済みIPAを取得・公開しない。Appleの認証と署名は本人が端末導入時に行う。
- 固定Bundle ID `io.github.photoplayer.p6a936d329b934a8ba532081564a51c07` とUserDefaultsキー `manualCounter.v1` を更新時に変えない。データ消去処理を追加しない。
- 本人用計画は単一エージェントによる開発を指定している。同時編集のサブエージェントは使わない。

## 実装・検証・引き渡し

1. 必要な最小変更を行い、差分と公開対象を確認する。生成したXcodeプロジェクト、ログ、IPAはコミットしない。
2. `Config/Version.xcconfig` が版番号の正本。初回の修正中はビルド1を維持し、次の実機候補作成時に増やす。
3. push後、`gh run list --commit <SHA>` で対象CIを特定する。CIの `head_sha` と対象コミットを照合する。文書だけの変更はビルド対象外。
4. 失敗時は `gh run view <ID> --log-failed` を読み、根拠のある修正をして再実行する。同一原因で3回失敗したら原因分析を見直す。テスト削除・合格条件緩和で成功扱いにしない。
5. 成功後、`scripts/Get-Ipa.ps1 -RunId <ID> -Commit <完全SHA>` で `dist/PhotoPlayer.ipa` を取得する。成功状態、対象コミット、run attempt、SHA-256、Bundle ID、ビルド番号、iPhoneOS plist、Mach-OのiOS実機プラットフォームを照合してから配置する。
6. CIのテスト結果とスクリーンショットを確認する。シミュレーター試験の合格と実機での合格を区別する。
7. 停止時は `STATUS.md` に最後の成功コミット・CI・成果物・未確認事項・次の作業を残す。引き渡しはIPAの絶対パス、ビルド番号、最大5項目の実機確認手順。失敗時は項目番号と現象だけを求める。

## ビルド環境

- SwiftUI、iOS 17.0以上、iPhone優先、アプリ外部依存なし。
- Xcode 27.1 (`27A9275`)、`/Applications/Xcode_27.1.app/Contents/Developer` を固定。暗黙の既定XcodeやRC/betaへ切り替えない。
- XcodeGen 2.46.0、公式ZIPのSHA-256をCIに固定する。
- シミュレーターはRelease構成で1台だけテスト。実機アーカイブは `-sdk iphoneos -destination 'generic/platform=iOS'`。
- CIは署名無効。`xcodebuild -exportArchive` による署名フローを使わず、実機アーカイブ内のアプリを `Payload/PhotoPlayer.app` に格納する。
- WindowsにはSwift/Xcode/Pythonの導入を要求しない。`gh` がPATHにない場合は `Program Files/GitHub CLI/gh.exe` を使う。通信制限と認証失敗を混同しない。
- Actions成果物の保持は3日。実機合格したIPAはローカルの `dist/known-good/` に保管し、新候補で置き換えない。
