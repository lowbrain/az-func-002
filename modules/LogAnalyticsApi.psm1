# [定数] Log Analytics API のリソース URI
$script:resourceURI = "https://api.loganalytics.io"

# Log Analytics API のアクセストークンを取得する関数
<#
.SYNOPSIS
    Log Analytics API のアクセストークンを取得します。
.DESCRIPTION
    実行環境（ローカル開発 or Azure Functions）を自動的に判別し、適切な認証方法（サービスプリンシパル or マネージドID）を使用して Log Analytics API のアクセストークンを取得します。
.EXAMPLE
    $token = Get-LogAnalyticsAccessToken -Verbose
    ローカル開発環境で、詳細なログを出力しながらアクセストークンを取得します。
.OUTPUTS
    System.String
    成功した場合は、Log Analytics API のアクセストークンを返します。
    失敗した場合は、例外をスローします。
#>
function Get-LogAnalyticsAccessToken {
    [CmdletBinding()]
    param()

    try {
        # マネージドIDの環境変数がない場合 (ローカルでの開発環境を想定)
        if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) {
            # クライアント資格情報を使用してトークンを取得
            Write-Verbose "ローカル開発環境として実行中。クライアント資格情報を使用してトークンを取得します。"
            $tokenAuthURI = "https://login.microsoftonline.com/$($env:AZURE_TENANT_ID)/oauth2/token"
            $tokenBody = @{
                grant_type    = "client_credentials"
                client_id     = $env:AZURE_CLIENT_ID
                client_secret = $env:AZURE_CLIENT_SECRET
                resource      = $script:resourceURI
            }
            $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenAuthURI -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        }
        # マネージドIDの環境変数がある場合 (Azure上での実行環境を想定)
        else {
            # マネージドIDを使用してトークンを取得
            Write-Verbose "Azure環境として実行中。マネージドIDを使用してトークンを取得します。"
            $tokenAuthURI = $env:IDENTITY_ENDPOINT + "?resource=$($script:resourceURI)&api-version=2019-08-01"
            $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER" = "$env:IDENTITY_HEADER" } -Uri $tokenAuthURI -ErrorAction Stop
        }

        return $tokenResponse.access_token
    }
    catch {
        Write-Error "Log Analytics API のアクセストークンの取得に失敗しました: $($_.Exception.Message)"
        # 例外を再スローして、呼び出し元にエラーを通知する
        throw
    }
}

# Log Analytics API を呼び出してクエリ結果を取得する関数
<#
.SYNOPSIS
    Log Analytics API を呼び出してクエリ結果を取得します。
.DESCRIPTION
    指定されたクエリURIとアクセストークンを使用して、Log Analytics API を呼び出し、その結果を返します。
.PARAMETER QueryUri
    クエリを実行するための Log Analytics API の完全なURI。
.PARAMETER AccessToken
    APIを認証するためのベアラートークン。
.EXAMPLE
    $response = Invoke-LogAnalyticsQuery -QueryUri "https://api.loganalytics.io/v1/workspaces/{ws-id}/query" -AccessToken $token
    指定されたURIとトークンで Log Analytics API を呼び出します。
.OUTPUTS
    PSCustomObject
    成功した場合は、Log Analytics API からの応答オブジェクトを返します。
    失敗した場合は、例外をスローします。
#>
function Invoke-LogAnalyticsQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$QueryUri,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    try {
        # API を呼び出すためのヘッダーを作成
        $apiRequestHeader = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = "application/json"
        }

        Write-Verbose "Log Analytics API にクエリを送信しています: $QueryUri"
        # Log Analytics API を呼び出す
        return Invoke-RestMethod -Method Get -Headers $apiRequestHeader -Uri $QueryUri -ErrorAction Stop
    }
    catch {
        Write-Error "Log Analytics API のクエリ実行に失敗しました: $($_.Exception.Message)"
        # 例外を再スローして、呼び出し元にエラーを通知する
        throw
    }
}

# 関数をモジュールのメンバーとしてエクスポートする
Export-ModuleMember -Function Get-LogAnalyticsAccessToken, Invoke-LogAnalyticsQuery