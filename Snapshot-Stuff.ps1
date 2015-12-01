<#
    .SYNOPSIS
    Collect Application Configuration Snapshots from the current host and publish via a specified provider.

    .DESCRIPTION
    Orchestrate the collection and publishing of application configuration states to a JSON snapshot representation. Uses standard application install locations to determine applications 
    that are installed on the server. 

    .PARAMETER AgentPropertiesFile
    An optional properties file used to setup the snapshot agent.  If this is not specified, a default configuration will be used.

    .OUTPUT
    Nothing

    .EXAMPLE
    Get-ApplicationSnapshots -AgentPropertiesFile C:\snapshot-agent.properties
    Discovers the applications installed on the executing host using the properties defined in the file "C:\snapshot-agent.properties"

    .EXAMPLE
    Get-ApplicationSnapshots
    Discovers the applications installed on the executing host using the default properties (this is generally appropriate for server use)

#>
[CmdletBinding()]
Param
(
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string] $AgentPropertiesFile = $null
)

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

# check if snapshot path env var is set, if not try to determine it
if(!(Test-Path Env:\APS_SNAPSHOT_PATH))
{
   $env:APS_SNAPSHOT_PATH = Get-ScriptDirectory
}

# import base modules
Import-Module $env:APS_SNAPSHOT_PATH\ConfigurationSnapshot.psm1 
Import-Module $env:APS_SNAPSHOT_PATH\ConfigurationSnapshotProperties.psm1

# this can be done better, will fix eventually
$CONF_DIR = "$env:APS_SNAPSHOT_PATH\..\conf"
$Script:DISCOVERY_ROOT = "D:\"

function Read-AgentProperties
{
    <#
        .SYNOPSIS
        Reads agent properties from the specified file (or provides defaults if file parameter is null).
        
        .DESCRIPTION
        If the file specified by the ConfFile parameter exists, reads the properties defined there into a a property hash which is returned. If the file path parameter is null or otherwise
        not valid, the function will return hash containing a set of default properties
        
        .PARAMETER ConfFile
        An optional path to a configuration file to be used to setup the logger.  If this is not provided either a set of default properties will be defined
        
        .OUTPUTS
        A System.Collections.Hashtable containing the name/value pairs representing the agent properties.
        
        .EXAMPLE
        Read-AgentProperties -ConfFile C:\snapshot-agent.properties
        Returns a new property set based on the properties defined in the file "C:\snapshot-agent.properties" (assuming the file exists and contains valid property definitions)
    #>
    [CmdletBinding()]
    Param
    (
         [Parameter(Mandatory=$false)]
         [string] $ConfFile = $null
    )

    if($ConfFile -eq $null -or $ConfFile.Length -lt 1)
    {
        $ConfFile = "$env:APS_SNAPSHOT_PATH\..\conf\agent.properties"
    }

    $Properties = @{}

    
    
    if(!(Test-Path $ConfFile))
    {
        $Properties.Add("agent.publish.provider", "FILE") # default to file
        $Properties.Add("agent.publish.url", "\\sentry.com\appfs_nonprod\AppServices\Snapshot\PublishQueue") 
        $Properties.Add("agent.discovery.root", "D:\")
    }
    else
    {
        $Properties = ConvertFrom-StringData -StringData (Get-Content -Raw -Path $ConfFile)
    }

    return $Properties

}

function Find-Java-Web-Properties
{
    <#
        .SYNOPSIS
        Finds installed Java Web applications on the current host
        
        .DESCRIPTION
        Returns an array of properties representing the Java Web applications on the current host
        
        .PARAMETER PropertyArray
        An optional array of previously discovered applications.  If this is not provided the function will initialize an empty array
        
        .PARAMETER DiscoveryRoot
        The base path from which to begin searching for installed applications (typically this is D:\ on a server or C:\ for local testing)

        .OUTPUTS
        An array of System.Collections.Hashtable objects containing properties representing the passed in PropertyArray parameter joined with the newly
        discovered applications (this may be empty if not applications of the given type were discovered)
        
        .EXAMPLE
        Find-Java-Web-Properties -PropertyArray $ArrayOfOtherApplications -DiscoveryRoot 'C:\'
        Searches for Java Web applications installed under 'C:\' in the standard install locations (i.e. C:\tomcat-applications) and combines the results with the provided $ArrayOfOtherApplications
        array to create the return array value
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [alias("PropertyArray")] $propArray = @(),
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $DiscoveryRoot    
    )

    $dpath = $DiscoveryRoot + "tomcat-applications"
    if(!(Test-Path $dpath))
    {
        return $propArray
    }
    $dir = Get-ChildItem -Path $dpath -Directory
    
    foreach($d in $dir)
    {
        $props = @{}
        $props.Add("application.platform", "JAVA")
        $props.Add("application.type", "WEB")
        $props.Add("application.key", $d.Name)
        $props.Add("instance.uri", $d.FullName)
        $props.Add("instance.key", $d.Name)
        $propArray += $props
    }
    return $propArray
}

function Find-Java-Service-Properties
{
    <#
        .SYNOPSIS
        Finds installed Java Service applications on the current host
        
        .DESCRIPTION
        Returns an array of properties representing the Java Service applications on the current host
        
        .PARAMETER PropertyArray
        An optional array of previously discovered applications.  If this is not provided the function will initialize an empty array
        
        .PARAMETER DiscoveryRoot
        The base path from which to begin searching for installed applications (typically this is D:\ on a server or C:\ for local testing)

        .OUTPUTS
        An array of System.Collections.Hashtable objects containing properties representing the passed in PropertyArray parameter joined with the newly
        discovered applications (this may be empty if not applications of the given type were discovered)
        
        .EXAMPLE
        Find-Java-Service-Properties -PropertyArray $ArrayOfOtherApplications -DiscoveryRoot 'C:\'
        Searches for Java Service applications installed under 'C:\' in the standard install locations (i.e. C:\javasvc-applications) and combines the results with the provided $ArrayOfOtherApplications
        array to create the return array value
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [alias("PropertyArray")] $propArray = @(),
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $DiscoveryRoot    
    )

    $dpath = $DiscoveryRoot + "javasvc-applications"
    if(!(Test-Path $dpath))
    {
        return $propArray
    }
    $dir = Get-ChildItem -Path $dpath -Directory

    [System.Collections.ArrayList] $pl = New-Object System.Collections.ArrayList(0)
    if($propArray.Length -gt 0)
    {
        foreach($p in $propArray)
        {
            $pl.Add($p) | Out-Null
        }
    }

    foreach($d in $dir)
    {
        #write-host discovering $d.name
        $props = @{}
        $props.Add("application.platform", "JAVA")
        $props.Add("application.type", "SERVICE")
        $props.Add("application.key", $d.Name)
        $props.Add("instance.uri", $d.FullName)
        if($props.ContainsKey("instance.key"))
        {
            write-host "How did this happen"
        }
        else
        {
            $props.Add("instance.key", $d.Name)
        }

        $pl.Add($props) | Out-Null

    }
    [System.Array] $propArray = [System.Array] $pl
    return $propArray
}

function Find-Java-Batch-Properties
{
    <#
        .SYNOPSIS
        Finds installed Java Batch applications on the current host
        
        .DESCRIPTION
        Returns an array of properties representing the Java Batch applications on the current host
        
        .PARAMETER PropertyArray
        An optional array of previously discovered applications.  If this is not provided the function will initialize an empty array
        
        .PARAMETER DiscoveryRoot
        The base path from which to begin searching for installed applications (typically this is D:\ on a server or C:\ for local testing)

        .OUTPUTS
        An array of System.Collections.Hashtable objects containing properties representing the passed in PropertyArray parameter joined with the newly
        discovered applications (this may be empty if not applications of the given type were discovered)
        
        .EXAMPLE
        Find-Java-Batch-Properties -PropertyArray $ArrayOfOtherApplications -DiscoveryRoot 'C:\'
        Searches for Java Batch applications installed under 'C:\' in the standard install locations (i.e. C:\javabat-applications) and combines the results with the provided $ArrayOfOtherApplications
        array to create the return array value
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [alias("PropertyArray")] $propArray = @(),
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $DiscoveryRoot    
    )

    $dpath = $DiscoveryRoot + "javabat-applications"
    if(!(Test-Path $dpath))
    {
        return $propArray
    }
    $dir = Get-ChildItem -Path $dpath -Directory

    [System.Collections.ArrayList] $pl = New-Object System.Collections.ArrayList(0)
    if($propArray.Length -gt 0)
    {
        foreach($p in $propArray)
        {
            $pl.Add($p) | Out-Null
        }
    }

    foreach($d in $dir)
    {
        #write-host discovering $d.name
        $props = @{}
        $props.Add("application.platform", "JAVA")
        $props.Add("application.type", "BATCH")
        $props.Add("application.key", $d.Name)
        $props.Add("instance.uri", $d.FullName)

        if($props.ContainsKey("instance.key"))
        {
            Write-Error "How did this happen"
        }
        else
        {
            $props.Add("instance.key", $d.Name)
        }
        $pl.Add($props) | Out-Null
    }
    [System.Array] $propArray = [System.Array] $pl
    return $propArray
}

function Check-IgnoreList
{
    Param
    (
        $List,
        $Uri
    )
    foreach($i in $list)
    {
        #make case insensitive?
        if($i -eq $uri)
        {
            return $true
        }
    }
    return $false
}


## MAIN ##
$AgentProps = Read-AgentProperties -ConfFile $AgentPropertiesFile


if($AgentProps.ContainsKey('agent.discovery.root'))
{
    $Script:DISCOVERY_ROOT = $AgentProps.'agent.discovery.root'
}

$dir = Get-ChildItem -Path $CONF_DIR -File -Filter *.properties
$declaredProps = @()
foreach($file in $dir)
{
    $p = Init-Properties -File $file.FullName
    $declaredProps += $p
}

$derivedProps = @()
$derivedProps = Find-Java-Web-Properties -PropertyArray $derivedProps -DiscoveryRoot $Script:DISCOVERY_ROOT
$derivedProps = Find-Java-Service-Properties -PropertyArray $derivedProps -DiscoveryRoot $Script:DISCOVERY_ROOT
$derivedProps = Find-Java-Batch-Properties -PropertyArray $derivedProps -DiscoveryRoot $Script:DISCOVERY_ROOT

$ignore = ""
if(Test-Path $CONF_DIR\ignore.txt)
{
    $ignore = Get-Content $CONF_DIR\ignore.txt
}
[System.Collections.ArrayList] $props = @()
foreach($derived in $derivedProps)
{
    $addProp = $derived
    foreach($declared in $declaredProps)
    {
              
        if($derived.Get_Item("instance.uri") -eq $declared.Get_Item("instance.uri"))
        {
            $addProp = $declared # defer to declared properties when a conflict is found
            #write-host "A Conflict is found!"
        }
    }
    $doIgnore = Check-IgnoreList -List $ignore -Uri $addProp.Get_Item("instance.uri")
    if(!$doIgnore)
    {
        $index = $props.Add($addProp)
    }    
    else
    {
        Write-Host "Ignorning " + $addProp.Get_Item("instance.uri")
    }
}
#exit
$version = New-SnapshotVersion
foreach($prop in $props)
{
    # add snapshot client version to properties
    $versionString = "0.0.0" # default value when no version is defined (should only be for local dev)
    $clientVersionPath = (Get-ScriptDirectory) + "\version.txt"
    if(Test-Path $clientVersionPath)
    {
        $versionString = Get-Content -Path $clientVersionPath
    }
    $prop.Add("snapshot.client.version", $versionString)

    #$props | ConvertTo-Json
    if($prop."application.platform" -eq "JAVA")
    {
        if($prop."application.type" -eq "SITE")
        {

            $ss = Get-Snapshot-TomcatContext -Properties $prop
            foreach($s in $ss) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }

            $s1 = Get-Snapshot-JavaServiceParams -Properties $prop 
            Publish-Snapshot -Snapshot $s1 -PublishProperties $AgentProps

            $s2 = Get-Snapshot-WindowsService -Properties $prop
            Publish-Snapshot -Snapshot $s2 -PublishProperties $AgentProps
            
            $sJCA = Get-Snapshot-JavaCodeArchive -Properties $prop
            foreach($s in $sJCA) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }

            $sProp = Get-Snapshot-PropertyFile -Properties $prop
            foreach($s in $sProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }
            
            $secProp = Get-Snapshot-SecurePropertyFile -Properties $prop
            foreach($s in $secProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }
            
            $codeProp = Get-Snapshot-CodePropertyFile -Properties $prop
            foreach($s in $codeProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }

            $runParamsSnap = Get-Snapshot-RunParamsFile -Properties $prop
            Publish-Snapshot -Snapshot $runParamsSnap -PublishProperties $AgentProps

            $certs = Get-Snapshot-CertificateFile -Properties $prop
            foreach($c in $certs) { Publish-Snapshot -Snapshot $c -PublishProperties $AgentProps }
            
        }
        elseif($prop."application.type" -eq "SERVICE")
        {
        
            $s1 = Get-Snapshot-JavaServiceParams -Properties $prop 
            Publish-Snapshot -Snapshot $s1 -PublishProperties $AgentProps

            $s2 = Get-Snapshot-WindowsService -Properties $prop
            Publish-Snapshot -Snapshot $s2 -PublishProperties $AgentProps
            
            $sJCA = Get-Snapshot-JavaCodeArchive -Properties $prop
            foreach($s in $sJCA) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }

            $sProp = Get-Snapshot-PropertyFile -Properties $prop
            foreach($s in $sProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }

            $secProp = Get-Snapshot-SecurePropertyFile -Properties $prop
            foreach($s in $secProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }
            
            $runParamsSnap = Get-Snapshot-RunParamsFile -Properties $prop
            Publish-Snapshot -Snapshot $runParamsSnap -PublishProperties $AgentProps

            $codeProp = Get-Snapshot-CodePropertyFile -Properties $prop
            foreach($s in $codeProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }
        }
        elseif($prop."application.type" -eq "BATCH")
        {     
            $sProp = Get-Snapshot-PropertyFile -Properties $prop
            foreach($s in $sProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }

            $secProp = Get-Snapshot-SecurePropertyFile -Properties $prop
            foreach($s in $secProp) { Publish-Snapshot -Snapshot $s -PublishProperties $AgentProps }
            
            $runParamsSnap = Get-Snapshot-RunParamsFile -Properties $prop
            Publish-Snapshot -Snapshot $runParamsSnap -PublishProperties $AgentProps
        }
    }
}
