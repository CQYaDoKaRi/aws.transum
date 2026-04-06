# Windows 版テスト

Windows 版のテストは xUnit を使用します。

## テストファイル

```
test/windows/
├── ErrorLoggerTests.cs                 # エラーログテスト
└── AdditionalPromptPersistenceTests.cs # 追加プロンプト永続化テスト
```

## 実行方法

```powershell
dotnet test --filter "FullyQualifiedName~ErrorLoggerTests"
dotnet test --filter "FullyQualifiedName~AdditionalPromptPersistenceTests"
```

## 前提条件

- .NET 8 SDK
- テストデータ（`test/data/test.wav`, `test/data/test.transcript.txt`）を配置済みであること
