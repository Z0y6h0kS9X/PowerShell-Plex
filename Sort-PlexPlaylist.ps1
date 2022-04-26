<#


Objective: Get the playlist info, sort the items and create a new list called "LISTNAME-Sorted"


#>

param(
	[PSCredential]
	$Credential,

	[string]
	$plexServerName,

	[string]
	$serverHostName,

	[ValidateSet('http','https')]
	[string]
	$serverProtocol,

	[int]
	$serverPort,

	[string]
	$userName,

	[string]
	$playList

)

#region FUNCTIONS

FUNCTION Get-PlexServerData
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[PSCredential]
		$Credential
	)

	#Converts provided credential to Base64 for easier sending to endpoint
	$Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Credential.GetNetworkCredential().UserName, $Credential.GetNetworkCredential().Password)));

	#Creates headers for accessing Plex
	$Data = Invoke-RestMethod -Uri "https://plex.tv/users/sign_in.json" -Method POST -Headers @{
		'Authorization'            = ("Basic {0}" -f $Base64AuthInfo);
		'X-Plex-Client-Identifier' = "PowerShellAccess";
		'X-Plex-Product'           = 'PoSH4Plex';
		'X-Plex-Version'           = "V1.0";
		'X-Plex-Username'          = $Credential.GetNetworkCredential().UserName;
		}

	#Stores information to an object
	$PlexServerData = [PSCustomObject]@{
		'Username' = $Data.user.username
		'Token'    = $Data.user.authentication_token
		'AddedOn'  = $(Get-Date -Format 's')
	}

	#returns the object to the function call
	return $PlexServerData

}

FUNCTION Get-PlexUsers
{
	param (
		[Parameter(Mandatory = $true)]
		[PSCustomObject]
		$plexConfig
	)

	Write-Host "Gathering user(s)..." -ForegroundColor Yellow

	$users = New-Object System.Collections.ArrayList

	#Gets raw user info
	$Data = Invoke-RestMethod -Uri "https://plex.tv/api/users`?X-Plex-Token=$($plexConfig.Token)" -Method GET

	#refines user info
	foreach ( $user in ( $Data.MediaContainer.user | Select-Object -Property id,email,username,@{N='machineID'; E={$_.Server.machineIdentifier}},token ) )
	{
		[void]$users.Add( $user )
	}

	#Adds Server Owner info
	[void]$users.Add( (
		New-Object psobject -Property ( [ordered]@{
			id        = 1;
			email     = 'Server Owner';
			username  = $plexConfig.UserName;
			machineID = $users[0].machineID;
			token     = $plexConfig.token; 
		} )
	) )

	#Gets the user tokens for the users

		#we use the user machineID rather than the global machineID in order to get non-admin users' tokens - hence $users[0].machineID rather than $Data.MediaContainer.machineIdentifier
		$Data = ( Invoke-RestMethod -Uri "https://plex.tv/api/servers/$($users[0].machineID)/access_tokens.xml?auth_token=$($plexConfig.Token)&includeProfiles=1&includeProviders=1" ).access_tokens.access_token

		foreach ( $user in $users )
		{

			#Grabs first valid user token for an object
			$token = ( $Data | Where-Object { $_.username -match $user.username } | Select-Object -First 1 ).token
			#Adds token to the user
			$user.token = $token

		}


	return $users
	 
}

FUNCTION Get-Choice
{
	
	param (
		[string]
		$Title,

		[array]
		$list
	)

	Write-Host $Title
	Write-Host "===================================="

	$i = 0

	if ( ( ($list | Get-Member -MemberType Properties).Count ) -gt 1 ) #array has multiple columsn specified
	{
		for ( $i = 0; $i -lt $list.Count; $i++ )
		{

			#In case multiple items are passed in, it will separate them with a | character
			$output = ( ($list | Get-Member -MemberType Properties).Name | ForEach-Object { $list[$i].$_ } ) -join ' | '
			
			Write-Host "[$($i)]: $($output)"

		}
	}
	else #array only has 1 element per entry
	{

		for ( $i = 0; $i -lt $list.Count; $i++ )
		{
			
			Write-Host "[$($i)]: $($list[$i])"

		}

	}
	

	do {

		$response = Read-Host -Prompt "Enter the number of the selection you want, or press 'Q' to exit"
		
	} until ( !$response -or $response -match 'q' -or ( [int]::Parse( $response ) -lt  $list.Count ) ) #keeps executing unitl valid input is detected

	if ( $response -match 'q' )
	{
		$response = -1
	}
	
	return $response

}

FUNCTION Get-Playlist
{

	param (
		[psobject]
		$user,

		[psobject]
		$plexConfig
	)

	Write-Host "Gathering playlist(s)..." -ForegroundColor Yellow

	#Gets the data from the site and converts it into a usable object
	$Data = Invoke-WebRequest -Uri "$($plexConfig.Protocol)://$($plexConfig.HostName):$($plexConfig.Port)/playlists/?X-Plex-Token=$($user.Token)"
	[xml]$UTF8String = [system.Text.Encoding]::UTF8.GetString($Data.RawContentStream.ToArray())
	$Results = $UTF8String.MediaContainer.Playlist
	
	#Goes through each playlist and adds the tracks to it
	foreach($Playlist in $Results)
	{
		$RestEndpoint = "playlists/$($Playlist.ratingKey)/items"
		Write-Verbose -Message "Function: $($MyInvocation.MyCommand): Appending playlist item(s)"
		try
		{
			[array]$Items = Invoke-RestMethod -Uri "$($plexConfig.Protocol)://$($plexConfig.HostName)`:$($plexConfig.Port)/$RestEndpoint`?`X-Plex-Token=$($user.Token)" -ErrorAction Stop
			$Playlist | Add-Member -NotePropertyName 'Tracks' -NotePropertyValue $Items.MediaContainer.Track
		}
		catch
		{
			throw $_
		}
	}

	return $Results

}

FUNCTION Add-Playlist
{

	param (
		[psobject]
		$user,

		[string]
		$playlistTitle,

		[psobject]
		$PlexConfig,

		[array]
		$tracks
	)

	#Converts array of tracks into a comma separated list, which is needed to pass through here
	$trackList = $tracks -join ","

	#Creates the playlist
	$Data = Invoke-RestMethod -Uri "$($PlexConfig.Protocol)://$($PlexConfig.HostName):$($PlexConfig.Port)/playlists?uri=server://$($user.machineID)/com.plexapp.plugins.library/library/metadata/$($trackList)&title=$($playlistTitle)&smart=0&type=audio&X-Plex-Token=$($user.Token)" -Method "POST"

	$response = $Data.MediaContainer.Playlist

	return $response
}

#endregion

Write-Host "Generating Plex Config" -ForegroundColor Yellow

IF (!$Credential){ $Credential = Get-Credential }

$PlexConfigData = Get-PlexServerData -Credential $Credential

	#Checks to see if server hostname was supplied, if not - prompts for it
	if ([string]::IsNullOrEmpty($serverHostName))
	{
		do {
			
			Write-Host "Plex Server's Host Name not supplied." -ForegroundColor Yellow
			$serverHostName = Read-Host -Prompt "Please Enter the Plex Server's Host Name"

		} while ( [string]::IsNullOrEmpty($serverHostName) )
		
	}

	#Checks to see if the plex server name was supplied, if not - prompts for it
	if ([string]::IsNullOrEmpty($plexServerName))
	{
		do {

			Write-Host "Plex Server Name not supplied." -ForegroundColor Yellow
			$plexServerName = Read-Host -Prompt "Please Enter the Plex Server Name"

		} while ( [string]::IsNullOrEmpty($plexServerName) )
		
	}

	#Checks to see if protocol was supplied, if not - prompts for it
	if ([string]::IsNullOrEmpty($serverProtocol))
	{
		do {

			Write-Host "Protocol for the Plex Server was not supplied (http/https)." -ForegroundColor Yellow
			$serverProtocol = Read-Host -Prompt "Please Enter the Plex Server Protocol (http/https)"
			
		} while ( [string]::IsNullOrEmpty($serverProtocol) -and $serverProtocol -notmatch 'http|https' )

	}

	#Checks to see if port was supplied, if not - prompts for it
	if ( $serverPort -eq 0 -or $null -eq $serverPort )
	{
		do {

			Write-Host "Port for the Plex Server was not supplied." -ForegroundColor Yellow
			$serverPort = Read-Host -Prompt "Please Enter the Plex Server Port"
			
		} while ( $serverPort -eq 0 -or $null -eq $serverPort )
		
	}

$PlexConfigData | Add-Member -MemberType NoteProperty -Name Protocol   -Value $serverProtocol
$PlexConfigData | Add-Member -MemberType NoteProperty -Name HostName   -Value $serverHostName
$PlexConfigData | Add-Member -MemberType NoteProperty -Name ServerName -Value $plexServerName
$PlexConfigData | Add-Member -MemberType NoteProperty -Name Port       -Value $serverPort

$users = Get-PlexUsers -plexConfig $PlexConfigData 

#if no username is specified initially, or it is specified but there is no match, prompts for selection
if ( !$userName -or !( $users | Where-Object { $_.username -match $userName } ) )
{ 
	$choice = Get-Choice -Title "Select the user you want to list playlists for" -list ( $users | Select-Object -Property email,username )
	#Gets the information for the user selected
	$user = $users[$choice]

	if ( $choice -eq -1 )
	{
		Write-Host "No User Selected, Exiting Script"
		BREAK
	}

}
else #if username was specified, sets the object here
{
	$user = $users | Where-Object { $_.username -match $userName }
}

#Gets the playlists for the user selected
$playLists = Get-Playlist -user $user -plexConfig $PlexConfigData

if ( !$playList -or !( $playLists | Where-Object { $_.title -match $playList } )  )
{

	#Gets the playlist choice
	$choice = Get-Choice -Title "Select the playlist you want to sort" -list $playLists.title

	if ( $choice -eq -1 )
	{
		Write-Host "No Playlist Selected, Exiting Script"
		BREAK
	}

	$playlistChoice = $playLists[$choice]	

}
else 
{
	$playlistChoice = $playLists | Where-Object { $_.title -match $playList }
}

#Sorts the list of tracks (ratingkeys)
$playlistChoice.Tracks = $playlistChoice.Tracks | Sort-Object -Property title

Add-Playlist -user $user -plexConfig $PlexConfigData -playlistTitle "$($playLists[$choice].title) - Sorted" -tracks ( ($playLists[$choice].Tracks).ratingKey )


