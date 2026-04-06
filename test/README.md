# テスト

## ディレクトリ構成

```
test/
├── README.md
├── macos/
│   ├── README.md
│   └── run_tests.swift         # macOS 版テストランナー（XCTest 不要）
├── windows/
│   ├── README.md
│   ├── ErrorLoggerTests.cs
│   └── AdditionalPromptPersistenceTests.cs
└── data/                        # テストデータ（git 管理外）
    ├── test.m4a                 # macOS 用テスト音声ファイル
    ├── test.wav                 # Windows 用テスト音声ファイル
    └── test.transcript.txt      # 文字起こし済みテキスト
```

## テストデータ

`test/data/` ディレクトリは `.gitignore` で除外されています。
テスト実行前に以下のファイルを手動で配置してください。

| ファイル | 用途 | 対象 OS |
|---------|------|---------|
| `test.m4a` | 音声ファイル（文字起こしテスト用） | macOS |
| `test.wav` | 音声ファイル（文字起こしテスト用） | Windows |
| `test.transcript.txt` | 文字起こし済みテキスト（要約・エラーログテスト用） | 共通 |

## テスト実行

### macOS

```bash
swift test/macos/run_tests.swift
```

### Windows

```powershell
dotnet test --filter "FullyQualifiedName~ErrorLoggerTests"
dotnet test --filter "FullyQualifiedName~AdditionalPromptPersistenceTests"
```

## テスト方針

- テストにより生成されるファイル（エラーログ、設定 JSON 等）は全て `test/data/` 以下に出力する
- テスト完了後、テストにより生成されたファイルは自動的に削除される（テストデータは保持）
- テストは AWS 接続不要
