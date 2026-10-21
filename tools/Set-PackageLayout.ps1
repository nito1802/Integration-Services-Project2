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
Place 'Package\Load archive jobs' 32 24
Place 'Package\For each archive job' 32 120 1100 1400 $true
Place 'Package\Check overall archive result' 32 1570
$jobs='Package\For each archive job'
Place "$jobs\Mark job as started" 28 24
Place "$jobs\Initialize job variables" 294 24
Place "$jobs\Prepare metadata and date queries" 560 24
Place "$jobs\Read column definitions" 826 24
Place "$jobs\Read SQL types and keys" 826 140
Place "$jobs\Prepare export schema and header" 560 140
Place "$jobs\Calculate retention cutoff" 294 140
Place "$jobs\Find first archive day" 294 260
Place "$jobs\For each archive day" 28 410 1030 810 $true
$daily="$jobs\For each archive day"
Place "$daily\Initialize daily archive" 24 24
Place "$daily\Stage archive day" 340 24
Place "$daily\Process daily batches" 24 130 950 150 $true
Place "$daily\Verify exported day" 24 340
Place "$daily\Create daily ZIP" 340 340
Place "$daily\Verify ZIP integrity" 656 340
Place "$daily\Delete archived day" 656 470
Place "$daily\Verify deleted row count" 340 470
Place "$daily\Drop staged day" 24 470
Place "$daily\Delete temporary CSV files" 24 620
Place "$jobs\Save job result" 294 1260
Place "$jobs\Log job result" 560 1260
$batch="$daily\Process daily batches"
Place "$batch\Prepare batch select query" 24 24 240
Place "$batch\Read archive batch" 340 24 240
Place "$batch\Write batch to CSV" 656 24 240
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
