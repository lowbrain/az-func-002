using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# モジュールをインポートします。Azure Functions の環境では、'modules' ディレクトリ内のモジュールは
# 自動的に利用可能になることが多いですが、明示的にインポートすることで、スクリプトの依存関係が明確になります。
Import-Module -Name ($PSScriptRoot + "/../modules/LogAnalyticsApi.psm1") -Force
Import-Module -Name ($PSScriptRoot + "/../modules/MgGraphApi.psm1") -Force

# [CONFIG] Entra セキュリティグループ ID を環境変数から取得します。
# ハードコーディングを避けることで、コードを変更せずに異なる環境で関数を再利用できます。
$groupId = $env:TARGET_GROUP_ID
if (-not $groupId) {
    # 必須の設定がない場合は、明確なエラーで処理を停止します。
    throw "環境変数 'TARGET_GROUP_ID' が設定されていません。"
}

# HTTPレスポンスのデフォルトステータスコードを設定します。
$statusCode = [HttpStatusCode]::OK
$responseBody = ""

try {
    # 1. リクエストボディから Log Analytics の検索結果 API の URI を取得します。
    # このURIは、アラートのコンテキストに含まれています。
    $logAnalyticsUri = $Request.Body.data.alertContext.condition.allOf.linkToSearchResultsAPI
    if (-not $logAnalyticsUri) {
        # 必要なURIが見つからない場合は、エラーをスローして処理を中断します。
        throw "リクエストボディに 'linkToSearchResultsAPI' が含まれていません。"
    }
    Write-Information "Log Analytics API の URI を取得しました: $logAnalyticsUri"

    # 2. LogAnalyticsApi モジュールの関数を呼び出して、API アクセストークンを取得します。
    # この関数は、ローカル開発環境とAzure環境（マネージドID）の両方に対応しています。
    Write-Verbose "Log Analytics API のアクセストークンを取得しています..."
    $accessToken = Get-LogAnalyticsAccessToken -Verbose
    Write-Verbose "アクセストークンの取得に成功しました。"

    # 3. 取得したトークンとURIを使って、Log Analytics API にクエリを実行します。
    Write-Verbose "Log Analytics API にクエリを実行しています..."
    $apiResponse = Invoke-LogAnalyticsQuery -QueryUri $logAnalyticsUri -AccessToken $accessToken -Verbose

    # 4. APIの応答からユーザーIDのリストを作成します。
    # Log Analytics の結果はネストされた配列になっているため、適切に展開します。
    # ForEach-Object を使用して、より簡潔で PowerShell らしい方法でリストを生成します。
    $userIdList = if ($apiResponse.tables[0].rows) {
        $apiResponse.tables[0].rows | ForEach-Object { [string]$_[0] }
    } else {
        @() # 処理対象がない場合は空の配列を返す
    }

    # 5. 処理対象のユーザーがいる場合のみ、Graph API 処理を実行します。
    if ($userIdList.Count -gt 0) {
        # 処理対象のユーザーIDをログに出力します。IDのリストが長くなる可能性がある点に注意してください。
        Write-Information "グループに追加するユーザー ($($userIdList.Count) 件): $($userIdList -join ', ')"

        # Microsoft Graph に接続します。
        Write-Verbose "Microsoft Graph に接続しています..."
        Connect-MgGraphApi -Verbose
        Write-Verbose "Microsoft Graph への接続に成功しました。"

        # ユーザーリストをグループに追加します。
        Add-MgGroupMemberBulk -GroupId $groupId -UserIdList $userIdList -Verbose

        $responseBody = @{
            status  = "Success"
            message = "グループメンバーの更新処理が完了しました。"
            usersProcessed = $userIdList.Count
        }
    }
    else {
        Write-Information "Log Analytics のクエリ結果に処理対象のユーザーは含まれていませんでした。"
        $responseBody = @{
            status  = "Success"
            message = "処理対象のユーザーがいなかったため、処理をスキップしました。"
            usersProcessed = 0
        }
    }
}
catch {
    # エラーが発生した場合は、ログに出力し、ステータスコードを500に設定します。
    Write-Error "関数の実行中にエラーが発生しました: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    $statusCode = [HttpStatusCode]::InternalServerError
    $responseBody = @{
        status  = "Error"
        message = $_.Exception.Message
    }
}

# 関数の実行結果をHTTPレスポンスとして返します。
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body       = ($responseBody | ConvertTo-Json -Depth 3)
    Headers    = @{ "Content-Type" = "application/json; charset=utf-8" }
})
