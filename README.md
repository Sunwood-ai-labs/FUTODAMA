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
| `PYTHON_AUTOSTART_ENABLE` | `0` | `1` で `/config` 上の Python スクリプトをコンテナ起動時に自動実行 |
| `PYTHON_AUTOSTART_SCRIPT` | (空) | 自動実行する Python スクリプトの絶対パス（例: `/config/startup/my_script.py`） |
| `PYTHON_AUTOSTART_CWD` | `/config` | Python スクリプトの実行作業ディレクトリ |
| `PYTHON_AUTOSTART_PYTHON` | `python3` | 使用する Python 実行ファイル |
| `PYTHON_AUTOSTART_DELAY_SEC` | `0` | 起動前の待機秒数（依存サービス待ちに使用） |
| `S6_USER_SERVICES_ENABLE` | `1` | `/config/s6-services` の `s6` サービス定義を自動読込 |
| `S6_USER_SERVICES_DIR` | `/config/s6-services` | 永続化する `s6` サービス定義ディレクトリ |

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

- イメージ内の `/custom-cont-init.d/05-selkies-touch-pid.sh` - selkies バックエンドの正常起動を保証
- `futodama-config/` 配下は実行時に生成・更新される永続化データ（Git では `.gitkeep` のみ管理）

## Pythonスクリプトの自動起動

この環境は `systemd` ではなく `s6` ベースで動作しているため、Python スクリプトの自動起動は `/custom-cont-init.d/31-python-autostart.sh` で行います。

1. `futodama-config/startup/my_script.py` を作成
2. `docker-compose.yml` の `environment` に以下を追加（またはコメント解除）
3. `docker compose up -d --build`（既存コンテナなら `docker compose restart`）

```yaml
environment:
  - PYTHON_AUTOSTART_ENABLE=1
  - PYTHON_AUTOSTART_SCRIPT=/config/startup/my_script.py
  - PYTHON_AUTOSTART_CWD=/config/startup
  - PYTHON_AUTOSTART_PYTHON=python3
  - PYTHON_AUTOSTART_DELAY_SEC=5
```

- ログ: `/config/.local/state/futodama/python-autostart.log`
- PID: `/config/.local/state/futodama/python-autostart.pid`
- スクリプトは `abc` ユーザー（`HOME=/config`）で実行されます

## s6常駐サービス（再起動つき）

長時間動かす Python スクリプトは、`s6` サービスとして `/config/s6-services/` に置く方法を推奨します。`s6` が監視するため、プロセスが落ちても再起動されます。

- サービス定義の場所: `/config/s6-services/<service-name>/run`
- コンテナ起動時に `/custom-cont-init.d/32-s6-user-services.sh` が `/run/service` にリンクして有効化
- `run` は `chmod +x` が必要（起動時に自動で `+x` を試行）

例: Python 常駐スクリプトを `s6` 管理にする

1. `futodama-config/startup/my_worker.py` を作成
2. `futodama-config/s6-services/my-python/run` を作成
3. `docker compose up -d --build`（初回）または `docker compose restart`

`futodama-config/s6-services/my-python/run`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /config/startup
exec env HOME=/config python3 /config/startup/my_worker.py >>/config/.local/state/futodama/my-python.log 2>&1
```

確認コマンド（コンテナ内）

```bash
ps aux | grep my_worker.py
tail -f /config/.local/state/futodama/my-python.log
```

補足:
- `PYTHON_AUTOSTART_*` は「起動時に1回だけ実行」
- `s6` サービスは「常駐監視 + 自動再起動」

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
