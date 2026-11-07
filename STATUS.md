# 開発状況

更新日: 2026-11-07

## 現在地

**段階1合格、段階2の実装・CI成功、ビルド3の実機確認待ち**。ビルド2の実機上書き・オフライン再起動は全項目合格、値12（2026-11-07の本人報告）。段階2の実装指示に従って動画再生機能を追加した。
引き渡し候補はバージョン0.2.0 / ビルド3。
固定Bundle ID: `io.github.photoplayer.p6a936d329b934a8ba532081564a51c07`。

PhotoKitの動画一覧・サムネイル・限定アクセス、AVPlayerへの直接再生、シーク、0.25/0.5/1/1.25/1.5/2倍、iCloud取得の進捗・取消・再試行を実装。アプリによる動画の永続コピー・書き出し・ライブラリ変更・アップロードは行わない。Photosによる取得キャッシュはOS管理。既存カウンターは「導入確認」に残し、標準UserDefaultsと `manualCounter.v1` を維持した。[公開リポジトリ](https://github.com/YotaFujimoto/photo-player-ios)へpush済み。本人用 `DEVELOPMENT_PLAN.md` はGit管理対象外で、公開側の一覧にも含まれないことを確認済み。

## 最後の成功

- 成功したビルドコミット: [`6125b2db204f7d45cd7b582c3f590a10be993c61`](https://github.com/YotaFujimoto/photo-player-ios/commit/6125b2db204f7d45cd7b582c3f590a10be993c61)。後続の文書だけのコミットはこのIPAのソースを変更しない。
- 成功CI: [run 42360541851](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42360541851)、**attempt 2**、2026-11-07。head SHA・run attempt・成果物来歴を照合済み。
- 実行環境: 標準 `xcode-27`、image `20261104.0337.1`、Xcode 27.1 (`27A9275`)、XcodeGen 2.46.0。
- 自動検証: IPA検査器4件、単体6件、iPhone 17 / iOS 27.0のRelease UI試験2件が成功（計12件、失敗0）。合成素材の形式・30秒の長さと、メディアをコピー／変更／アップロードしない静的検査も成功。PhotoKit一覧・サムネイル、0.25倍の実速度と時刻進行、停止中／再生中のシーク、閉じる、カウンター12の背景移行・終了・再起動後保持を確認。画面画像5枚を目視確認済み。実機の音質や上書き確認の代わりにはしない。
- 実機用IPA: `dist/PhotoPlayer.ipa`、202,364 bytes、**ビルド3 / 0.2.0**。iOS 17.0以上。実機arm64、SDK `iphoneos27.1`、Release、未署名。CIとWindowsでplist・Mach-Oを検査済み（`LC_BUILD_VERSION platform=IOS(2)`、署名なし）。
- SHA-256: `f1814b986319892ea6a940b99b58cb3e9a836ab031a5a244a541f7b4f8da5975`。
- 来歴: `dist/build-info.json`。成功CIログ・テスト結果・画面画像はローカル `build/evidence-42360541851-attempt2/` と `build/success-42360541851-attempt2.log` に取得済み。GitHub成果物の保持は3日。
- 最新の実機合格版: **ビルド2**（コミット `003a6d73620230685e6f7509fa3a894d189d8355`、[run 42350896546](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42350896546)）。上書き・終了／再起動・PCなし機内モードでの値12保持に合格。IPA・来歴・本人報告を `dist/known-good/build-2/` に保管し、元のSHA-256 `1b3ba0aba813b83b262d9ffae0e0325191e88ff6ed36baf623a264cbc2550ae0` と一致することを再確認済み。ビルド1も `dist/known-good/build-1/` に保管継続。ビルド3は実機合格前の候補であり、正常版を置き換えない。

## 未確認事項

ビルド3の実機上書きと値12保持、権限の限定／拒否からの復帰、実動画の0.25倍音質・同期・長時間シーク、HEVC/HDR/編集済み素材、実iCloud取得の進捗・取消・ネットワーク切断・再試行、再署名の運用。CIで使うのは合成素材とシミュレーターだけで、これらの実機結果は未判定。

## 初回CIの調査

コミット `689dfe7a8822ac323c706ca633611844e636ac5a` の [run 42346620649](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42346620649) は試験ステップの長時間待機を調査するため中断。回収したログでは、起動と12までの加算後、iPhone Duoのホーム遷移で `.runningBackground` に到達せずテストが失敗していた。正常な `.runningBackgroundSuspended` も扱うよう変更し、再起動後の保存検証は維持する。

コミット `c57c790792e512289de79bbfd56d667ebfea4283` の [run 42347602362](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42347602362) でiPhone 17 / iOS 27.1を指定したところ該当機種が未登録で停止。取得した一覧を根拠に、存在する安定版iPhone 17 / iOS 27.0へ固定した。Xcodeは27.1、ビルド番号は1のまま。

## ビルド2のCI調査

[run 42350093139](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42350093139)、コミット `e0819f29473570fda61bde3cacdfb923154d7da5` はUIテストの背景状態確認で失敗。回収したXCTest診断ログでは、背景状態の1秒待機が終了した後、一時停止状態を待っている間に実際の状態が背景へ変わり、誤って失敗していた。正常な背景／一時停止のどちらかを単一の述語で同時に待つよう修正し、終了・再起動後の値保持の検証は維持した。失敗時にも画面画像を取得できるようにした。アプリ本体・Bundle ID・保存方式は変更していない。

## 次の作業

1. 本人が既存アプリを削除せず、同じ署名設定でビルド3を上書きし、`TESTING.md` の5項目を確認する。失敗時は項目番号と現象だけを受け取り、動画・ログ転送を求めず調査する。
2. 実機結果を記録し、必要なら同じBundle ID・保存キーを維持した次候補を作る。実機合格した場合にだけビルド3を `dist/known-good/` へ追加する。
3. 音声付き0.25倍と長時間動画の実機合格、および次段階の明示指示を受けるまで段階3以降へ広げない。

## ビルド3のCI調査

- [run 42354951618](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42354951618)、コミット `a696c87c6768b2ce0e7c29af72c6062a44c3b4a6` はアプリ試験前の合成素材生成で失敗。AVAssetWriterの入力待機が60秒で打ち切られ、ログには仮想環境の映像ドライバー照合失敗も出ていた。CI素材生成をFFmpegのソフトウェアH.264/AACへ変更し、生成後の形式・30秒の長さを検査する。再実行で素材生成と検査の成功を確認済み。
- シーク完了時、停止中のプレイヤーから次の定期通知が来なくても表示を更新するよう補強。UI試験には停止中のシークに加え、再生中のシーク後の0.25倍維持も追加。
- [run 42355693541](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42355693541) は合成素材検査に成功したが、コンパイルでHDR属性のAPI指定とPhotosUIのimport不足が判明。HDRはAVFoundationの `.containsHDRVideo` トラック読み込みへ修正し、限定アクセス選択にPhotosUIを読み込む。試験対象1台と同じarm64だけをシミュレーターでビルドする。
- [run 42356382683](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42356382683) はReleaseビルド・単体6件・カウンター保存試験に成功。動画一覧・サムネイル・再生・0.25倍選択と時刻進行まで成功した後、実速度のUI要素検出で失敗。取得した画面階層で、DisclosureGroupの識別子が子の実速度表示へ伝播して上書きされていることを確認。親の識別子を除き、開閉は表示ラベルで操作する。0.25倍の実速度検証は維持する。画像と階層から判明したサムネイルのセル幅超過と、端末内素材の取得進捗をiCloudと誤分類する表示も修正。
- [run 42357587482](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42357587482) は実速度0.25倍表示と停止中の中央シークまで成功。再生中のシーク後にUI照会が時間切れ。xcresult内のアプリログでは実速度0.25倍を維持した応答が約19秒後に届いており、速度設定の不一致ではなく応答遅延だった。画面更新ごとの同一AVPlayer再設定と、同じ値のPublished通知を抑え、SDK警告があった音声セッション操作を直列のバックグラウンドキューへ移す。取消後の音声完了通知も無効化する。速度・位置の合格条件と待機上限は維持し、CIだけで匿名のシーク／再開ログを有効にして再検証する。

ビルド3の [run 42359098117](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42359098117) ではUI応答とシーク後の0.25倍維持が成功。位置確認で失敗したが、診断ログの最終要求24.496秒に対して実際は24.495秒へ移動済みで、最初の位置照会時には0.25倍再生で25秒へ進んでいた。XCTestのスライダー操作は近似であり、再生中の画面に固定の22〜24秒だけを期待した試験の時刻基準を修正する。同じ幅の期待範囲を0.25倍の経過時間だけ進め、15秒の待機上限・実速度・再生状態の検証は維持する。

- [run 42360541851](https://github.com/YotaFujimoto/photo-player-ios/actions/runs/42360541851) attempt 1は単体6件・カウンター保持に成功したが、動画画面を開く前の一覧UI照会が停止。spindumpではアプリのメインスレッドがXCTestの画面階層走査とログ出力の `writev` / OSのI/O待ちに滞留し、60秒の自動操作応答上限、続いて試験上限を超過していた。再生処理や今回修正したシーク判定には未到達。同じコミット・試験条件を新しい標準ランナーで再実行し、実行環境の一時停止と実装の問題を切り分ける。

同じコミットのattempt 2で全12試験・実機アーカイブ・成果物取得に成功。動画UI試験は44.488秒、カウンターUI試験は52.818秒で完了した。attempt 1の遅延は再現せず、試験条件・待機上限を変えずに確認を完了した。失敗attemptの証跡もローカル `build/evidence-42360541851/` に保持する。

## 段階1の実機合格

ビルド2は「全項目合格、値12」の報告を受領。削除せず上書きした後のデータ維持とPCなし・機内モード再起動に合格した。IPA・来歴・実機結果を `dist/known-good/build-2/` に保管し、SHA-256 `1b3ba0aba813b83b262d9ffae0e0325191e88ff6ed36baf623a264cbc2550ae0` を照合済み。ビルド1も保管継続。
