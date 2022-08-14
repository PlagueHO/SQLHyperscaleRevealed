# These tags are used to deterine which resource groups to delete.
$resource_tags = @{ environment = 'SQL Hyperscale Reveaeled demo' }

# Find all the resource groups that match the resource_tags
$resource_groups = Get-AzResourceGroup -Tag $resource_tags
if ($resource_groups) {
    $confirm = Read-Host -Prompt "The following SQL Hyperscale Revealed demonstration resource groups will be deleted: '$($resource_groups.ResourceGroupName -join ''', ''')'. Confirm by typing 'yes' and pressing enter"

    if ($confirm -eq 'yes') {
        $resource_group_deleted_count = 0
        $resource_groups | Foreach-Object -Process {
            Write-Progress -Activity "Deleting the SQL Hyperscale Revealed demonstration resource group '$($_.ResourceGroupName)'" -PercentComplete ($resource_group_deleted_count / ($resource_groups.Count - 1) * 100) -Status "Deleting '$($_.ResourceGroupName)'"
            Remove-AzResourceGroup -Name $_.ResourceGroupName -Force -Confirm:$true | Out-Null
            $resource_group_deleted_count++
        }

        Write-Verbose -Message "The SQL Hyperscale Revealed demonstration resource groups '$($resource_groups.ResourceGroupName -join ''', ''')' have been deleted." -Verbose

    } else {
        Write-Verbose -Message "User declined to delete the SQL Hyperscale Revealed demonstration resource groups '$($resource_groups.ResourceGroupName -join ''', ''')'." -Verbose
    }
} else {
    Write-Verbose -Message 'There are no SQL Hyperscale Revealed demonstration resource groups to delete.' -Verbose
}
