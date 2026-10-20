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
      <GraphLayout xmlns="clr-namespace:Microsoft.SqlServer.IntegrationServices.Designer.Model.Serialization;assembly=Microsoft.SqlServer.IntegrationServices.Graph" xmlns:mssgle="clr-namespace:Microsoft.SqlServer.Graph.LayoutEngine;assembly=Microsoft.SqlServer.Graph" xmlns:assembly="http://schemas.microsoft.com/winfx/2006/xaml">
'@)
$positions=@{}
function Place($id,$x,$y,$width=210,$height=46,$container=$false) {
    if(!$xml.SelectSingleNode('//DTS:Executable[@DTS:refId="'+$id+'"]',$ns)) { throw "Missing task: $id" }
    $escaped=[Security.SecurityElement]::Escape($id)
    $positions[$id]=@{X=$x;Y=$y;W=$width;H=$height}
    if($container) {
        [void]$layout.AppendLine("        <ContainerLayout Id=`"$escaped`" TopLeft=`"$x,$y`" Size=`"$width,$height`" HeaderHeight=`"43`" IsExpanded=`"True`" PanelSize=`"$width,$($height-43)`" />")
    } else {
        [void]$layout.AppendLine("        <NodeLayout Id=`"$escaped`" TopLeft=`"$x,$y`" Size=`"$width,$height`" />")
    }
}
# Coordinates are relative to the containing graph/panel.
Place 'Package\Get Archive Jobs' 32 24
Place 'Package\Foreach Loop Container' 32 120 1000 660 $true
Place 'Package\Archive summary' 32 840
$jobs='Package\Foreach Loop Container'
Place "$jobs\Start archive job" 28 24
Place "$jobs\Prepare archive job" 294 24
Place "$jobs\BeginScript" 560 24
Place "$jobs\Get cutoff date" 560 120
Place "$jobs\GetGuid" 294 120
Place "$jobs\Loop through 1000" 72 220 870 280 $true
Place "$jobs\SetTableStatus" 294 550
Place "$jobs\Report archive job" 560 550
$batch="$jobs\Loop through 1000"
Place "$batch\Construct SQL" 24 24 180
Place "$batch\Read archive batch" 236 24 180
Place "$batch\Export data to CSV" 448 24 180
Place "$batch\Prepare batch delete" 660 24 180
Place "$batch\Create batch key table" 660 156 180
Place "$batch\Stage batch keys" 448 156 180
Place "$batch\Delete exported batch" 236 156 180
Place "$batch\Check deleted rows" 24 156 180
foreach($constraint in $xml.SelectNodes('//DTS:PrecedenceConstraint',$ns)) {
    $from=$positions[$constraint.GetAttribute('From',$ns.LookupNamespace('DTS'))]
    $to=$positions[$constraint.GetAttribute('To',$ns.LookupNamespace('DTS'))]
    if(!$from -or !$to) { throw 'Missing arrow endpoint layout' }
    $id=[Security.SecurityElement]::Escape($constraint.GetAttribute('refId',$ns.LookupNamespace('DTS')))
    if($from.Y -eq $to.Y) {
        $direction=if($to.X -gt $from.X) { 1 } else { -1 }
        $sx=if($direction -eq 1) { $from.X+$from.W } else { $from.X }
        $sy=$from.Y+$from.H/2
        $tx=if($direction -eq 1) { $to.X } else { $to.X+$to.W }
        $dx=$tx-$sx; $dy=0; $ex=$dx-7.5*$direction; $ey=0
        $segments="<mssgle:LineSegment End=`"$ex,$ey`" />"
    } else {
        $sx=$from.X+$from.W/2; $sy=$from.Y+$from.H
        $dx=$to.X+$to.W/2-$sx; $dy=$to.Y-$sy
        $ex=$dx; $ey=$dy-7.5; $mid=$dy/2
        $segments="<mssgle:LineSegment End=`"0,$mid`" /><mssgle:LineSegment End=`"$dx,$mid`" /><mssgle:LineSegment End=`"$ex,$ey`" />"
    }
    [void]$layout.AppendLine(@"
        <EdgeLayout Id="$id" TopLeft="$sx,$sy">
          <EdgeLayout.Curve>
            <mssgle:Curve StartConnector="{assembly:Null}" EndConnector="$dx,$dy" Start="0,0" End="$ex,$ey">
              <mssgle:Curve.Segments><mssgle:SegmentCollection>$segments</mssgle:SegmentCollection></mssgle:Curve.Segments>
            </mssgle:Curve>
          </EdgeLayout.Curve>
          <EdgeLayout.Labels><EdgeLabelCollection /></EdgeLayout.Labels>
        </EdgeLayout>
"@)
}
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
