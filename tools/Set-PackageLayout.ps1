param([string]$Path=(Join-Path (Split-Path $PSScriptRoot -Parent) 'Integration Services Project2\Package.dtsx'))
$ErrorActionPreference='Stop'
$xml=New-Object Xml.XmlDocument
$xml.PreserveWhitespace=$true
$xml.Load($Path)
$ns=New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
foreach($old in @($xml.SelectNodes('//DTS:DesignTimeProperties',$ns))) { [void]$old.ParentNode.RemoveChild($old) }
$runtime=$xml.OuterXml
$layout=New-Object Text.StringBuilder
[void]$layout.AppendLine(@'
<Objects Version="8">
  <Package design-time-name="Package">
    <LayoutInfo>
      <GraphLayout xmlns="clr-namespace:Microsoft.SqlServer.IntegrationServices.Designer.Model.Serialization;assembly=Microsoft.SqlServer.IntegrationServices.Graph">
'@)
function Place($id,$x,$y,$width=210,$height=46,$container=$false) {
    if(!$xml.SelectSingleNode('//DTS:Executable[@DTS:refId="'+$id+'"]',$ns)) { throw "Missing task: $id" }
    $escaped=[Security.SecurityElement]::Escape($id)
    if($container) {
        [void]$layout.AppendLine("        <ContainerLayout Id=`"$escaped`" TopLeft=`"$x,$y`" Size=`"$width,$height`" HeaderHeight=`"43`" IsExpanded=`"True`" PanelSize=`"$width,$($height-43)`" />")
    } else {
        [void]$layout.AppendLine("        <NodeLayout Id=`"$escaped`" TopLeft=`"$x,$y`" Size=`"$width,$height`" />")
    }
}
# Coordinates are relative to the containing graph/panel.
Place 'Package\Get Archive Jobs' 32 24
Place 'Package\Foreach Loop Container' 32 120 1100 830 $true
Place 'Package\Archive summary' 32 1010
$jobs='Package\Foreach Loop Container'
Place "$jobs\Start archive job" 28 24
Place "$jobs\Prepare archive job" 294 24
Place "$jobs\BeginScript" 560 24
Place "$jobs\Count days diff" 560 120
Place "$jobs\GetGuid" 294 120
Place "$jobs\For Loop Container" 72 220 980 450 $true
Place "$jobs\SetTableStatus" 294 720
Place "$jobs\Report archive job" 560 720
$days="$jobs\For Loop Container"
Place "$days\Get DateTo" 24 24
Place "$days\Loop through 1000" 72 110 870 280 $true
$batch="$days\Loop through 1000"
Place "$batch\Construct SQL" 24 24 180
Place "$batch\Read archive batch" 236 24 180
Place "$batch\Export data to CSV" 448 24 180
Place "$batch\Prepare batch delete" 660 24 180
Place "$batch\Create batch key table" 660 156 180
Place "$batch\Stage batch keys" 448 156 180
Place "$batch\Delete exported batch" 236 156 180
Place "$batch\Check deleted rows" 24 156 180
[void]$layout.AppendLine(@'
      </GraphLayout>
    </LayoutInfo>
  </Package>
</Objects>
'@)
$design=$xml.CreateElement('DTS','DesignTimeProperties','www.microsoft.com/SqlServer/Dts')
[void]$design.AppendChild($xml.CreateCDataSection($layout.ToString()))
[void]$xml.DocumentElement.AppendChild($design)
$xml.Save($Path)
# Assert that only designer metadata changed.
$check=New-Object Xml.XmlDocument; $check.PreserveWhitespace=$true; $check.Load($Path)
$checkNs=New-Object Xml.XmlNamespaceManager($check.NameTable); $checkNs.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
$node=$check.SelectSingleNode('/DTS:Executable/DTS:DesignTimeProperties',$checkNs)
[void]$node.ParentNode.RemoveChild($node)
if($check.OuterXml -ne $runtime) { throw 'Runtime XML changed unexpectedly' }
Write-Output "Updated designer layout only: $Path"
