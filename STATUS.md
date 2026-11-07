# 開発状況

更新日: 2026-11-07

## 現在地

ビルド1の初回実機確認は全項目合格、保存値12（2026-11-07の本人報告）。**ビルド2の上書き試験版を作成・取得済み。実機の上書き結果待ち**。上書き確認が終わるまで段階1全体は未完了。
バージョン0.1.0。アプリの変更はビルド番号1→2のみ。
固定Bundle ID: `io.github.photoplayer.p6a936d329b934a8ba532081564a51c07`。

SwiftUIの手動カウンター、UserDefaults保存、ビルド表示、XcodeGen設定、CI、取得検査スクリプトと公開文書を作成した。[公開リポジトリ](https://github.com/YotaFujimoto/photo-player-ios)へpush済み。本人用 `DEVELOPMENT_PLAN.md` はGit管理対象外で、公開側の一覧にも含まれないことを確認済み。

## 最後の成功

- 成功したビルドコミット: [`003a6d73620230685e6f7509fa3a894d189d8355`](https://github.com/YotaFujimoto/photo-player-ios/commit/003a6d73620230685e6f7509fa3a894d189d8355)。後続の文書だけのコミットはこのIPAのソースを変更しない。
- 成功CI: [run 42350896546](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42350896546)、attempt 1、2026-11-07。head SHAと成果物来歴を照合済み。
- 実行環境: 標準 `xcode-27`、image `20261104.0337.1`、Xcode 27.1 (`27A9275`)、XcodeGen 2.46.0。
- 自動検証: IPA検査器の4テストと、iPhone 17 / iOS 27.0のRelease UIテスト1件が成功。ビルド2での12への加算、バックグラウンド移行・終了・再起動後の12保持を確認。縦横の画面画像を目視確認済み。実機上書きの代わりにはしない。
- 実機用IPA: `dist/PhotoPlayer.ipa`、14,203 bytes、**ビルド2**。iOS 17.0以上。実機arm64、SDK `iphoneos27.1`、Release、未署名。CIとWindowsでplist・Mach-Oを検査済み（`LC_BUILD_VERSION platform=IOS`、署名なし）。
- SHA-256: `1b3ba0aba813b83b262d9ffae0e0325191e88ff6ed36baf623a264cbc2550ae0`。
- 来歴: `dist/build-info.json`。成功CIログ・テスト結果・画面画像はローカル `build/evidence-42350896546/` と `build/success-42350896546.log` に取得済み。GitHub成果物の保持は3日。
- 実機合格版: **ビルド1**（コミット `797b8d0b62591d1ec281f4ad34dc69013a44ba53`、[run 42347702781](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42347702781)）。署名・初回導入、アプリ終了・再起動後の12保持、PCなし・機内モード（Wi-Fiオフ）での起動と12保持に合格（本人報告）。IPA・来歴・確認結果を `dist/known-good/build-1/` に保管。元のSHA-256 `50634bf7d68d53acc1d5abd31aee34755008aa97f9963b0e0f86cbc26b167ab1` と一致することを再確認済み。

## 未確認事項

ビルド2への実機上書き更新時の保存値12の維持、更新後の実機オフライン起動、再署名の運用。シミュレーターでの合格を実機上書きの合格とは扱わない。

## 初回CIの調査

コミット `689dfe7a8822ac323c706ca633611844e636ac5a` の [run 42346620649](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42346620649) は試験ステップの長時間待機を調査するため中断。回収したログでは、起動と12までの加算後、iPhone Duoのホーム遷移で `.runningBackground` に到達せずテストが失敗していた。正常な `.runningBackgroundSuspended` も扱うよう変更し、再起動後の保存検証は維持する。

コミット `c57c790792e512289de79bbfd56d667ebfea4283` の [run 42347602362](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42347602362) でiPhone 17 / iOS 27.1を指定したところ該当機種が未登録で停止。取得した一覧を根拠に、存在する安定版iPhone 17 / iOS 27.0へ固定した。Xcodeは27.1、ビルド番号は1のまま。

## ビルド2のCI調査

[run 42350093139](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42350093139)、コミット `e0819f29473570fda61bde3cacdfb923154d7da5` はUIテストの背景状態確認で失敗。回収したXCTest診断ログでは、背景状態の1秒待機が終了した後、一時停止状態を待っている間に実際の状態が背景へ変わり、誤って失敗していた。正常な背景／一時停止のどちらかを単一の述語で同時に待つよう修正し、終了・再起動後の値保持の検証は維持した。失敗時にも画面画像を取得できるようにした。アプリ本体・Bundle ID・保存方式は変更していない。

## 次の作業

1. 本人が `TESTING.md` のビルド2上書き確認票を実施する。アプリを削除せず、初回と同じ署名アカウント・実際のBundle ID・設定で上書きし、ビルド2・値12を確認する。**ここで実機結果を待つ。**
2. 合格報告後はビルド2のIPA・来歴・実機結果も `dist/known-good/build-2/` へ保管し、段階1の合格を記録する。ビルド1の保管は維持する。
3. 失敗なら削除・再インストールを求めず、その症状に対する更新／起動／保存の修正を優先する。
4. 上書き後のデータ保持まで実機で合格し、次段階の指示を受けるまで動画プレイヤー本体へ進まない。
