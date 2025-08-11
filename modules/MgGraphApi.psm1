# Microsoft Graph への接続を確立する関数
<#
.SYNOPSIS
    Microsoft Graph への接続を確立します。
.DESCRIPTION
    実行環境（ローカル開発 or Azure Functions）を自動的に判別し、適切な認証方法（サービスプリンシパル or マネージドID）を使用して Microsoft Graph への接続を確立します。
.EXAMPLE
    Connect-MgGraphApi -Verbose
    ローカル開発環境で、詳細なログを出力しながら Graph API に接続します。
#>
function Connect-MgGraphApi {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Microsoft Graph に接続しています..."
        if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) {
            # ローカル開発環境 (サービスプリンシパル認証)
            Write-Verbose "ローカル開発環境として実行中。サービスプリンシパルを使用して接続します。"
            Connect-MgGraph -NoWelcome -EnvironmentVariable -ErrorAction Stop
        }
        else {
            # Azure 環境 (マネージドID認証)
            Write-Verbose "Azure環境として実行中。マネージドIDを使用して接続します。"
            Connect-MgGraph -NoWelcome -Identity -ErrorAction Stop
        }
        Write-Verbose "Microsoft Graph への接続に成功しました。"
    }
    catch {
        Write-Error "Microsoft Graph への接続に失敗しました: $($_.Exception.Message)"
        throw
    }
}

# 指定されたグループに複数のユーザーを効率的に追加する関数
<#
.SYNOPSIS
    指定されたグループに複数のユーザーを効率的に追加します。
.DESCRIPTION
    まずグループの既存メンバーをすべて取得し、追加対象のユーザーリストと比較します。
    まだメンバーでないユーザーのみを、一人ずつグループに追加します。
    ユーザーの追加に失敗した場合は、警告を出力して次のユーザーの処理を続行します。
.PARAMETER GroupId
    ユーザーを追加する対象の Entra ID グループのID。
.PARAMETER UserIdList
    追加するユーザーのIDを含む文字列の配列。
.EXAMPLE
    $users = "user-guid-1", "user-guid-2"
    Add-MgGroupMemberBulk -GroupId "group-guid" -UserIdList $users -Verbose
    指定されたグループに2人のユーザーを追加します。既に追加済みのユーザーはスキップされます。
#>
function Add-MgGroupMemberBulk {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string[]]$UserIdList
    )

    try {
        Write-Verbose "グループ '$($GroupId)' の既存メンバーを取得しています..."
        # 既存のメンバーIDをすべて取得し、高速な検索のためにハッシュセットに格納する
        $existingMembers = Get-MgGroupMember -GroupId $GroupId -All -ErrorAction Stop | Select-Object -ExpandProperty Id
        $existingMemberSet = [System.Collections.Generic.HashSet[string]]::new($existingMembers)
        Write-Verbose "$($existingMemberSet.Count) 人の既存メンバーが見つかりました。"

        # 追加対象のユーザーリストから、まだメンバーでないユーザーを抽出する
        $usersToAdd = $UserIdList | Where-Object { -not $existingMemberSet.Contains($_) }

        if ($usersToAdd.Count -eq 0) {
            Write-Verbose "グループに追加する新規ユーザーはいません。"
            return
        }

        Write-Verbose "$($usersToAdd.Count) 人のユーザーをグループに追加します。"

        foreach ($userId in $usersToAdd) {
            try {
                Write-Verbose "ユーザー '$userId' をグループ '$GroupId' に追加しています。"
                # -ErrorAction Stop を指定して、APIエラーを catch ブロックで確実に捕捉する
                New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $userId -ErrorAction Stop
            }
            catch {
                # 一人のユーザー追加に失敗しても処理を止めず、警告を出力してループを継続する
                Write-Warning "ユーザー '$userId' のグループへの追加に失敗しました: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Error "グループへのメンバー追加処理中に致命的なエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

# 関数をモジュールのメンバーとしてエクスポートする
Export-ModuleMember -Function Connect-MgGraphApi, Add-MgGroupMemberBulk