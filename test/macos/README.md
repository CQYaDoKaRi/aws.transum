# macOS 版テスト

## 実行方法

プロジェクトルートから実行:

```bash
swift test/macos/run_tests.swift
```

## テスト内容

- ErrorLogger: 元ファイル名ベースのエラーログ出力、app.error.log フォールバック、追記動作
- 追加プロンプト永続化: 設定 JSON への保存・復元、空文字対応、他設定への影響なし
- テストデータ存在確認: test.m4a, test.transcript.txt

## 備考

XCTest / Swift Testing を使わない独立スクリプト形式のため、Xcode 不要で実行可能です。
