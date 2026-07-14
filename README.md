# CodexBar — Codex / ChatGPT Workの消費監視Macアプリ

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Codex / ChatGPT Workの共通週間枠を、残量だけでなく「このMacのCodex利用速度」から判断するためのmacOSメニューバーアプリです。

このリポジトリは[steipete/CodexBar](https://github.com/steipete/CodexBar)の個人forkです。上流版が対応する各種AIサービスの使用状況表示を維持しつつ、このMacでのCodexの短期的な使いすぎを早く検知できる表示を追加しています。

> [!IMPORTANT]
> このfork独自のリリース配布やHomebrew Formulaはありません。利用する場合はソースからビルドしてください。上流版のリリースやHomebrew版には、このforkの消費速度機能は含まれません。

## このforkで追加した機能

- メインメニューに、直近1時間の消費速度グラフを常時表示
- 「消費速度・24h」サブメニューに、直近24時間の推移を表示
- 直近15分・1時間・24時間の速度を、安全速度に対する倍率で表示
- 現在の速度を続けた場合、週間上限がリセット前に枯渇するかを予測
- Codex Spark Weeklyとコードレビュー枠を補助情報としてコンパクトに表示
- アカウントごとに履歴を分離し、別アカウントのデータ混入を防止

## 計測対象

OpenAI公式資料では、CodexとChatGPT Workは料金・クレジット・利用上限を共有します。このアプリの「週間残量」は、サインイン中のChatGPTアカウント／ワークスペースに紐づく、この共通枠です。詳細は[OpenAI公式のCodex pricing](https://learn.chatgpt.com/docs/pricing)を参照してください。

| 表示・利用形態 | このアプリでの扱い |
| --- | --- |
| 週間残量 | Codex / ChatGPT Workの共通枠をアカウント側から取得 |
| 消費速度 | 主にこのMacのローカルCodexログから推定 |
| 通常のChatGPTチャット・画像・音声 | 総使用量を取得・合算しない |
| OpenAI APIキーによる利用 | 対象外。ChatGPTの利用枠ではなくAPI使用量として別途課金 |

別のMac、Codex Cloud、ChatGPT Workなどで同じ共通枠を使った場合、その消費は週間残量には反映されます。一方、現在の速度は主にこのMacのログを分子として計算するため、別環境での短期的な消費を過小評価する可能性があります。

## 指標の読み方

`1.0×`は、Codex / ChatGPT Work共通枠の現在の残量を、週間リセットまで均等に使い切る速度です。

| 表示 | 意味 |
| --- | --- |
| `1.0×` | リセットまで持続できる安全速度 |
| `1.0×`より大きい | 現在のペースでは早期枯渇する可能性がある |
| `1.0×`より小さい | 現在のペースを継続しても余裕がある |
| `≈`付き | ローカルトークン数と上限消費率の関係を推定中 |

表示倍率は、共通週間枠の残量とリセットまでの時間から求めた安全速度に対して、ローカルのCodexログから計測した速度が何倍かを表します。OpenAIがトークン数と上限消費率の正確な換算式を公開しているわけではないため、実測に基づく推定値です。

### 計測開始後の目安

| 指標 | 表示に必要な履歴 |
| --- | ---: |
| 15分 | 約1分で参考値を表示。15分経過後に全区間を計測 |
| 1時間 | 約48分 |
| 24時間 | 約19時間12分 |

枯渇予測には、1時間値が揃うまでは15分値、その後は1時間値を使います。計測中に共通週間枠の使用率が0%のまま、ローカルログがない、アカウントを特定できないなどの状態では、倍率を表示できません。

## 必要環境

- macOS 14以降
- Swift 6.2対応のXcode Command Line Tools
- Codex CLI、またはCodexを利用できるChatGPT環境
- CodexBarから週間使用枠を取得できること

## インストール

このforkの`main`を取得して、ローカル署名のアプリを作成します。

```bash
git clone https://github.com/Taku0728/CodexBar.git
cd CodexBar
./Scripts/package_app.sh release
open CodexBar.app
```

初回ビルドではSwift Package Managerが依存関係を取得するため、時間がかかる場合があります。生成される`CodexBar.app`はad-hoc署名で、自動更新は無効です。

常用する場合は、終了後に`CodexBar.app`を`/Applications`へ移動して起動してください。

## 初期設定

1. CodexBarの「設定」を開く
2. 「Providers」から「Codex」を有効にする
3. Codexの取得元を`Auto`、`OAuth`、`CLI`から選ぶ。通常は`Auto`
4. `Historical tracking`を有効にする
5. メニューからCodexを更新する

消費速度の計測には`Historical tracking`が必須です。`OpenAI web extras`はコードレビュー枠やWebダッシュボード由来の補助情報にだけ必要で、消費速度の計測には不要です。

Codex連携の詳細は[`docs/codex.md`](docs/codex.md)を参照してください。

## データの取得と保存

消費速度機能は、次のデータを組み合わせます。

- Codex / ChatGPT Work共通週間枠の残量・リセット時刻・アカウント情報
- 既知のCodexログ保存先にあるローカルセッションログ
- Codex CLIが返す累積トークン情報（ローカルログを利用できない場合）

独自の外部送信先は追加していません。速度履歴は次のファイルへローカル保存します。

```text
~/Library/Application Support/com.steipete.codexbar/history/codex-consumption-velocity.json
```

速度履歴の保持期間は8日です。直近24時間は詳細なサンプルを保持し、それより古いデータは1時間単位に圧縮します。上流版由来の各プロバイダーは、それぞれの公式APIやWebエンドポイントへ通信する場合があります。

## グラフの仕様

- メインメニューの横軸は常に直近1時間
- 「消費速度・24h」の横軸は常に直近24時間
- 縦軸は安全速度に対する倍率
- 破線は安全速度`1.0×`
- グラフ点は約5分間隔に間引き、最新点を追加
- 履歴が足りない区間は空白のまま表示

## Codex Spark Weeklyとコードレビュー

どちらも通常のCodex週間枠とは別の補助的な上限です。

- **Codex Spark Weekly**: Sparkモデル専用の週間枠
- **コードレビュー**: GitHub連携のコードレビュー枠。表示には`OpenAI web extras`が必要

このforkでは消費速度を優先し、これらはコンパクトな行として表示します。不要な場合は、設定の表示項目やCodexプロバイダー設定から非表示にできます。

## 開発

アプリのビルドと起動:

```bash
./Scripts/compile_and_run.sh
```

消費速度の単体テスト:

```bash
swift test --filter CodexConsumptionVelocityTests
```

リポジトリ全体の検査:

```bash
make check
```

開発手順の詳細は[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)、上流版の対応プロバイダーは[`docs/providers.md`](docs/providers.md)を参照してください。

## 上流版との関係

このforkで変更している主な対象はCodex / ChatGPT Work共通枠に対する、ローカルCodexの消費速度表示です。上流版の最新機能や修正が、このforkへ自動で取り込まれるわけではありません。

- 上流リポジトリ: [steipete/CodexBar](https://github.com/steipete/CodexBar)
- このfork: [Taku0728/CodexBar](https://github.com/Taku0728/CodexBar)
- 消費速度機能を含む標準ブランチ: [`main`](https://github.com/Taku0728/CodexBar/tree/main)

## ライセンス

[MIT License](LICENSE)。原著作者と上流プロジェクトのクレジットは[`LICENSE`](LICENSE)および[steipete/CodexBar](https://github.com/steipete/CodexBar)を参照してください。
