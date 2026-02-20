<#
RoadMap Architecture:

    1. Expand Template-Achitecture Logic
        - Add into template .json  Folder Mappings - done
        - Each Folder Needs: a global Type from the TypeList 
        - Each Type Accepts defined File Extensions only (With Override functions) - done
        - There can be more Mapping rules. - done
        - The Connection between Mappings and Template are n to n - done
        - We to define a path for each type. 
        - Final: Get it production ready 

    2. Create a Drive Detection Engine
        - Function to automatically detect removable drives like Cameras, SD Cards, Thumb Drives etc
        for convenience --> Generate a List for User in CLI and let him confirm it 
        - Check for Volume Name (TypeList with common camera names etc. --> Extra Function to 
        manage this whitelist) Appdata -> RenderKit -> detectlist.json or .txt --> 
        - Check for Format System of the Drive (TypeList for common Format System for SD cards, cameras etc)
        I need to Do some research about this topic
        - Create a Function to expand the WhiteList with SerialNumber = Once Mapped -> Its saved in AppData config
        You never need to map your drive again
        - WhiteLists are always in AppData (Appdata -> RenderKit -> Devices.json)

    3. ACTUALLY Build an Import-Engine in 6 Phases: 
        Phase 1 - Detect Source 
            - Show all the potencial Drives, that we detected in Step 2. 
            - Get the Confirmation / Correction from User in a sexy CLI UX
            - If it shows broken things, let the user give the actual absolute path
        Phase 2 - Scan & Filter
            - First things first -> We scan the whole Drive with [System.IO.DirectoryInfo]
            - We Filter --> Folder --> Time Range --> Wildcard --> Combination all of it 
            - We Return the Results and let the user decide what he wants to import
            - The User has still the option do define his own filters 
            - If the Criteria are defined --> List a sexy UI Table with the contents that are 
            goint to be imported 
            - We let the User confirm the import 
        Phase 3 - Classification
            - Now we know what to import, and where to import
            but we don't know that type where to import
            - We Iterate through every file and check the file extension
            - We search for the Template-Mapping for that file extension
            - Now we search for the Folder type that includes the extension 
            and read out the folder name as a path
            - If we don't find a mapping for an extension we classify it as "unassigned"
            - After the Iteration we ask the user how to Handle unassigned File Types 
            With a List of destination folders from the Project Folder (sexy UI ofc.)
            with the option to skip it after the import
        Phase 4 - Transaction-Safe Transfer
            - This is the most critical step, since we don't want to fk up raw Footage from the User.
            - We Copy to a .renderkit\import-temp 
            - We calculate a hash 
            - We compare the hash 
            - If hash == hash we move from temp to final location
            - If we have an error, we delete the rollback temp
        Phase 5 - Logging & Revision
            - Create ".renderkit/import-2026-02-12.log"
            With these Information: StartTime, SourceDrive, FileCount, Hash, Destination,
            User, Template, Template Version, RenderKitVersion, json Schema version, 
            and maybe some other fancy stuff that is relevant for revision
        Phase 6 - Final Report
            - Finally we create an import summary with: 
                - Count.Files Imported
                - Total Size in GB
                - Duration
                - Average Copy Speed 
                - Sum of unassigned files (handled / unhandled)
                - Implement a Progressbar (PS Native)
                    - Sum of Bytes 
                    - Already copied bytes
                    - avg. speed

    4. Potential nice to have Features after the implementations of all above
        - SHA256 Manifest
        - Duplicate Detection
        - Pause / Resume Import 
        - Device Registry
        - Camera Profiles (Folder Structure / Import efficiency)

#>
function Import-Media{
    [CmdletBinding()]
    param(
        [switch]$SelectSource,
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    if ($SelectSource) {
        return Select-RenderKitDriveCandidate `
            -IncludeFixed:$IncludeFixed `
            -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem
    }

    return Get-RenderKitDriveCandidate `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem
}
