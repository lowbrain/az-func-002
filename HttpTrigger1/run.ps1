using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

try {
    # Azure サービスのリソース URI を指定してローカル エンドポイントからトークンを取得
    $resourceURI = "https://api.loganalytics.io"
    $tokenAuthURI = $env:IDENTITY_ENDPOINT + "?resource=$resourceURI&api-version=2019-08-01"
    $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER"="$env:IDENTITY_HEADER"} -Uri $tokenAuthURI
    $accessToken = $tokenResponse.access_token

    Write-Host "Successfully acquired access token."

    $apiRequestHeader = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "application/json"
    }

    $logAnalyticsUri = $Request.Body.data.alertContext.condition.allOf.linkToSearchResultsAPI

    Write-Host "Querying Log Analytics API at $logAnalyticsUri"

    $apiResponse = Invoke-RestMethod -Method GET -Headers $apiRequestHeader -Uri $logAnalyticsUri 
    @($apiResponse.tables.rows) | ForEach-Object {
       Write-Host "UserId: $_[0]"
    }

    $statusCode = [HttpStatusCode]::OK
}
catch {
    Write-Error $_.Exception.Message
    $statusCode = [HttpStatusCode]::InternalServerError
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
})
