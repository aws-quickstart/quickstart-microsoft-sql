try {
    $newdisk = get-disk | where partitionstyle -eq 'raw'

    foreach ($d in $newdisk){
        $disknum = $d.Number
        Initialize-Disk -Number $disknum -PartitionStyle GPT
        Set-Disk -Number $disknum -IsReadOnly $False
        New-Partition -DiskNumber $disknum -UseMaximumSize -AssignDriveLetter
    }
}
catch {
    $_ | Write-AWSQuickStartException
}