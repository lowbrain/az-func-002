# az-func-002

このプロジェクトは、PowerShellで実装されたAzure Functionsです。

## 機能概要

このFunctionは、**Log Analyticsのアラートをトリガー**として、アラートの検索結果に含まれるユーザーを**特定のEntra ID（旧Azure AD）セキュリティグループに自動で追加**します。

主に、セキュリティインシデントや特定のログパターンが検出された際に、関連するユーザーを即座に特定のグループ（例：アクセス制限グループ、要監視ユーザーグループなど）に所属させる、といったセキュリティオートメーションのユースケースを想定しています。

### 処理フロー

1.  **HTTPトリガーで起動**:
    Log Analyticsのアラートルールに設定されたWebhookアクションによって、このFunctionが呼び出されます。リクエストボディには、アラートのコンテキスト情報が含まれています。

2.  **Log Analyticsの検索結果を取得**:
    リクエストボディから`linkToSearchResultsAPI`のURIを抽出し、Function Appに割り当てられた**マネージドID**を使ってLog Analytics APIにアクセスします。これにより、アラートを発生させた元のログクエリ結果（ユーザーIDのリストなど）を取得します。

3.  **Microsoft Graph APIでグループメンバーを追加**:
    取得したユーザーIDのリストを使い、Microsoft Graph APIを呼び出します。ここでも**マネージドID**で認証を行い、環境変数で指定されたEntra IDのセキュリティグループに、対象ユーザーを一括で追加します。

### 主な特徴

*   **セキュリティオートメーション**: Log Analyticsのアラート検知からグループメンバーの更新までを自動化します。
*   **セキュアな認証**: マネージドIDを利用してLog AnalyticsとMicrosoft Graphの両方にアクセスするため、コード内に認証情報（シークレットや証明書）を保持する必要がありません。
*   **モジュール化された設計**: Log Analytics APIやMicrosoft Graph APIとの通信処理が、それぞれ`LogAnalyticsApi.psm1`と`MgGraphApi.psm1`というカスタムモジュールに分離されており、再利用性と保守性が高められています。
*   **依存関係の自動管理**: `requirements.psd1`で定義されたPowerShellモジュール (`Az.Accounts`, `Microsoft.Graph.Groups`) は、Azure Functionsのホストによって自動的に管理されます。

## 必要な設定

このFunctionを正しく動作させるためには、以下の設定が必要です。

*   **アプリケーション設定（環境変数）**:
    *   `TARGET_GROUP_ID`: ユーザーを追加する対象のEntra IDセキュリティグループのオブジェクトIDを設定します。

*   **マネージドIDのアクセス許可**:
    *   **Log Analytics**: ログを読み取るための適切なRBACロール（例: `Log Analytics Reader`）が必要です。
    *   **Microsoft Graph**: グループメンバーを更新するためのAPIアクセス許可（例: `GroupMember.ReadWrite.All`）が必要です。

## カスタムモジュール

このFunctionは、以下のカスタムPowerShellモジュールを利用しています。

*   `modules/LogAnalyticsApi.psm1`: Log Analytics APIへの認証とクエリ実行を担当します。
*   `modules/MgGraphApi.psm1`: Microsoft Graph APIへの接続とグループメンバーの追加処理を担当します。
