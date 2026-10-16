using Godot;
using MongoDB.Bson;
using MongoDB.Driver;
using System;
using System.Threading.Tasks;

public partial class MongoDBAPI
{
	/// <summary>
	/// Reads the immutable free-plan cycle anchor. Never inserts.
	/// result receives ready/ok/anchor on the main thread. anchor is 0 when the
	/// member has not used data yet. ok is false when the read itself failed.
	/// </summary>
	public void ReadFreeCycleAnchor(string memberId, Godot.Collections.Dictionary result)
	{
		if (result == null)
			return;
		_ = ReadFreeCycleAnchorInternal(memberId, result);
	}

	private async Task ReadFreeCycleAnchorInternal(string memberId, Godot.Collections.Dictionary result)
	{
		long anchor = 0;
		bool ok = false;
		try
		{
			if (client != null && !string.IsNullOrEmpty(memberId))
			{
				BsonDocument document = await client.GetDatabase(databaseName)
					.GetCollection<BsonDocument>("FreeCycle")
					.Find(Builders<BsonDocument>.Filter.Eq("_id", memberId))
					.Project<BsonDocument>(Builders<BsonDocument>.Projection.Include("Anchor"))
					.FirstOrDefaultAsync()
					.ConfigureAwait(false);
				ok = true;
				if (document != null
					&& document.TryGetValue("Anchor", out BsonValue value)
					&& value.IsNumeric)
				{
					anchor = value.ToInt64();
				}
			}
		}
		catch (Exception ex)
		{
			GD.Print("ReadFreeCycleAnchor failed for ", memberId, ": ", ex.Message);
			ok = false;
		}

		CallDeferred(nameof(FinishFreeCycleRead), result, anchor, ok);
	}

	private void FinishFreeCycleRead(Godot.Collections.Dictionary result, long anchor, bool ok)
	{
		if (result == null)
			return;
		result["anchor"] = anchor;
		result["ok"] = ok;
		result["ready"] = true;
	}
}
