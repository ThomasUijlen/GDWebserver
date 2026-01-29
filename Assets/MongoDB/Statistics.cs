using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

public partial class MongoDBAPI : Node
{
	public void getLiveData(string publicKey, Godot.Collections.Dictionary liveData)
	{
		_ = getLiveDataInternal(publicKey, liveData);
	}

	public async Task getLiveDataInternal(string publicKey, Godot.Collections.Dictionary liveData)
	{
		Godot.Collections.Dictionary data = await RetrieveDocumentsByIdSubstringAsync(
			"LiveData",
			publicKey,
			100,
			1,

false,
true
		);

		var d = await RetrieveAllDocumentIdsAsync(
			"LiveData"
		);
		foreach (string b in d)
		{
			if (b.Contains(publicKey))
				GD.Print(b);
		}

		Godot.Collections.Array documents = (Godot.Collections.Array)data["Documents"];

		int currentTime = (int)Time.GetUnixTimeFromSystem();
		long dataUsage = 0;
		int playerCount = 0;
		int lobbyCount = 0;

		foreach (Godot.Collections.Dictionary document in documents)
		{
			GD.Print(document);
			int validTime = (int)document["ValidTime"];
			GD.Print(currentTime - validTime);
			if (currentTime > validTime - 3600) continue;

			dataUsage += (long)document["DataUsage"];
			playerCount += (int)document["PlayerCount"];
			lobbyCount += (int)document["LobbyCount"];
		}

		liveData["usage"] = (long)liveData.GetValueOrDefault("usage", 0) + dataUsage;
		liveData["playercount"] = (int)liveData.GetValueOrDefault("playercount", 0) + playerCount;
		liveData["lobbycount"] = (int)liveData.GetValueOrDefault("lobbycount", 0) + lobbyCount;
		liveData["keys"] = (int)liveData.GetValueOrDefault("keys", 0) + 1;
		GD.Print("Live data ", liveData);
	}

	public void getDailyData(string memberId, string publicKey, Godot.Collections.Dictionary dailyData, Godot.Collections.Dictionary keyData)
	{
		_ = getDailyDataInternal(memberId, publicKey, dailyData, keyData);
	}

	public async Task getDailyDataInternal(string memberId, string publicKey, Godot.Collections.Dictionary dailyData, Godot.Collections.Dictionary keyData)
	{
		Godot.Collections.Dictionary data = await RetrieveDocumentsByIdSubstringAsync(
			"DailyData",
			publicKey,
			100,
			1
		);

		Godot.Collections.Dictionary resultData = new();
		int currentDay = Mathf.FloorToInt(Time.GetUnixTimeFromSystem() / 86400.0);

		Godot.Collections.Array documents = (Godot.Collections.Array)data["Documents"];

		foreach (Godot.Collections.Dictionary document in documents)
		{
			int day = (int)document["Day"];
			if (day < currentDay - 30) continue;

			if (resultData.ContainsKey(day))
			{
				Godot.Collections.Dictionary dayData = (Godot.Collections.Dictionary)resultData[day];
				dayData["playercount"] = (int)dayData.GetValueOrDefault("playercount", 0) + (int)document["PlayerCount"];
				dayData["lobbiesopened"] = (int)dayData.GetValueOrDefault("lobbiesopened", 0) + (int)document["LobbiesOpened"];
				dayData["usage"] = (int)dayData.GetValueOrDefault("usage", 0) + (int)document["DataUsage"];
			}
			else
			{
				Godot.Collections.Dictionary dayData = new Godot.Collections.Dictionary();
				dayData["playercount"] = (int)document["PlayerCount"];
				dayData["lobbiesopened"] = (int)document["LobbiesOpened"];
				dayData["usage"] = (int)document["DataUsage"];
				resultData[day] = dayData;
			}
		}

		keyData["MonthlyData"] = resultData;
		dailyData[publicKey] = keyData;
	}



	public void ExportUsageDataToCSV()
	{
		_ = ExportUsageDataToCSVInternal();
	}

	public async Task ExportUsageDataToCSVInternal()
	{
		GD.Print("=== Starting Usage Data Export ===");
		GD.Print($"Start time: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");

		// Calculate date range (last 30 days)
		int currentDay = Mathf.FloorToInt((float)(Time.GetUnixTimeFromSystem() / 86400.0));
		int startDay = currentDay - 30;
		GD.Print($"Date range: Day {startDay} to {currentDay} (last 30 days)");

		// Get all DailyData documents
		GD.Print("");
		GD.Print("[Step 1/3] Retrieving all DailyData documents...");
		var stopwatch = System.Diagnostics.Stopwatch.StartNew();

		// We need to paginate through all documents
		List<Godot.Collections.Dictionary> allDocuments = new List<Godot.Collections.Dictionary>();
		int page = 1;
		int pageSize = 100;
		bool hasMore = true;

		while (hasMore)
		{
			GD.Print($"  Fetching page {page}...");
			var pageStopwatch = System.Diagnostics.Stopwatch.StartNew();

			Godot.Collections.Dictionary result = await RetrieveDocumentsAsync(
				"DailyData",
				pageSize,
				page,
				false,
				true,  // Include ID to see the document structure
				new HashSet<string> { "IP", "LobbiesOpened", "PlayerCount", "DataUsage", "Day", "PlayTime", "PlayTimeCount" }
			);

			pageStopwatch.Stop();

			Godot.Collections.Array documents = (Godot.Collections.Array)result["Documents"];
			int finalPage = (int)result["FinalPage"];

			GD.Print($"  ✓ Page {page}/{finalPage}: Got {documents.Count} documents in {pageStopwatch.ElapsedMilliseconds}ms");

			foreach (Godot.Collections.Dictionary doc in documents)
			{
				allDocuments.Add(doc);
			}

			if (page >= finalPage)
			{
				hasMore = false;
			}
			else
			{
				page++;
			}
		}

		stopwatch.Stop();
		GD.Print($"  ✓ Total: {allDocuments.Count} documents retrieved in {stopwatch.ElapsedMilliseconds}ms");

		// Aggregate by memberId
		GD.Print("");
		GD.Print("[Step 2/3] Aggregating data by member...");
		stopwatch.Restart();

		// Structure: memberId -> aggregated data
		Dictionary<string, MemberUsageData> memberData = new Dictionary<string, MemberUsageData>();

		int processedDocs = 0;
		int skippedOld = 0;
		int skippedError = 0;

		foreach (Godot.Collections.Dictionary document in allDocuments)
		{
			processedDocs++;

			if (processedDocs % 100 == 0 || processedDocs == allDocuments.Count)
			{
				GD.Print($"  Processing document {processedDocs}/{allDocuments.Count}...");
			}

			try
			{
				// Extract memberId from the document ID
				// Document ID format: day + ip + memberId + publicKey
				// We need to parse this - but it's concatenated without delimiters
				// So we'll need the IP field to help us parse it

				if (!document.ContainsKey("Database_id") || !document.ContainsKey("Day"))
				{
					skippedError++;
					continue;
				}

				string docId = document["Database_id"].ToString();

				// Get the day value
				int day = (int)(Variant)document["Day"];

				// Skip documents older than 30 days
				if (day < startDay)
				{
					skippedOld++;
					continue;
				}

				// Parse the document ID to extract memberId
				// Format: {day}{ip}{memberId}{publicKey}
				// Day is an integer (like 20145), IP is like "123.456.789.012"
				// We need to find where memberId starts

				string dayStr = day.ToString();
				string ip = document.ContainsKey("IP") ? document["IP"].ToString() : "";

				// The docId starts with day + ip, so memberId + publicKey is the rest
				string prefix = dayStr + ip;

				if (!docId.StartsWith(prefix))
				{
					// Try to find memberId another way - maybe day format is different
					// Let's just skip for now and log it
					if (skippedError < 5)
					{
						GD.Print($"  ⚠ Doc ID doesn't match expected format: {docId}");
						GD.Print($"    Expected prefix: {prefix}");
					}
					skippedError++;
					continue;
				}

				string memberIdAndPublicKey = docId.Substring(prefix.Length);

				// Now we need to split memberId and publicKey
				// Both are likely UUIDs or similar strings
				// Let's assume they're both the same length or we can detect the pattern
				// For now, let's try to split assuming publicKey is a known length (like 32 chars for UUID without dashes)
				// Or we can try to detect based on common patterns

				// If you know the exact length of memberId or publicKey, adjust here
				// For now, let's assume memberId is a UUID (36 chars with dashes, or 32 without)
				// Let's try to detect - if the string is 64+ chars, split in half

				string memberId;
				if (memberIdAndPublicKey.Length >= 64)
				{
					// Assume memberId and publicKey are equal length
					memberId = memberIdAndPublicKey.Substring(0, memberIdAndPublicKey.Length / 2);
				}
				else if (memberIdAndPublicKey.Length >= 32)
				{
					// Try 32 char memberId
					memberId = memberIdAndPublicKey.Substring(0, 32);
				}
				else
				{
					// Just use the whole thing as memberId for now
					memberId = memberIdAndPublicKey;
				}

				// Extract other fields
				int lobbiesOpened = document.ContainsKey("LobbiesOpened") ? (int)(Variant)document["LobbiesOpened"] : 0;
				int playerCount = document.ContainsKey("PlayerCount") ? (int)(Variant)document["PlayerCount"] : 0;
				long dataUsage = 0;
				if (document.ContainsKey("DataUsage"))
				{
					Variant duVariant = (Variant)document["DataUsage"];
					if (duVariant.VariantType == Variant.Type.Int)
					{
						dataUsage = (long)(int)duVariant;
					}
					else
					{
						dataUsage = (long)duVariant;
					}
				}
				int playTime = document.ContainsKey("PlayTime") ? (int)(Variant)document["PlayTime"] : 0;
				int playTimeCount = document.ContainsKey("PlayTimeCount") ? (int)(Variant)document["PlayTimeCount"] : 0;

				// Aggregate into member data
				if (!memberData.ContainsKey(memberId))
				{
					memberData[memberId] = new MemberUsageData
					{
						MemberId = memberId,
						TotalLobbiesOpened = 0,
						TotalPlayerCount = 0,
						TotalDataUsage = 0,
						TotalPlayTime = 0,
						TotalPlayTimeCount = 0,
						DaysActive = 0,
						UniqueIPs = new HashSet<string>(),
						DailyData = new Dictionary<int, DayData>()
					};
				}

				var member = memberData[memberId];
				member.TotalLobbiesOpened += lobbiesOpened;
				member.TotalPlayerCount += playerCount;
				member.TotalDataUsage += dataUsage;
				member.TotalPlayTime += playTime;
				member.TotalPlayTimeCount += playTimeCount;

				if (!string.IsNullOrEmpty(ip))
				{
					member.UniqueIPs.Add(ip);
				}

				if (!member.DailyData.ContainsKey(day))
				{
					member.DailyData[day] = new DayData();
					member.DaysActive++;
				}

				member.DailyData[day].LobbiesOpened += lobbiesOpened;
				member.DailyData[day].PlayerCount += playerCount;
				member.DailyData[day].DataUsage += dataUsage;
			}
			catch (Exception ex)
			{
				skippedError++;
				if (skippedError <= 5)
				{
					GD.Print($"  ✗ Error processing doc: {ex.Message}");
				}
			}
		}

		stopwatch.Stop();
		GD.Print($"  ✓ Aggregation complete in {stopwatch.ElapsedMilliseconds}ms");
		GD.Print($"  ✓ Found {memberData.Count} unique members");
		GD.Print($"  ✓ Processed: {processedDocs - skippedOld - skippedError}, Skipped (old): {skippedOld}, Errors: {skippedError}");

		// Generate CSV
		GD.Print("");
		GD.Print("[Step 3/3] Generating CSV file...");

		string timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
		string fileName = $"member_usage_export_{timestamp}.csv";
		string filePath = $"res://{fileName}";

		GD.Print($"  Creating file: {fileName}");

		using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Write);
		if (file == null)
		{
			GD.PrintErr($"  ✗ Failed to create file: {filePath}");
			GD.PrintErr($"    Error: {FileAccess.GetOpenError()}");
			return;
		}

		// Write header
		GD.Print($"  Writing header...");
		file.StoreLine("MemberId,TotalLobbiesOpened,TotalPlayerCount,TotalDataUsageMB,TotalPlayTimeMinutes,AvgPlayTimeMinutes,DaysActive,UniqueIPs,AvgLobbiesPerDay,AvgPlayersPerDay,AvgDataPerDayMB");

		// Write data rows
		GD.Print($"  Writing {memberData.Count} data rows...");
		int rowsWritten = 0;

		// Sort by total lobbies opened (most active first)
		var sortedMembers = memberData.Values.OrderByDescending(m => m.TotalLobbiesOpened).ToList();

		foreach (var member in sortedMembers)
		{
			double totalDataMB = member.TotalDataUsage / (1024.0 * 1024.0);
			double totalPlayTimeMinutes = member.TotalPlayTime / 60.0;
			double avgPlayTimeMinutes = member.TotalPlayTimeCount > 0 ? (member.TotalPlayTime / 60.0) / member.TotalPlayTimeCount : 0;
			double avgLobbiesPerDay = member.DaysActive > 0 ? (double)member.TotalLobbiesOpened / member.DaysActive : 0;
			double avgPlayersPerDay = member.DaysActive > 0 ? (double)member.TotalPlayerCount / member.DaysActive : 0;
			double avgDataPerDayMB = member.DaysActive > 0 ? totalDataMB / member.DaysActive : 0;

			string line = string.Join(",", new string[]
			{
			EscapeCSV(member.MemberId),
			member.TotalLobbiesOpened.ToString(),
			member.TotalPlayerCount.ToString(),
			totalDataMB.ToString("F4"),
			totalPlayTimeMinutes.ToString("F2"),
			avgPlayTimeMinutes.ToString("F2"),
			member.DaysActive.ToString(),
			member.UniqueIPs.Count.ToString(),
			avgLobbiesPerDay.ToString("F2"),
			avgPlayersPerDay.ToString("F2"),
			avgDataPerDayMB.ToString("F4")
			});
			file.StoreLine(line);
			rowsWritten++;

			if (rowsWritten % 50 == 0 || rowsWritten == memberData.Count)
			{
				GD.Print($"    Written {rowsWritten}/{memberData.Count} rows...");
			}
		}

		file.Close();
		GD.Print($"  ✓ File written and closed");

		// Get absolute path for user reference
		string absolutePath = ProjectSettings.GlobalizePath(filePath);

		GD.Print("");
		GD.Print("╔══════════════════════════════════════════════════════════════╗");
		GD.Print("║                    EXPORT COMPLETE                           ║");
		GD.Print("╠══════════════════════════════════════════════════════════════╣");
		GD.Print($"  Total members exported: {memberData.Count}");
		GD.Print($"  File saved to: {absolutePath}");
		GD.Print($"  End time: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
		GD.Print("╠══════════════════════════════════════════════════════════════╣");
		GD.Print("║                 SUMMARY (Last 30 Days)                       ║");
		GD.Print("╠══════════════════════════════════════════════════════════════╣");

		// Print summary statistics
		long grandTotalData = 0;
		int grandTotalLobbies = 0;
		int grandTotalPlayers = 0;
		int activeMembers = 0;

		foreach (var m in memberData.Values)
		{
			grandTotalData += m.TotalDataUsage;
			grandTotalLobbies += m.TotalLobbiesOpened;
			grandTotalPlayers += m.TotalPlayerCount;
			if (m.DaysActive > 0) activeMembers++;
		}

		GD.Print($"  Total Members: {memberData.Count}");
		GD.Print($"  Active Members (30d): {activeMembers}");
		GD.Print($"  Total Lobbies Opened: {grandTotalLobbies:N0}");
		GD.Print($"  Total Player Joins: {grandTotalPlayers:N0}");
		GD.Print($"  Total Data Usage: {grandTotalData / (1024.0 * 1024.0 * 1024.0):F2} GB");
		GD.Print("╚══════════════════════════════════════════════════════════════╝");

		// Print top 10 most active members
		GD.Print("");
		GD.Print("Top 10 Most Active Members (by lobbies opened):");
		int rank = 0;
		foreach (var member in sortedMembers.Take(10))
		{
			rank++;
			string memberPreview = member.MemberId.Length > 16 ? member.MemberId.Substring(0, 16) + "..." : member.MemberId;
			GD.Print($"  {rank}. {memberPreview}: {member.TotalLobbiesOpened} lobbies, {member.TotalPlayerCount} players, {member.TotalDataUsage / (1024.0 * 1024.0):F2} MB");
		}
	}

	private class MemberUsageData
	{
		public string MemberId { get; set; }
		public int TotalLobbiesOpened { get; set; }
		public int TotalPlayerCount { get; set; }
		public long TotalDataUsage { get; set; }
		public int TotalPlayTime { get; set; }
		public int TotalPlayTimeCount { get; set; }
		public int DaysActive { get; set; }
		public HashSet<string> UniqueIPs { get; set; }
		public Dictionary<int, DayData> DailyData { get; set; }
	}

	private class DayData
	{
		public int LobbiesOpened { get; set; }
		public int PlayerCount { get; set; }
		public long DataUsage { get; set; }
	}

	private string EscapeCSV(string value)
	{
		if (string.IsNullOrEmpty(value)) return "";
		if (value.Contains(",") || value.Contains("\"") || value.Contains("\n"))
		{
			return "\"" + value.Replace("\"", "\"\"") + "\"";
		}
		return value;
	}
}
