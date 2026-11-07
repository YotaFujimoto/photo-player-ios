# 開発状況

更新日: 2026-11-07

## 現在地

段階0・1の初回導入版を実装中。ビルド1、バージョン0.1.0。
固定Bundle ID: `io.github.photoplayer.p6a936d329b934a8ba532081564a51c07`。

SwiftUIの手動カウンター、UserDefaults保存、ビルド表示、XcodeGen設定、CI、取得検査スクリプトと公開文書を作成した。本人用 `DEVELOPMENT_PLAN.md` はGit管理対象外。

## 最後の成功

- 成功したビルドコミット: まだなし。
- 成功CI: まだなし。
- 実機用IPA: まだなし。
- 実機合格版: まだなし。

## 未確認事項

CIの初回実行、実機署名・導入、PCなし・機内モードでの起動、再起動時のカウンター保持、上書き更新時のデータ維持。

## 初回CIの調査

コミット `689dfe7a8822ac323c706ca633611844e636ac5a` の [run 42346620649](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42346620649) は試験ステップの長時間待機を調査するため中断。回収したログでは、起動と12までの加算後、iPhone Duoのホーム遷移で `.runningBackground` に到達せずテストが失敗していた。正常な `.runningBackgroundSuspended` も扱うよう変更し、再起動後の保存検証は維持する。

コミット `c57c790792e512289de79bbfd56d667ebfea4283` の [run 42347602362](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42347602362) でiPhone 17 / iOS 27.1を指定したところ該当機種が未登録で停止。取得した一覧を根拠に、存在する安定版iPhone 17 / iOS 27.0へ固定した。Xcodeは27.1、ビルド番号は1のまま。

## 次の作業

修正をpushしてCIを再実行する。失敗時はログを取得・修正し、成功したコミットのIPAを検査して `dist/PhotoPlayer.ipa` へ取得する。初回実機結果を待つ。結果を受けるまで上書き試験版は作らない。
