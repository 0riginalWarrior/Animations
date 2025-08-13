# Source folder with JSON files
$sourceFolder = "C:\Users\Felix\AppData\Local\Potassium\workspace\audio_logs"

# Destination file path for combined JSON
$destinationFile = "D:\RobloxEmotes\audios\combined_emotes.json"

# Prepare array to hold all emotes
$allEmotes = @()

# Get all JSON files
$jsonFiles = Get-ChildItem -Path $sourceFolder -Filter *.json

foreach ($file in $jsonFiles) {
    $jsonName = $file.BaseName

    # Read and parse JSON content
    $jsonContent = Get-Content -Path $file.FullName -Raw
    try {
        $jsonObject = $jsonContent | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to parse JSON in file $jsonName"
        continue
    }

    # Assume jsonObject is either:
    # 1) An array of emote objects, or
    # 2) An object with a key like "EmotesInfo" containing an array

    $emotes = @()
    if ($jsonObject -is [System.Array]) {
        $emotes = $jsonObject
    } elseif ($jsonObject.PSObject.Properties.Name -contains "EmotesInfo") {
        $emotes = $jsonObject.EmotesInfo
    } else {
        # If structure unknown, try treating whole object as single emote
        $emotes = @($jsonObject)
    }

    # For each emote, add the Name field with the JSON filename
    foreach ($emote in $emotes) {
        # Create a new hashtable so we don't modify original object
        $emoteDict = @{}

        foreach ($property in $emote.PSObject.Properties) {
            $emoteDict[$property.Name] = $property.Value
        }

        $emoteDict["Name"] = $jsonName

        # Add to allEmotes array
        $allEmotes += [PSCustomObject]$emoteDict
    }
}

# Create the final combined object
$combinedObject = @{
    EmotesInfo = $allEmotes
}

# Convert to JSON (with indentation)
$finalJson = $combinedObject | ConvertTo-Json -Depth 5 -Compress:$false

# Ensure destination folder exists
$destFolder = Split-Path $destinationFile
if (-not (Test-Path $destFolder)) {
    New-Item -ItemType Directory -Path $destFolder | Out-Null
}

# Save combined JSON to file
$finalJson | Out-File -FilePath $destinationFile -Encoding UTF8

Write-Output "Combined emotes saved to $destinationFile"
