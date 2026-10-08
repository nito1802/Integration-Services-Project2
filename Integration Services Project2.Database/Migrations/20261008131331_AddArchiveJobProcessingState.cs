using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IntegrationServicesProject2.Database.Migrations;

public partial class AddArchiveJobProcessingState : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Widen date to datetime2; preserve existing dates and all job records.
        migrationBuilder.AlterColumn<DateTime>(
            name: "LastSuccesProcessedAt", schema: "Archive", table: "ArchiveJobs",
            type: "datetime2", nullable: true, oldClrType: typeof(DateOnly), oldType: "date");
        migrationBuilder.AddColumn<string>(
            name: "DateColumn", schema: "Archive", table: "ArchiveJobs",
            type: "nvarchar(128)", maxLength: 128, nullable: false, defaultValue: "CreatedAt");
        migrationBuilder.AddColumn<string>(
            name: "ErrorMessage", schema: "Archive", table: "ArchiveJobs",
            type: "nvarchar(max)", nullable: true);
        migrationBuilder.AddColumn<DateTime>(
            name: "LastProcessedAt", schema: "Archive", table: "ArchiveJobs",
            type: "datetime2", nullable: true);
        migrationBuilder.AddColumn<string>(
            name: "LastProcessedStatus", schema: "Archive", table: "ArchiveJobs",
            type: "nvarchar(16)", maxLength: 16, nullable: true);
        // The original seed used schema labels as DatabaseName. Normalize only those two known entries.
        migrationBuilder.Sql("UPDATE [Archive].[ArchiveJobs] SET [DatabaseName]=DB_NAME() WHERE ([DatabaseName]=N'MyData' AND [TableName]=N'MyData.Snapshots') OR ([DatabaseName]=N'SmartHome' AND [TableName]=N'SmartHome.Events');");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "DateColumn", schema: "Archive", table: "ArchiveJobs");
        migrationBuilder.DropColumn(name: "ErrorMessage", schema: "Archive", table: "ArchiveJobs");
        migrationBuilder.DropColumn(name: "LastProcessedAt", schema: "Archive", table: "ArchiveJobs");
        migrationBuilder.DropColumn(name: "LastProcessedStatus", schema: "Archive", table: "ArchiveJobs");
        migrationBuilder.AlterColumn<DateOnly>(
            name: "LastSuccesProcessedAt", schema: "Archive", table: "ArchiveJobs",
            type: "date", nullable: false, defaultValue: new DateOnly(1, 1, 1),
            oldClrType: typeof(DateTime), oldType: "datetime2", oldNullable: true);
    }
}