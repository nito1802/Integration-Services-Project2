param([switch]$MainConfiguration)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($MainConfiguration) {
    $sourcePackage=[xml](Get-Content -LiteralPath (Join-Path $root 'Integration Services Project2\Package.dtsx') -Raw)
    $sourceNs=New-Object Xml.XmlNamespaceManager($sourcePackage.NameTable); $sourceNs.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
    $config=[pscustomobject]@{
        RunDirectory=(Join-Path $root 'verification\main-run')
        ConnectionString=$sourcePackage.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="ConnectionString"]/DTS:Property[@DTS:Name="ParameterValue"]',$sourceNs).InnerText
        ArchiveRoot=$sourcePackage.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="ArchiveRoot"]/DTS:Property[@DTS:Name="ParameterValue"]',$sourceNs).InnerText
    }
} else {
    $config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification\latest-config.txt')) -Raw | ConvertFrom-Json
}
$testProject=Join-Path $config.RunDirectory 'designer-test'
[void](New-Item -ItemType Directory -Path $testProject -Force)
$package=[xml](Get-Content -LiteralPath (Join-Path $root 'Integration Services Project2\Package.dtsx') -Raw)
$ns=New-Object Xml.XmlNamespaceManager($package.NameTable); $ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
$package.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="ConnectionString"]/DTS:Property[@DTS:Name="ParameterValue"]',$ns).InnerText=$config.ConnectionString
$package.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="ArchiveRoot"]/DTS:Property[@DTS:Name="ParameterValue"]',$ns).InnerText=$config.ArchiveRoot
foreach($conn in $package.SelectNodes('//DTS:ConnectionManager/DTS:ObjectData/DTS:ConnectionManager',$ns)) { $conn.SetAttribute('ConnectionString','www.microsoft.com/SqlServer/Dts',$config.ConnectionString) | Out-Null }
$package.Save((Join-Path $testProject 'Package.dtsx'))
$project=[xml](Get-Content -LiteralPath (Join-Path $root 'Integration Services Project2\Integration Services Project2.dtproj') -Raw)
$pn=New-Object Xml.XmlNamespaceManager($project.NameTable); $pn.AddNamespace('SSIS','www.microsoft.com/SqlServer/SSIS')
$project.SelectSingleNode('//SSIS:Parameter[@SSIS:Name="ConnectionString"]/SSIS:Properties/SSIS:Property[@SSIS:Name="Value"]',$pn).InnerText=$config.ConnectionString
$project.Save((Join-Path $testProject 'Integration Services Project2.dtproj'))
Copy-Item -LiteralPath (Join-Path $root 'Integration Services Project2\Project.params'),(Join-Path $root 'Integration Services Project2\Integration Services Project2.database') -Destination $testProject
$solution=[xml](Get-Content -LiteralPath (Join-Path $root 'Integration Services Project2.slnx') -Raw)
foreach ($solutionProject in @($solution.Solution.Project)) {
    if ($solutionProject.GetAttribute('Path').EndsWith('.dtproj')) {
        $solutionProject.SetAttribute('Path','Integration Services Project2.dtproj')
    } else { [void]$solution.Solution.RemoveChild($solutionProject) }
}
$solution.Save((Join-Path $testProject 'Test.slnx'))
Write-Output (Join-Path $testProject 'Test.slnx')
