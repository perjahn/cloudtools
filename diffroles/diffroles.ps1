#!/usr/bin/env pwsh

Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main([string[]] $mainargs) {
  [string] $usage = "Usage: ./diffroles.ps1 [-onlydiff] [-login] <subscriptions...>"

  if (!$mainargs -or $mainargs.Count -eq 0) {
    Write-Host $usage
    exit 1
  }

  [bool] $onlydiff = $false
  [bool] $login = $false

  [string[]] $parsedArgs = @()

  for ([int] $i = 0; $i -lt $mainargs.Count; $i++) {
    if ($mainargs[$i] -eq '-onlydiff') {
      $onlydiff = $true
    }
    elseif ($mainargs[$i] -eq '-login') {
      $login = $true
    }
    else {
      $parsedArgs += $mainargs[$i]
    }
  }

  if ($login) {
    Connect-AzAccount -UseDeviceAuthentication | Out-Null
  }

  [string[]] $allsubscriptions = Get-AzSubscription | % { $_.Name }
  if (!$allsubscriptions) {
    Write-Host "Couldn't get subscriptions (use Connect-AzAccount or -login flag)." -f Red
    exit 1
  }

  Write-Host "Got $($allsubscriptions.Count) total subscriptions." -f Cyan

  [string[]] $subscriptions = @()

  for ([int] $i = 0; $i -lt $parsedArgs.Count; $i++) {
    foreach ($allsubscription in $allsubscriptions) {
      if ($allsubscription -like $parsedArgs[$i]) {
        $subscriptions += $allsubscription
      }
    }
  }

  if ($subscriptions.Count -eq 0) {
    Write-Host "Didn't find any subscriptions." -f Cyan
    exit 1
  }

  $subscriptions = $subscriptions | Sort-Object

  Write-Host "Filtered to $($subscriptions.Count) subscriptions." -f Cyan

  $allroles = @()
  foreach ($subscription in $subscriptions) {
    [string] $filename = $subscription.ToLower() + ".txt"
    $roles = @(GetRoles $subscription $filename)
    foreach ($role in $roles) {
      $role | Add-Member NoteProperty "Subscription" $subscription
      $allroles += $role
    }
  }

  Write-Host "Got $($allroles.Count) total role assigments." -f Cyan

  [string[]] $allids = @()
  foreach ($role in $allroles) {
    [string] $id = $role.DisplayName + "/" + $role.RoleDefinitionName

    if ($allids -notcontains $id) {
      $allids += $id
    }
  }

  Write-Host "Got $($allids.Count) user role assigments." -f Cyan

  $rolesubs = @()
  foreach ($id in $allids) {
    $rolesub = New-Object PSObject
    $rolesub | Add-Member NoteProperty "User/Role" $id

    foreach ($subscription in $subscriptions) {
      [bool] $found = $false
      foreach ($role in $allroles) {
        if ((($role.DisplayName + "/" + $role.RoleDefinitionName) -eq $id) -and ($role.Subscription -eq $subscription)) {
          $found = $true
        }
      }
      if ($found) {
        $rolesub | Add-Member NoteProperty $subscription.ToLower() "x"
      }
      else {
        $rolesub | Add-Member NoteProperty $subscription.ToLower() $null
      }
    }

    $rolesubs += $rolesub
  }

  Write-Host "Got $($rolesubs.Count) user role assignments." -f Cyan

  if ($onlydiff) {
    $rolesubs = @(HideUserRolesAssignments $rolesubs $subscriptions)
  }

  Write-Host "Filtered to $($rolesubs.Count) user role assignments." -f Cyan

  $rolesubs | Sort-Object "User/Role" | ft
}

function GetRoles([string] $subscription, [string] $filename) {
  Set-AzContext -Subscription $subscription | Out-Null

  $roles = Get-AzRoleAssignment
  Write-Host "Got $($roles.Count) role assignments in subscription: '$subscription'" -f Cyan
  #SaveCleanFile $roles $filename

  $roles
}

function SaveCleanFile($roles, [string] $filename) {
  [string] $tmpfile = "./tmp.txt"
  $roles > $tmpfile
  Get-Content $tmpfile | % { $_ -replace '\x1b\[\d+(;\d+)?m' } > $filename
}

function HideUserRolesAssignments($rolesubs, [string[]] $subscriptions) {
  $rolesubs | ? {
    [bool] $empty = $false
    foreach ($subscription in $subscriptions) {
      [string] $qq = $subscription.ToLower()
      if (!$_.$qq) {
        $empty = $true
      }
    }
    $empty
  }
}

Main $args
