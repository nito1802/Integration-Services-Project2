$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$helper=Get-Content (Join-Path $root 'scripts/Progress logging.cs') -Raw
$helper+="`n"+(Get-Content (Join-Path $root 'scripts/Summary logging.cs') -Raw)
$code=@'
using System;
using System.IO;
using System.Text;
using System.Globalization;
using System.Diagnostics;
using System.Collections.Generic;
public class LogBox { public object Value; }
public class LogEvents {
    public int Warnings;
    public void FireWarning(int code,string source,string message,string file,int line) { Warnings++; }
}
public class LogDts {
    public Dictionary<string,LogBox> Variables = new Dictionary<string,LogBox>();
    public LogEvents Events = new LogEvents();
}
public class ProgressLogProbe {
    public LogDts Dts = new LogDts();
    public ProgressLogProbe(string file) {
        Dts.Variables["User::RunLogFile"]=new LogBox {Value=file};
        Dts.Variables["User::RunSummaryFile"]=new LogBox {Value=file+".summary.txt"};
    }
    public void Write() { Progress("TEST", "Zażółć", "one\r\ntwo"); Summary("TEST", "Zażółć", "one\r\ntwo"); }
    public static void Verify(string file) {
        var first=new ProgressLogProbe(file);
        var second=new ProgressLogProbe(file);
        first.Write();
        using(var reader=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite | FileShare.Delete)) {
          using(var summaryReader=new FileStream(file+".summary.txt",FileMode.Open,FileAccess.Read,FileShare.ReadWrite | FileShare.Delete)) {
            long before=reader.Length;
            System.Threading.Tasks.Parallel.Invoke(
                () => { for(int i=0;i<100;i++) first.Write(); },
                () => { for(int i=0;i<100;i++) second.Write(); });
            if(reader.Length<=before) throw new Exception("Reader blocked appends");
            if(first.Dts.Events.Warnings+second.Dts.Events.Warnings!=0) throw new Exception("Write warning");
            var lines=File.ReadAllLines(file,Encoding.UTF8);
            if(lines.Length!=201) throw new Exception("Lost or broken log lines");
            foreach(var line in lines) if(!line.Contains("Zażółć") || !line.EndsWith("one\\r\\ntwo")) throw new Exception("Damaged log content");
            if(File.ReadAllLines(file+".summary.txt",Encoding.UTF8).Length!=201) throw new Exception("Summary lost lines");
          }
        }
        var invalid=new ProgressLogProbe(Path.Combine(file,"missing.txt"));
        invalid.Write();
        if(invalid.Dts.Events.Warnings!=2) throw new Exception("Log I/O failure did not become a warning");
    }
    // __HELPER__
}
'@
Add-Type -TypeDefinition ($code.Replace('// __HELPER__',$helper))
$folder=Join-Path $root 'artifacts/log-sharing'
[void](New-Item -ItemType Directory -Force $folder)
$file=Join-Path $folder ([guid]::NewGuid().ToString('N')+'.txt')
[ProgressLogProbe]::Verify($file)
Write-Output "PASS: 201 complete UTF-8 lines in both logs from concurrent writers while readers stayed open; log I/O failures became warnings. $file"
