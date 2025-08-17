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
    このFunctionが利用するマネージドIDには、アクセス先のサービスに応じて2種類の異なるアクセス許可を付与する必要があります。

    ### 1. Log Analyticsへのアクセス許可 (Azure RBAC)

    Function AppがAzureリソースである**Log Analyticsワークスペース**のデータを読み取るための権限です。

    *   **目的**: アラートのトリガーとなったログ検索結果（`linkToSearchResultsAPI`の先にあるデータ）を取得するため。
    *   **必要な権限**: `Log Analytics 閲覧者 (Log Analytics Reader)` という **Azure RBACロール**。
        *   このロールを割り当てることで、Log Analytics APIへの読み取りアクセスが許可されます。
    *   **設定方法**:
        1.  Azureポータルで、対象の**Log Analyticsワークスペース**に移動します。
        2.  `[アクセス制御 (IAM)]` を選択します。
        3.  `[追加]` > `[ロールの割り当ての追加]` をクリックします。
        4.  ロールとして `Log Analytics 閲覧者` を選択します。
        5.  `[アクセスの割り当て先]` で `マネージド ID` を選択し、このFunction AppのマネージドID（サービスプリンシパル）を選択して割り当てます。
    *   **補足**: 手動でEntra IDにアプリを登録し、APIのアクセス許可を追加する必要は**ありません**。Log Analytics APIへのアクセスはAzure RBACによって制御されます。

    ### 2. Microsoft Graphへのアクセス許可 (APIのアクセス許可)

    Function Appが**Microsoft Graph API**を呼び出して、Entra IDのグループメンバーを操作するための権限です。これはAzure RBACロールとは別の仕組みです。

    *   **目的**: Log Analyticsから取得したユーザーを、指定されたEntra IDのセキュリティグループに追加するため。
    *   **必要な権限**: `GroupMember.ReadWrite.All` という **Microsoft Graph APIのアクセス許可 (Application)**。
    *   **重要**: この権限は強力なため、付与するには**管理者の同意**が必要です。
    *   **設定方法**:
        管理者の同意は、PowerShellやAzure CLIを使用してマネージドIDのサービスプリンシパルに直接APIロールを割り当てることで行います。
        以下のPowerShellスクリプトを実行するには、`AppRoleAssignment.ReadWrite.All` などの管理者権限でMicrosoft Graphに接続する必要があります。

        ```powershell
        # 前提:
        # 1. Microsoft.Graph モジュールがインストールされていること
        #    Install-Module Microsoft.Graph -Scope CurrentUser
        # 2. 管理者権限でGraphに接続していること
        #    Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All"

        # Function AppのマネージドIDのオブジェクトID (Azureポータルから取得)
        $managedIdentityObjectId = "YOUR_FUNCTION_APP_MANAGED_IDENTITY_OBJECT_ID"
        $msi = Get-MgServicePrincipal -ServicePrincipalId $managedIdentityObjectId

        # Microsoft Graph APIのサービスプリンシパルを取得
        $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

        # 'GroupMember.ReadWrite.All' のAppRoleを取得
        $appRole = $graphSp.AppRoles | Where-Object {$_.Value -eq 'GroupMember.ReadWrite.All'}

        # マネージドIDにAPIアクセス許可を付与
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id -PrincipalId $msi.Id -ResourceId $graphSp.Id -AppRoleId $appRole.Id
        ```
    *   **補足**: 上記のスクリプトを管理者として実行する操作が、Azureポータルで「管理者の同意を与えます」ボタンをクリックする行為に相当します。これにより、アプリケーションがテナント全体のグループメンバーシップを管理することを正式に許可したことになります。

## カスタムモジュール

このFunctionは、以下のカスタムPowerShellモジュールを利用しています。

*   `modules/LogAnalyticsApi.psm1`: Log Analytics APIへの認証とクエリ実行を担当します。
*   `modules/MgGraphApi.psm1`: Microsoft Graph APIへの接続とグループメンバーの追加処理を担当します。
