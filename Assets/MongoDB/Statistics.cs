using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

public partial class MongoDBAPI : Node
{
	public void getLiveData(string ip, string publicKey, Godot.Collections.Dictionary liveData)
	{
		_ = getLiveDataInternal(ip, publicKey, liveData);
	}

	public async Task getLiveDataInternal(string ip, string publicKey, Godot.Collections.Dictionary liveData)
	{
		Godot.Collections.Dictionary data = await RetrieveDocumentsByIdSubstringAsync(
			"LiveData",
			publicKey,
			100,
			1
		);

		Godot.Collections.Array documents = (Godot.Collections.Array)data["Documents"];

		int currentTime = (int)Time.GetUnixTimeFromSystem();
		long dataUsage = 0;
		int playerCount = 0;
		int lobbyCount = 0;

		foreach (Godot.Collections.Dictionary document in documents)
		{
			int validTime = (int)document["ValidTime"];
			if (currentTime > validTime - 3600) continue;

			dataUsage += (long)document["DataUsage"];
			playerCount += (int)document["PlayerCount"];
			lobbyCount += (int)document["LobbyCount"];
		}

		liveData["usage"] = (long)liveData.GetValueOrDefault("usage", 0) + dataUsage;
		liveData["playercount"] = (int)liveData.GetValueOrDefault("playercount", 0) + playerCount;
		liveData["lobbycount"] = (int)liveData.GetValueOrDefault("lobbycount", 0) + lobbyCount;
		liveData["keys"] = (int)liveData.GetValueOrDefault("keys", 0) + 1;
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
}
