# 開発状況

更新日: 2026-11-07

## 現在地

段階0・1の初回導入版を作成・取得済み。**初回の実機確認待ち**。段階1全体はまだ未完了。
ビルド1、バージョン0.1.0。
固定Bundle ID: `io.github.photoplayer.p6a936d329b934a8ba532081564a51c07`。

SwiftUIの手動カウンター、UserDefaults保存、ビルド表示、XcodeGen設定、CI、取得検査スクリプトと公開文書を作成した。[公開リポジトリ](https://github.com/YotaFujimoto/photo-player-ios)へpush済み。本人用 `DEVELOPMENT_PLAN.md` はGit管理対象外で、公開側の一覧にも含まれないことを確認済み。

## 最後の成功

- 成功したビルドコミット: [`797b8d0b62591d1ec281f4ad34dc69013a44ba53`](https://github.com/YotaFujimoto/photo-player-ios/commit/797b8d0b62591d1ec281f4ad34dc69013a44ba53)。後続の文書だけのコミットはこのIPAのソースを変更しない。
- 成功CI: [run 42347702781](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42347702781)、attempt 1、2026-11-07。head SHAと成果物来歴を照合済み。
- 実行環境: 標準 `xcode-27`、image `20261104.0337.1`、Xcode 27.1 (`27A9275`)、XcodeGen 2.46.0。
- 自動検証: IPA検査器の4テストと、iPhone 17 / iOS 27.0のRelease UIテスト1件が成功。12への加算、バックグラウンド移行・終了・再起動後の12保持を確認。縦横の画面画像を目視確認済み。
- 実機用IPA: `dist/PhotoPlayer.ipa`、14,202 bytes、ビルド1。iOS 17.0以上。実機arm64、SDK `iphoneos27.1`、Release、未署名。CIとWindowsでplist・Mach-Oを検査済み（`LC_BUILD_VERSION platform=IOS`、署名なし）。
- SHA-256: `50634bf7d68d53acc1d5abd31aee34755008aa97f9963b0e0f86cbc26b167ab1`。
- 来歴: `dist/build-info.json`。成功CIログ・テスト結果・画面画像はローカル `build/evidence-42347702781/` と `build/success-42347702781.log` に取得済み。GitHub成果物の保持は3日。
- 実機合格版: まだなし。初回合格報告後にIPAと来歴を `dist/known-good/` へ保管する。

## 未確認事項

Sideloadlyでの端末認識・署名・導入、PCなし・機内モードでの起動、実機再起動時のカウンター保持、上書き更新時のデータ維持、再署名の運用。シミュレーターでの合格を実機の合格とは扱わない。

## 初回CIの調査

コミット `689dfe7a8822ac323c706ca633611844e636ac5a` の [run 42346620649](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42346620649) は試験ステップの長時間待機を調査するため中断。回収したログでは、起動と12までの加算後、iPhone Duoのホーム遷移で `.runningBackground` に到達せずテストが失敗していた。正常な `.runningBackgroundSuspended` も扱うよう変更し、再起動後の保存検証は維持する。

コミット `c57c790792e512289de79bbfd56d667ebfea4283` の [run 42347602362](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42347602362) でiPhone 17 / iOS 27.1を指定したところ該当機種が未登録で停止。取得した一覧を根拠に、存在する安定版iPhone 17 / iOS 27.0へ固定した。Xcodeは27.1、ビルド番号は1のまま。

## 次の作業

1. 本人が `TESTING.md` の初回確認票を実行し、ビルド1の結果を報告する。**ここで待つ。結果を受けるまで上書き試験版は作らない。**
2. 初回合格なら現在のIPA・来歴を実機正常版として保管。同じBundle ID・保存キー・保存方式のままビルド2を作り、CI・取得・最大5項目の上書き確認票まで進める。
3. 失敗なら削除・再インストールを求めず、その症状に対する導入／起動／保存の修正を優先する。
4. 上書き後のデータ保持まで実機で合格し、次段階の指示を受けるまで動画プレイヤー本体へ進まない。
