# BarFold

<div align="center">

**混み合った macOS メニューバーを、コンパクトな2段目に整理します。**

[English](README.md) | [简体中文](README_CN.md) | 日本語

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![BarFold をビルド](../../actions/workflows/build.yml/badge.svg)](../../actions/workflows/build.yml)

</div>

BarFold は、選択したメニューバー項目をメニューバー直下のコンパクトな2段目へ移動する、macOS ネイティブの整理ツールです。ノッチ付き Mac や小型ディスプレイで、ステータス項目を表示するスペースが不足する場合に役立ちます。

## プレビュー

<div align="center">
  <img src="docs/images/settings.png" alt="BarFold 設定画面" width="480">
  <br><br>
  <img src="docs/images/second-row.png" alt="BarFold の2段目" width="330">
</div>

設定でチェックした項目は1段目に残り、チェックしていない項目は BarFold の2段目へ移動します。

## 主な機能

- macOS のアクセシビリティ API を使ってメニューバー項目を検出します。
- 選択した項目を折りたたみ可能な2段目へ移動し、1段目に透明な空き領域を残しません。
- BarFold のステータス項目から2段目を展開・折りたたみできます。
- 2段目の外側をクリックするか `Esc` を押すと自動的に閉じます。
- 2段目の項目をクリックすると、対応するアプリまたは設定画面を開きます。
- 2段目のアイコンをドラッグして、任意の順序を維持できます。
- 選択を変更しても、設定リスト内の項目位置は変わりません。
- macOS によって固定されているコントロールセンターと時計は1段目に残します。
- 初回起動時は、検出可能な項目を既定で2段目へ移動します。
- ログイン時の起動と複数ディスプレイに対応します。
- トラブルシューティング用のローテーション診断ログをローカルに保存します。
- システム言語に追従するほか、簡体字中国語、繁体字中国語、英語、日本語、韓国語、フランス語、ドイツ語、スペイン語を選択できます。

## 動作要件

- macOS 13 Ventura 以降。
- メニューバー項目の検出と並べ替えにアクセシビリティ権限が必要です。
- 対象項目が十分なアクセシビリティ情報を公開している必要があります。

macOS には、他のアプリのステータス項目を管理する公開 API がありません。BarFold はアクセシビリティイベントと WindowServer のメニューバーウィンドウ情報を利用するため、Mac App Store での配布には適していません。

## インストール

1. [GitHub Releases](../../releases/latest) から `BarFold-x.y.z.zip` をダウンロードします。
2. 展開後、権限を付与する前に `BarFold.app` を `/Applications` へ移動します。
3. BarFold を開きます。ad-hoc 署名のビルドが macOS にブロックされた場合は、Control キーを押しながらアプリをクリックして**開く**を選ぶか、**システム設定 > プライバシーとセキュリティ**で実行を許可します。
4. **システム設定 > プライバシーとセキュリティ > アクセシビリティ**で BarFold を有効にします。
5. BarFold の設定を開き、1段目に残す項目をチェックします。チェックしていない項目は自動的に2段目へ移動します。
6. メニューバーの BarFold アイコンをクリックして、2段目を展開または折りたたみます。

アプリを移動した場合や、コード署名が異なるビルドに置き換えた場合、macOS からアクセシビリティ権限を再度求められることがあります。

## 使い方

### 表示する段を選ぶ

2段目右側の歯車ボタンから設定を開くか、BarFold のステータス項目を右クリックして**設定**を選びます。チェックした項目は1段目に残り、チェックしていない項目は2段目へ移動します。

### 2段目を操作する

- BarFold のステータス項目を1回クリックすると展開し、もう一度クリックすると折りたたみます。
- 項目をクリックすると対応するアプリを開きます。メニューバー専用アプリでは、環境設定が開く場合があります。
- 項目を左右にドラッグすると、2段目での順序を変更できます。
- 2段目の外側をクリックするか `Esc` を押すと閉じます。
- 他のメニューバーアプリをインストール、終了、または並べ替えた後は、更新ボタンで再スキャンできます。

### 言語を変更する

設定を開き、右上の地球ボタンをクリックします。変更はすぐに反映され、次回起動時にも維持されます。

## ソースからビルド

Xcode 16 または Swift 6 ツールチェーンが必要です。

```bash
git clone <your-repository-url>
cd BarFold
chmod +x scripts/package-app.sh scripts/build-release.sh
./scripts/build-release.sh
open dist/BarFold.app
```

リリース用 ZIP は `outputs/BarFold-<version>.zip` に生成されます。ローカルに Apple Development 証明書がある場合は最初の有効な証明書を使用し、ない場合は ad-hoc 署名を使用します。使用する証明書を明示することもできます。

```bash
BARFOLD_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/build-release.sh
```

## GitHub Actions

[`.github/workflows/build.yml`](.github/workflows/build.yml) には、公開 GitHub リポジトリ向けの自動ビルドフローが用意されています。

- Push と Pull Request では、警告をエラーとして扱ってコンパイルし、アプリのパッケージ化、署名と ZIP の検証、Actions アーティファクトのアップロードを行います。
- `v*` 形式のタグを Push すると、ZIP を添付した GitHub Release を自動作成または更新します。
- タグは `CFBundleShortVersionString` と一致する必要があります。たとえばアプリのバージョンが `0.5.4` の場合、タグは `v0.5.4` です。

GitHub のリモートリポジトリを設定した後、次のコマンドで公開できます。

```bash
git push origin main
git push origin v0.5.4
```

GitHub ホスト環境での既定ビルドは ad-hoc 署名です。一般公開時の Gatekeeper 警告をなくすには、Developer ID Application 証明書を使用し、既定フローとは別に Apple の公証処理を追加してください。

## 診断ログ

設定画面右上の診断ログボタンをクリックすると、Finder で次のファイルを表示できます。

```text
~/Library/Application Support/BarFold/barfold.log
```

ログは Mac 内にのみ保存され、BarFold が自動送信することはありません。1 MB に達すると `barfold.previous.log` にローテーションし、最新2ファイルだけを保持します。

## 既知の制限

- コントロールセンターと時計は macOS に固定されているため移動できません。
- 一部のサードパーティ製ステータス項目は十分なアクセシビリティ情報を公開しないか、合成ドラッグイベントを拒否します。
- macOS のメジャーアップデート後に互換性対応が必要になる場合があります。
- 2段目のクリックはアプリまたは環境設定を開くためのもので、各アプリのネイティブステータスメニューは再現しません。

移動や起動の失敗を報告する際は、macOS のバージョン、BarFold のバージョン、対象アプリ名、関連する診断ログの抜粋を添えてください。
