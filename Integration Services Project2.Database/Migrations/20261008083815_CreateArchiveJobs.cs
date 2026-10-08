using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace IntegrationServicesProject2.Database.Migrations
{
    /// <inheritdoc />
    public partial class CreateArchiveJobs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "Archive");

            migrationBuilder.CreateTable(
                name: "ArchiveJobs",
                schema: "Archive",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    DatabaseName = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    TableName = table.Column<string>(type: "nvarchar(257)", maxLength: 257, nullable: false),
                    LastSuccesProcessedAt = table.Column<DateOnly>(type: "date", nullable: false),
                    ArchiveOlderThanDays = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ArchiveJobs", x => x.Id);
                });

            migrationBuilder.InsertData(
                schema: "Archive",
                table: "ArchiveJobs",
                columns: new[] { "Id", "ArchiveOlderThanDays", "DatabaseName", "LastSuccesProcessedAt", "TableName" },
                values: new object[,]
                {
                    { 1, 90, "MyData", new DateOnly(2026, 9, 29), "MyData.Snapshots" },
                    { 2, 30, "SmartHome", new DateOnly(2026, 10, 3), "SmartHome.Events" },
                    { 3, 180, "SalesDemo", new DateOnly(2026, 9, 15), "dbo.Orders" },
                    { 4, 60, "WarehouseDemo", new DateOnly(2026, 10, 1), "audit.StockMovements" },
                    { 5, 14, "TelemetryDemo", new DateOnly(2026, 9, 22), "dbo.Readings" },
                    { 6, 365, "SupportDemo", new DateOnly(2026, 8, 31), "dbo.Tickets" },
                    { 7, 120, "PaymentsDemo", new DateOnly(2026, 10, 5), "audit.Transactions" },
                    { 8, 7, "LogsDemo", new DateOnly(2026, 10, 7), "dbo.ApplicationLogs" }
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ArchiveJobs",
                schema: "Archive");
        }
    }
}
