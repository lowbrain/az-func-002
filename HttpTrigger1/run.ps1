using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host $Request.Body
Write-Host $Request.Body.data
Write-Host $Request.Body.data.alertContext
Write-Host $Request.Body.data.alertContext.condition
Write-Host $Request.Body.data.alertContext.condition.allOf
Write-Host $Request.Body.data.alertContext.condition.allOf.linkToSearchResultsAPI
Write-Host $env:IDENTITY_ENDPOINT
Write-Host $env:IDENTITY_HEADER

# Interact with query parameters or the body of the request.
$name = $Request.Query.Name
if (-not $name) {
    $name = $Request.Body.Name
}

$body = "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response."

if ($name) {
    $body = "Hello, $name. This HTTP triggered function executed successfully."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
