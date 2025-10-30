# Nike Research Tool

NIKE の商品一覧ページをクロールし、バリエーション別の価格や画像 URL を収集して Google スプレッドシートへ書き戻す Ruby 製の自動化ツールです。処理の開始・終了状況は Notion に通知され、実行ログはローカルに保存されます。

## 主な機能
- Selenium + ChromeDriver を用いた商品一覧ページの全件スクレイピング
- 無限スクロール対応の商品収集（スクロールとユニークURLカウントによる終了判定）
- バリエーション画像IDの取得（ホバー処理による動的画像読み込み対応）
- "+"フラグ検出機能（バリエーション数が5個以上の場合の判定）
- バリエーション URL を生成して商品詳細（型番・画像・価格）を取得
- 収集データの一時 CSV 化とスプレッドシートへの一括更新
- Notion ページへの稼働中 / 停止 / エラー通知
- ログローテーションと Shift_JIS 変換による日本語テキスト整形

## ディレクトリ構成
```
.
├── main.rb                  # エントリーポイント
├── scraper.rb               # Selenium ベースのスクレイパー
├── file_create.rb           # CSV や Sheets ユーティリティ、ログ処理
├── notion_manager.rb        # Notion API 連携
├── main.vbs                 # Windows 用最小化起動スクリプト
├── settings/
│   ├── config.json          # Google サービスアカウント JSON キー
│   └── account_settings.csv # スプレッドシート & Notion 設定
├── process/                 # 中間データ (nike_items.csv)
├── results/                 # 出力データ (nike_datas.csv)
└── logs/                    # 実行ログ
```

## 必要環境
- Ruby 3.x 以降
- Bundler (`gem install bundler`)
- Google Chrome と対応する ChromeDriver（PATH に配置）
- Google Sheets API と Notion API を利用できる認証情報

## セットアップ
1. 依存パッケージをインストールします。
   ```bash
   bundle install
   ```
2. `settings/config.json` に Google サービスアカウントの JSON キーを配置します。  
   そのアカウントを対象スプレッドシートへ編集権限付きで共有してください。
3. `settings/account_settings.csv` を Shift_JIS で編集し、以下を設定します（A 列=キー、B 列=値）。
   | key               | value 例 (実際の値に置き換え) |
   |-------------------|--------------------------------|
   | `spreadsheet_key` | `1A2B3C...`                     |
   | `notion_api_key`  | `secret_xxx`                    |
   | `database_id`     | `xxxxxxxxxxxxxxxx`              |
   | `page_id`         | `xxxxxxxxxxxxxxxx`              |

4. 対象スプレッドシートの各ワークシート `B1` セルに NIKE 商品一覧ページの URL を記載します。

## 実行方法
- 通常実行（Mac / Linux）
  ```bash
  bundle exec ruby main.rb
  ```
- Windows で最小化実行したい場合は `main.vbs` をダブルクリックします。

実行すると `logs/` にタイムスタンプ付きログが生成され、結果が Google スプレッドシートへ反映されます。Notion ページには稼働ステータスが更新されます。

## 処理フロー概要
1. `scrape_nike_list_page` が商品一覧ページをスクロールしながら全件収集
   - 無限スクロール処理（20ステップで段階的にスクロール）
   - ユニークURLカウントによる終了判定
   - 各商品カードから商品情報とバリエーション画像IDを取得
   - "+"フラグの検出（カードテキストから検出）
   - `process/nike_items.csv` に保存
2. 各商品について `retrieve_variation_url` がバリエーション URL を生成し、必要に応じてチェックフラグを付与
3. `scrape_nike_page` がバリエーションごとに画像 URL・型番・価格を取得し、`results/nike_datas.csv` に追記
4. スプレッドシート 3 行目以降をクリアし、結果データを `A:G` 列に一括書き込み
5. Notion ページに開始 / 終了通知（エラー時はメッセージ付き）を送信

## 技術的な特徴
- **CSSセレクターベースの要素検索**: HTML構成変更に対応するため、複数のセレクターを順次試行
- **ホバー処理による画像ID取得**: バリエーションリンクにホバーして動的に読み込まれる画像を取得（2番目以降のバリエーション）
- **画像URLからの画像ID抽出**: 画像URLから画像IDを抽出（URLの最後から2番目のパスセグメント）
- **エラーハンドリング**: 各段階でエラーハンドリングを実施し、処理継続性を確保

## 生成物
- `logs/log_YYYYMMDDHHMMSS.log` … 実行ログ
- `process/nike_items.csv` … 商品一覧から取得した中間データ
- `results/nike_datas.csv` … スプレッドシート書き込み前の最終データ

## トラブルシューティング
- **ChromeDriver のバージョン不一致**: Chrome と一致するバージョンをダウンロードして置き換えてください。
- **Google API 認証失敗**: `config.json` の権限と `account_settings.csv` のキー名を再確認してください。
- **Notion 通知失敗**: API キーの有効期限と対象ページの権限、ネットワーク制限を確認してください。
- **DOM 変更によるスクレイピング失敗**: ログに出力される URL とエラー内容を確認し、`scraper.rb` の CSSセレクターまたは XPath を更新してください。
- **Stale Element Reference エラー**: ページ遷移後に古い要素を参照している可能性があります。要素取得前にページの読み込み完了を待機する処理を追加してください。

## 開発メモ
- ヘッドレス実行する場合は `scraper.rb` の `options.add_argument('--headless')` のコメントアウトを解除します。
- 大量データで 429 / Timeout が発生する場合は、スクロール間隔や待機時間 (`sleep`, `Wait#timeout`) を調整してください。
- 機能追加や再利用を見据える場合は、ワークシート単位の処理ブロックをクラス化するなど責務の分離を検討してください。

