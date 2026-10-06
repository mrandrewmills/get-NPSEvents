# filter-Events.ps1

PowerShell script for querying the National Park Service (NPS) Public Data API `/events` endpoint and returning matching event records.

## Overview

`filter-Events.ps1` supports three modes:

- `Page` (default): returns one page of matching event records
- `Count`: returns the total number of matches plus the estimated page count
- `Grab`: retrieves all matching records across all pages

The script reads your API key from the `NPS_API_KEY` environment variable and sends it in the `X-Api-Key` header. It does not write the key to output.

## Prerequisites

- PowerShell 5.1+ or PowerShell 7+
- A valid NPS API key
- Internet access to `https://developer.nps.gov/api/v1/events`

## API key setup

Set the environment variable before running the script:

```powershell
$env:NPS_API_KEY = 'your-api-key'
```

You can also set this persistently in your Windows environment or PowerShell profile if desired.

## Usage

```powershell
./filter-Events.ps1 [parameters]
```

### Parameters

- `-Mode` : `Page`, `Count`, or `Grab` (default: `Page`)
- `-ParkCode` : One or more park codes
- `-Organization` : One or more organization codes
- `-Subject` : One or more subject codes
- `-Portal` : One or more portal codes
- `-TagsAll` : Tags that every result must include
- `-TagsOne` : Tags where one or more may match
- `-TagsNone` : Tags that matching results must not include
- `-StateCode` : One or more two-letter state codes
- `-DateStart` : Start date in `yyyy-MM-dd` format
- `-DateEnd` : End date in `yyyy-MM-dd` format
- `-EventType` : One or more event types
- `-Id` : A single event ID to match
- `-Q` : Search text
- `-PageSize` : Results per page (default: `10`; API caps at `50`)
- `-PageNumber` : Page number when using `-Mode Page` (default: `1`)
- `-ExpandRecurring` : `$true` or `$false` (default: `$false`)

Multiple values for array parameters are passed as comma-delimited query values, which matches the NPS API parameter conventions.

## Examples

### Get a page of events for a park

```powershell
$env:NPS_API_KEY = 'your-api-key'
./filter-Events.ps1 -ParkCode 'abli' -PageSize 10 -PageNumber 1
```

### Filter by tags and date range

```powershell
./filter-Events.ps1 -TagsOne 'America 250', 'Freedom 250' -DateStart '2024-01-01'
```

### Count matching events

```powershell
./filter-Events.ps1 -Mode Count -TagsOne 'America 250', 'Freedom 250'
```

### Grab all matching events and export to CSV

```powershell
./filter-Events.ps1 -Mode Grab -TagsOne 'America 250', 'Freedom 250' |
    Export-Csv -LiteralPath .\events.csv -NoTypeInformation
```

### Output a selected set of fields

```powershell
./filter-Events.ps1 -ParkCode 'abli', 'cacl' -PageSize 50 -PageNumber 2 |
    Select-Object category, datestart, parkfullname, sitecode, title, types, id
```

## Output

The script writes event objects from the NPS API to the pipeline:

- In `Page` mode, one page of event records is written
- In `Count` mode, a custom object with:
  - `TotalMatches`
  - `EstimatedPageSize`
  - `EstimatedPageCount`
- In `Grab` mode, every matching event record is written in sequence

## Notes

- The script uses `Invoke-RestMethod` to call the NPS API.
- In `Count` mode, the API is queried with a page size of 1 and the script estimates page totals using the API's documented page size of 50.
- In `Grab` mode, the script fetches pages of 50 records until all matching events are retrieved.
- If the API responds with unexpected totals or missing data, the script throws an error rather than silently returning incomplete results.

## Related files

- `filter-Events.ps1` — main script
