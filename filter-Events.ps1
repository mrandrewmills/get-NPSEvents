<#
.SYNOPSIS
Retrieves matching National Park Service events in page, count, or grab mode.

.DESCRIPTION
Calls the NPS Public Data API /events endpoint. Page mode writes one requested
page of event records. Count mode reports the total matches and estimated pages.
Grab mode writes all matching event records, retrieving up to 50 per request.

The API key is read from the NPS_API_KEY environment variable and sent in the
X-Api-Key request header. The key is never written to the pipeline or output.

Array-valued filters are accepted as PowerShell string arrays and sent as
comma-delimited query values, consistent with the endpoint parameter
descriptions.

.PARAMETER ParkCode
Comma-delimited park codes to filter by.

.PARAMETER Organization
Comma-delimited organization site codes to filter by.

.PARAMETER Subject
Comma-delimited subject site codes to filter by.

.PARAMETER Portal
Comma-delimited portal site codes to filter by.

.PARAMETER TagsAll
Comma-delimited tags that every matching event must include.

.PARAMETER TagsOne
Comma-delimited tags of which a matching event may include one or more.

.PARAMETER TagsNone
Comma-delimited tags that matching events must not include.

.PARAMETER StateCode
Comma-delimited two-character state codes to filter by.

.PARAMETER DateStart
Starting date filter in yyyy-MM-dd format.

.PARAMETER DateEnd
Ending date filter in yyyy-MM-dd format.

.PARAMETER EventType
Comma-delimited event types to filter by.

.PARAMETER Id
Unique event ID to filter by.

.PARAMETER Q
Search term.

.PARAMETER PageSize
Requested number of results per page. The API currently returns no more than
50 records per page, regardless of a larger value. Used in Page mode; defaults
to 10. Count mode requests one record and estimates pages using 50 records per
page. Grab mode requests 50 records per page.

.PARAMETER PageNumber
Page number to retrieve in Page mode. Defaults to 1.

.PARAMETER Mode
Operation to perform. Page retrieves one page and is the default. Count reports
the total matches and estimated number of 50-record pages. Grab retrieves all
matching records in 50-record pages.

.PARAMETER ExpandRecurring
Whether to expand recurring events into separate date-specific records.
Defaults to false.

.EXAMPLE
$env:NPS_API_KEY = 'your-api-key'
.\filter-Events.ps1 -TagsOne 'America 250', 'Freedom 250' -DateStart '2024-01-01' |
    Select-Object category, datestart, parkfullname, sitecode, title, types, id

.EXAMPLE
.\filter-Events.ps1 -ParkCode 'abli', 'cacl' -PageSize 50 -PageNumber 2

.EXAMPLE
.\filter-Events.ps1 -Mode Count -TagsOne 'America 250', 'Freedom 250'

.EXAMPLE
.\filter-Events.ps1 -Mode Grab -TagsOne 'America 250', 'Freedom 250' |
    Export-Csv -LiteralPath .\events.csv -NoTypeInformation
#>
[CmdletBinding()]
param(
    [ValidateSet('Page', 'Count', 'Grab')]
    [string] $Mode = 'Page',
    [string[]] $ParkCode,
    [string[]] $Organization,
    [string[]] $Subject,
    [string[]] $Portal,
    [string[]] $TagsAll,
    [string[]] $TagsOne,
    [string[]] $TagsNone,
    [string[]] $StateCode,
    [string] $DateStart,
    [string] $DateEnd,
    [string[]] $EventType,
    [string] $Id,
    [string] $Q,
    [ValidateRange(1, [int]::MaxValue)]
    [int] $PageSize = 10,
    [ValidateRange(1, [int]::MaxValue)]
    [int] $PageNumber = 1,
    [bool] $ExpandRecurring = $false
)

$ErrorActionPreference = 'Stop'

$apiKey = [Environment]::GetEnvironmentVariable('NPS_API_KEY')
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'The NPS_API_KEY environment variable is not set or is empty.'
}

$queryParameters = [ordered]@{}
$arrayParameters = [ordered]@{
    parkCode    = $ParkCode
    organization = $Organization
    subject     = $Subject
    portal      = $Portal
    tagsAll     = $TagsAll
    tagsOne     = $TagsOne
    tagsNone    = $TagsNone
    stateCode   = $StateCode
    eventType   = $EventType
}

foreach ($parameter in $arrayParameters.GetEnumerator()) {
    if ($null -ne $parameter.Value -and $parameter.Value.Count -gt 0) {
        $queryParameters[$parameter.Key] = $parameter.Value -join ','
    }
}

if (-not [string]::IsNullOrWhiteSpace($DateStart)) {
    $queryParameters.dateStart = $DateStart
}
if (-not [string]::IsNullOrWhiteSpace($DateEnd)) {
    $queryParameters.dateEnd = $DateEnd
}
if (-not [string]::IsNullOrWhiteSpace($Id)) {
    $queryParameters.id = $Id
}
if (-not [string]::IsNullOrWhiteSpace($Q)) {
    $queryParameters.q = $Q
}

function Invoke-EventsRequest {
    param(
        [int] $RequestedPageSize,
        [int] $RequestedPageNumber
    )

    $requestParameters = [ordered]@{}
    foreach ($parameter in $queryParameters.GetEnumerator()) {
        $requestParameters[$parameter.Key] = $parameter.Value
    }
    $requestParameters.pageSize = $RequestedPageSize
    $requestParameters.pageNumber = $RequestedPageNumber
    $requestParameters.expandRecurring = $ExpandRecurring.ToString().ToLowerInvariant()

    $queryString = ($requestParameters.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f [Uri]::EscapeDataString([string]$_.Key), [Uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
    $uri = "https://developer.nps.gov/api/v1/events?$queryString"

    Invoke-RestMethod -Method Get -Uri $uri -Headers @{ 'X-Api-Key' = $apiKey } -ErrorAction Stop
}

function Get-EventsTotal {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Response,
        [Parameter(Mandatory)]
        [int] $Page
    )

    if ($null -eq $Response -or $null -eq $Response.total) {
        throw "The NPS API response for page $Page did not include a total."
    }

    $totalText = [string]$Response.total
    if ($totalText -notmatch '^\d+$') {
        throw "The NPS API returned an invalid total on page ${Page}: '$totalText'."
    }
    [long]::Parse($totalText, [Globalization.CultureInfo]::InvariantCulture)
}

switch ($Mode) {
    'Page' {
        $response = Invoke-EventsRequest -RequestedPageSize $PageSize -RequestedPageNumber $PageNumber
        if ($null -eq $response -or $null -eq $response.data) {
            throw 'The NPS API response did not include event data.'
        }

        foreach ($eventRecord in $response.data) {
            Write-Output $eventRecord
        }
    }
    'Count' {
        $response = Invoke-EventsRequest -RequestedPageSize 1 -RequestedPageNumber 1
        $total = Get-EventsTotal -Response $response -Page 1

        [pscustomobject][ordered]@{
            TotalMatches       = $total
            EstimatedPageSize  = 50
            EstimatedPageCount = [long][Math]::Ceiling($total / 50.0)
        }
    }
    'Grab' {
        $total = $null
        [long]$retrieved = 0
        $pageNumber = 1

        do {
            $response = Invoke-EventsRequest -RequestedPageSize 50 -RequestedPageNumber $pageNumber
            $pageTotal = Get-EventsTotal -Response $response -Page $pageNumber
            if ($null -eq $total) {
                $total = $pageTotal
            } elseif ($pageTotal -ne $total) {
                throw "The NPS API total changed from $total to $pageTotal while fetching page $pageNumber."
            }

            $pageEvents = @()
            if ($null -ne $response.data) {
                $pageEvents = @($response.data)
            }
            if ($pageEvents.Count -eq 0 -and $retrieved -lt $total) {
                throw "The NPS API returned no events on page $pageNumber before all $total matching events were retrieved."
            }
            if (($retrieved + $pageEvents.Count) -gt $total) {
                throw "The NPS API returned more events than the reported total of $total."
            }

            foreach ($eventRecord in $pageEvents) {
                Write-Output $eventRecord
            }
            $retrieved += $pageEvents.Count
            $pageNumber++
        } while ($retrieved -lt $total)

        if ($retrieved -ne $total) {
            throw "Retrieved $retrieved events, but the API reported $total."
        }
    }
}
