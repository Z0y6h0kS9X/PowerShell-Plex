# PowerShell-Plex
Scripts for working with Plex Media Server using PowerShell

# Sort-Playlist

This is a script that will allow you to alphabetically sort the items inside of a user's playlist and create a new playlist named '#playlistName#-Sorted' to prevent potential data loss.

## What do I need to run it?

This makes a few assumptions - namely, that you are the server admin and know the following information:
1. Protocol you communicate with your plex server on (http/https).
2. You know the hostname/IP of the computer hosting your server.
3. You know the port your Plex Server is listening on.
4. Basic familiarity with working with a command line.

## How to run it?
Using powershell navigate to the directory containing the file and run it .\Sort-Playlist.ps1

## Variables
Required - Variable Name  - Type         - Description
------------------------------------------------------
1. Yes      - Credential     - PSCredential - A credential object, easily generating by running 'Get-Credential' and supplying your credentials. 
2. Yes      - plexServerName - string       - The name of the Plex server (myPlexServer, etc.).
3. Yes      - serverHostName - string       - IP or HostName of the computer where Plex Media Server is installed.
4. Yes      - serverProtocol - string       - What protocol (http or https) that you connect to your server on.
5. Yes      - serverPort     - int          - Port Number that Plex is listening on (default 32400)
6. No       - userName       - string       - Username of the user you want to sort playlists for
6. No       - playList       - string       - Title of the playlist you want to sort

