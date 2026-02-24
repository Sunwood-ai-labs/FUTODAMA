<div align="center">
  <img src="assets/header.jpeg" alt="FUTODAMA" width="100%">

# FUTODAMA

**F**ully **U**nified **T**ooling and **O**rchestration for **D**esktop **A**gent **M**achine **A**rchitecture

<img src="https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white" alt="Docker">
<img src="https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white" alt="Ubuntu">
<img src="https://img.shields.io/badge/XFCE-2284F2?logo=xfce&logoColor=white" alt="XFCE">
<img src="https://img.shields.io/badge/Chrome-4285F4?logo=googlechrome&logoColor=white" alt="Chrome">
<img src="https://img.shields.io/badge/ffmpeg-007808?logo=ffmpeg&logoColor=white" alt="ffmpeg">
<img src="https://img.shields.io/badge/noVNC-000000?logoColor=white" alt="noVNC">
</div>

---

AIエージェント専用のPCワークスペース環境。Dockerコンテナで動作するUbuntu XFCEデスクトップで、AIエージェントがブラウザ操作・画面確認・ファイル管理などを自律的に行える環境を提供します。

## 背景

以前は既存のPC上でAIエージェントを動かしていたが、エージェントの機能拡張に伴い操作範囲が広がり、ホスト環境への影響リスクが高まった。そのため、エージェント専用の**隔離されたサンドボックス環境**としてこのコンテナを作成。

**メリット：**
- 🛡️ ホストPCへの影響を完全遮断
- 🔒 エージェントの操作範囲を制御可能
- 🔄 環境のリセット・再構築が容易
- 📦 再現可能な環境をどこでも構築

## 特徴

- 🖥️ **ブラウザ経由でアクセス可能なデスクトップ環境**
- 🤖 **AIエージェントによる自律操作を想定した設計**
- 🌐 **Google Chrome** - Webブラウジング、スクレイピング、Webアプリ操作
- 🎬 **ffmpeg** - 動画・音声処理
- 🚀 **Antigravity** - AIエージェント用デスクトップアプリ

## Quick Start

1. リポジトリをクローン
2. `docker-compose up -d` を実行（Chrome、ffmpeg含むカスタムイメージをビルド）
3. `http://localhost:3333` でデスクトップにアクセス
4. デスクトップ上のアイコンから Chrome や Antigravity を起動

## 環境変数

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `CUSTOM_USER` | `user` | ログインユーザー名 |
| `PASSWORD` | `strong-pass` | ログインパスワード |
| `TZ` | `Asia/Tokyo` | タイムゾーン |

## ディレクトリ構成

```
.
├── Dockerfile
├── docker-compose.yml
├── futodama-config/      # AIエージェントのホームディレクトリ（永続化）
│   ├── Desktop/          # デスクトップ
│   ├── .config/          # アプリ設定
│   └── ...
├── data/                 # 作業データ（永続化）
└── futodama-config/ssl/  # SSL証明書（オプション）
```

## データ永続化

- `futodama-config/` - AIエージェントのホームディレクトリ（`/config`）。デスクトップ上のファイル、ブラウザプロファイル、アプリ設定などが保存される
- `data/` - 作業用データディレクトリ（`/data`）。外部ファイル、出力成果物などの置き場

## SSL設定

`futodama-config/ssl/` に証明書を配置すると WSS（Secure WebSockets）が有効になります。
> [!IMPORTANT]
> 証明書ファイルは秘密鍵を含むため git で管理されません。未設定の場合は起動時に自己署名証明書が自動生成されます。

## カスタム初期化スクリプト

- `futodama-config/custom-cont-init.d/01-touch-pid.sh` - selkies バックエンドの正常起動を保証

## AIエージェントからの利用

AIエージェントは以下の方法でこの環境を利用できます：

1. **ブラウザ操作** - Cinderella Browser API 経由で Chrome を操作
2. **画面確認** - noVNC や スクリーンショットAPIでデスクトップ状態を確認
3. **ファイル管理** - `data/` ディレクトリ経由でファイルをやり取り

## セキュリティ

- ポートは `127.0.0.1:3333` にバインド（外部から直接アクセス不可）
- コンテナ内では Chrome は `--no-sandbox` モードで動作（コンテナ環境向け）

### Chrome サンドボックス設定

Dockerコンテナ内ではChromeのサンドボックス機能が制限されるため、以下の設定で `--no-sandbox` を自動付与しています：

| 設定箇所 | 説明 |
|---------|------|
| `/usr/local/bin/google-chrome-launch` | Chrome起動用ラッパースクリプト。`--no-sandbox --disable-gpu` を自動付与 |
| `/usr/share/applications/google-chrome.desktop` | システムのdesktopファイルを修正し、ラッパーを使用 |
| `/usr/share/xfce4/helpers/google-chrome.desktop` | XFCEヘルパーを修正。`xdg-open`（Antigravityのリンク等）が正しく動作 |
| `/config/Desktop/google-chrome.desktop` | デスクトップショートカットもラッパーを使用 |

これにより、以下のすべてのケースでChromeが正常に起動します：
- デスクトップのChromeアイコンをクリック
- Antigravityから外部リンクを開く
- `xdg-open` コマンドでURLを開く
