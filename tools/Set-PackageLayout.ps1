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
# Coordinates are relative to the containing panel.
Place 'Package\Initialize run log' 32 24
Place 'Package\Prepare job queries' 310 24
Place 'Package\Prepare archive execution lock' 590 24
Place 'Package\Acquire archive execution lock' 32 120
Place 'Package\Load archive jobs' 310 120
Place 'Package\For each archive job' 32 216 1100 2600 $true
Place 'Package\Release archive execution lock' 32 2900
Place 'Package\Check overall archive result' 310 2900
$jobs='Package\For each archive job'
Place "$jobs\Mark job as started" 28 24
Place "$jobs\Initialize job variables" 294 24
Place "$jobs\Prepare metadata and date queries" 560 24
Place "$jobs\Read column definitions" 826 24
Place "$jobs\Read SQL types and keys" 826 140
Place "$jobs\Prepare export schema and header" 560 140
Place "$jobs\Prepare FK validation queries" 28 240
Place "$jobs\Load configured job relations" 294 240
Place "$jobs\Read foreign key definitions" 560 240
Place "$jobs\Validate archive relations" 826 240
Place "$jobs\Calculate retention cutoff" 294 350
Place "$jobs\Find first archive day" 560 350
Place "$jobs\For each archive day" 28 460 1030 1900 $true
$daily="$jobs\For each archive day"
Place "$daily\Prepare related archive group" 24 24
Place "$daily\Stage parent day" 340 24
Place "$daily\Load archive members" 656 24
Place "$daily\Plan archive graph" 656 85
Place "$daily\Validate archive plan relations" 340 85
Place "$daily\For each archive member" 24 180 970 1100 $true
$member="$daily\For each archive member"
Place "$member\Prepare archive member" 24 24
Place "$member\Read member column definitions" 340 24
Place "$member\Read member SQL types and keys" 656 24
Place "$member\Prepare member export schema" 656 150
Place "$member\Initialize daily archive" 340 150
Place "$member\Drop previous member snapshot" 24 150
Place "$member\Stage archive day" 24 230
Place "$member\Process daily batches" 24 300 920 150 $true
Place "$member\Verify exported day" 24 530
Place "$member\Create daily ZIP" 340 530
Place "$member\Verify ZIP integrity" 656 530
Place "$member\Publish verified archive" 24 700
Place "$member\Collect archive member deletion" 656 700
Place "$member\Collect ZIP process diagnostics" 340 700
Place "$daily\Prepare group deletion" 24 1320
Place "$daily\Refresh foreign keys before deletion" 340 1320
Place "$daily\Validate relations before deletion" 656 1320
Place "$daily\Delete archived day" 24 1470
Place "$daily\Finalize successful archives" 340 1470
Place "$daily\Find next archive day" 656 1470
Place "$jobs\Save job result" 294 2440
Place "$jobs\Log job result" 560 2440
$batch="$member\Process daily batches"
Place "$batch\Prepare batch select query" 24 24 240
Place "$batch\Read archive batch" 330 24 240
Place "$batch\Write batch to CSV" 636 24 240
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
