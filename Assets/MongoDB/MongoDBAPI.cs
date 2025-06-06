using ENUMS;
using Godot;
using MongoDB.Bson;
using MongoDB.Driver;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using ZstdSharp;

public partial class MongoDBAPI : Node
{
	private string connectionString = "mongodb+srv://doadmin:063g54jbKv981JRh@main-database-011967d4.mongo.ondigitalocean.com/admin?authSource=admin&ssl=true";
	private MongoClient client;

	private bool print_debug = false;

	private string databaseName = "main";

	public Compressor compressor = new Compressor();
	public Decompressor decompressor = new Decompressor();

	Node Firebase;


	private BsonDocument[] deletepipeline = new BsonDocument[]
	{
			new BsonDocument("$match", new BsonDocument
			{
				{ "operationType", new BsonDocument("$in", new BsonArray(new[] { "delete" })) }
			})
	};

	private BsonDocument[] writepipeline = new BsonDocument[]
	{
			new BsonDocument("$match", new BsonDocument
			{
				{ "operationType", new BsonDocument("$in", new BsonArray(new[] { "insert", "update", "replace" })) }
			})
	};

	public override void _Ready()
	{
		Firebase = GetNode("/root/Firebase");

		client = new MongoClient(connectionString);
	}

	private Dictionary<string, CancellationTokenSource> listenerTokens = new Dictionary<string, CancellationTokenSource>();
	ChangeStreamOptions options = new ChangeStreamOptions
	{
		FullDocument = ChangeStreamFullDocumentOption.Default // This ensures the full document is not returned
	};

	public async void ListenToDatabase(string collectionName, BsonDocument[] pipeline, Action<string, string> onDocumentChanged, int counter = 0)
	{
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		// Create a cancellation token source and store it
		var cancellationTokenSource = new CancellationTokenSource();
		listenerTokens[databaseName + "_" + collectionName] = cancellationTokenSource;

		try
		{
			using (var cursor = await collection.WatchAsync<ChangeStreamDocument<BsonDocument>>(pipeline, options, cancellationToken: cancellationTokenSource.Token))
			{
				while (await cursor.MoveNextAsync())
				{
					if (cancellationTokenSource.Token.IsCancellationRequested)
					{
						if (print_debug) GD.Print("Listening canceled for database: ", databaseName, " and collection: ", collectionName);
						return;
					}

					foreach (var change in cursor.Current)
					{
						string dbKey = (string)change.DocumentKey["_id"];
						if (print_debug)
						{
							GD.Print("Changed", dbKey);
						}
						onDocumentChanged(collectionName, dbKey);
					}
				}
			}
		}
		catch (Exception ex)
		{
			if (print_debug) GD.Print("Error watching database changes: " + ex.Message);
			await Task.Delay(1000);
			ListenToDatabase(collectionName, pipeline, onDocumentChanged, counter + 1);
		}
	}

	public void StopListening(string collectionName)
	{
		string key = databaseName + "_" + collectionName;
		if (listenerTokens.TryGetValue(key, out var tokenSource))
		{
			tokenSource.Cancel();
			listenerTokens.Remove(key);
			if (print_debug) GD.Print("Stopped listening to ", databaseName, " ", collectionName);
		}
	}

	public async Task<int> SetPlayerDocument(string user, string path, bool externally_visible, Godot.Collections.Dictionary data, string publicKey)
	{
		if (print_debug) GD.Print("Set user document ", user, " ", path);

		string[] pathSegments = path.Split('/');

		await LockDocument("UserData", user);

		Godot.Collections.Dictionary activeSaveData;

		byte[] bytes = await RetrieveByteDocument("UserData", user, publicKey);

		if (bytes == null)
		{
			activeSaveData = new Godot.Collections.Dictionary();
		}
		else
		{
			bytes = decompressor.Unwrap(bytes).ToArray();
			activeSaveData = (Godot.Collections.Dictionary)GD.BytesToVar(bytes);
		}


		// Start with the root of the active save data
		Godot.Collections.Dictionary currentData = activeSaveData;
		for (int i = 0; i < pathSegments.Length; i++)
		{
			string pathSegment = pathSegments[i];

			// If we're at the last segment, set the data
			if (i == pathSegments.Length - 1)
			{
				if (!currentData.ContainsKey(pathSegment))
				{
					currentData[pathSegment] = new Godot.Collections.Dictionary();
				}
				((Godot.Collections.Dictionary)currentData[pathSegment])["_externally_visible"] = externally_visible;
				((Godot.Collections.Dictionary)currentData[pathSegment])["_document_data"] = data;
			}
			else
			{
				// If the segment exists, navigate deeper
				if (currentData.ContainsKey(pathSegment))
				{
					currentData = (Godot.Collections.Dictionary)currentData[pathSegment];

					if (externally_visible) currentData["_externally_visible"] = externally_visible;
				}
				else
				{
					// If the segment doesn't exist, create a new dictionary at this segment
					currentData[pathSegment] = new Godot.Collections.Dictionary();
					currentData = (Godot.Collections.Dictionary)currentData[pathSegment];
					if (externally_visible) currentData["_externally_visible"] = externally_visible;
				}
			}
		}

		bytes = compressor.Wrap(GD.VarToBytes(activeSaveData)).ToArray();
		int size = bytes.Length;

		if (print_debug) GD.Print("Attempting to store ", size / 1024.0, "kb");
		// if (size / 1024.0 > storageLimit)
		// {
		// 	UnlockDocument(memberID, "UserData", user);
		// 	return (int)SET_PLAYER_DOCUMENT_RESPONSE_CODE.STORAGE_FULL;
		// }

		_ = CreateByteDocument("UserData", user, bytes, publicKey, size);
		UnlockDocument("UserData", user);

		return (int)SET_PLAYER_DOCUMENT_RESPONSE_CODE.SUCCESS;
	}

	public async Task<Godot.Collections.Dictionary> RetrieveDocument(string collectionName, string documentId, bool includeSize = false, bool includeID = false, HashSet<string> rawParameters = null)
	{
		if (print_debug) GD.Print("Retrieve document ", databaseName, " ", collectionName, " ", documentId);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		// Create a filter to find the document by its "_id" field
		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentId);

		var bsonDocument = await collection.Find(filter).FirstOrDefaultAsync();
		if (bsonDocument == null)
		{
			// Handle the case where no document matches the filter
			if (print_debug) GD.Print("Retrieve document FAILED ", databaseName, " ", collectionName, " ", documentId);
			return new Godot.Collections.Dictionary()
			{
			};
		}

		var dictionary = new Godot.Collections.Dictionary();
		foreach (var element in bsonDocument)
		{
			if (includeSize)
			{
				if (element.Name == "StorageSize")
				{
					int size = (int)element.Value;
					dictionary["StorageSize"] = size;
					continue;
				}
			}
			else
			{
				if (element.Name == "StorageSize") continue;
			}
			if (includeID)
			{
				if (element.Name == "_id")
				{
					dictionary["Database_id"] = (string)element.Value;
					continue;
				}
			}
			else
			{
				if (element.Name == "_id") continue;
			}
			if (element.Name == "expiresAt") continue;

			if (rawParameters != null && rawParameters.Contains(element.Name))
			{
				if (element.Value.BsonType == BsonType.String)
				{
					dictionary[element.Name] = (string)element.Value;
				}
				else
				{
					dictionary[element.Name] = (int)element.Value;
				}

			}
			else
			{
				dictionary[GD.StrToVar(element.Name)] = GD.BytesToVar((byte[])element.Value);
			}
		}

		return dictionary;
	}

	public async Task<byte[]> RetrieveByteDocument(string collectionName, string documentId, string publicKey)
	{
		if (print_debug) GD.Print("Retrieve byte document from ", databaseName, " ", collectionName, " ", documentId);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		// Create a filter to find the document by its "_id" field
		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentId);

		// Define a projection to include only the byte array field

		string byteArrayKey = GD.VarToStr("byteData");
		var projection = Builders<BsonDocument>.Projection.Include(byteArrayKey).Exclude("_id");

		// Execute the find operation with projection
		var document = await collection.Find(filter).Project<BsonDocument>(projection).FirstOrDefaultAsync();

		if (document != null && document.Contains(byteArrayKey) && document[byteArrayKey].IsBsonBinaryData)
		{
			var byteData = document[byteArrayKey].AsBsonBinaryData.Bytes;
			if (print_debug) GD.Print("Retrieved byte document size: ", byteData.Length, " bytes.");

			return byteData;
		}
		else
		{
			if (print_debug) GD.Print("No byte document found or field 'byteData' is missing.");
			return null;  // Return null to indicate no data found or incorrect data format
		}
	}

	public async Task CreateByteDocument(string collectionName, string documentName, byte[] byteArray, string publicKey, int size = 0)
	{
		if (print_debug) GD.Print("Write to file ", databaseName, " ", collectionName, " ", documentName);

		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		var document = new BsonDocument();
		document["_id"] = documentName;

		string byteArrayKey = GD.VarToStr("byteData");
		document[byteArrayKey] = new BsonBinaryData(byteArray);

		if (size == 0) size = byteArray.Length;
		document["StorageSize"] = size;

		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentName);
		var options = new ReplaceOptions { IsUpsert = true };

		try
		{
			ReplaceOneResult result = await collection.ReplaceOneAsync(filter, document, options);
			if (!result.IsAcknowledged || result.ModifiedCount == 0 && result.UpsertedId == null)
			{
				if (print_debug) GD.Print("Failed to replace document: No document was modified or upserted.");
			}
		}
		catch (Exception ex)
		{
			if (print_debug) GD.Print("Exception occurred while replacing the document: ", ex.Message);
		}
	}

	public async Task<bool> DeleteDocument(string collectionName, string documentName)
	{
		if (print_debug) GD.Print("Deleting document ", databaseName, " ", collectionName, " ", documentName);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentName);
		var result = await collection.DeleteOneAsync(filter);

		bool isDeleted = result.IsAcknowledged && result.DeletedCount > 0;

		if (print_debug)
		{
			if (isDeleted)
				GD.Print("Document ", databaseName, " ", collectionName, " ", documentName, " successfully deleted.");
			else
				GD.Print("Document ", databaseName, " ", collectionName, " ", documentName, " deletion failed or document not found.");
		}

		return isDeleted;
	}

	public async Task CreateDocument(string collectionName, string documentName, Godot.Collections.Dictionary data, string publicKey, int size = 0, bool register = true, HashSet<string> rawParameters = null)
	{
		if (print_debug) GD.Print("Write to file ", databaseName, " ", collectionName, " ", documentName);

		if (string.IsNullOrEmpty(documentName))
		{
			documentName = Guid.NewGuid().ToString();
		}

		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		var document = new BsonDocument();
		document["_id"] = documentName;
		foreach (KeyValuePair<Variant, Variant> entry in data)
		{
			string key = (string)entry.Key;
			if (rawParameters != null && rawParameters.Contains(key))
			{
				if (entry.Value.VariantType == Variant.Type.Int)
				{
					document[key] = (int)entry.Value;
				}
				else
				{
					document[key] = (string)entry.Value;
				}
			}
			else
			{
				key = GD.VarToStr(entry.Key);
				document[key] = new BsonBinaryData(GD.VarToBytes(entry.Value));
			}
		}

		if (size == 0) size = GD.VarToBytes(data).Length;
		document["StorageSize"] = size;

		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentName);
		var options = new ReplaceOptions { IsUpsert = true };

		try
		{
			ReplaceOneResult result = await collection.ReplaceOneAsync(filter, document, options);
			if (!result.IsAcknowledged || result.ModifiedCount == 0 && result.UpsertedId == null)
			{
				if (print_debug) GD.Print("Failed to replace document: No document was modified or upserted.");
			}
		}
		catch (Exception ex)
		{
			if (print_debug) GD.Print("Exception occurred while replacing the document: ", ex.Message);
		}
	}

	public async Task CreateTemporaryDocument(string collectionName, string documentName, Godot.Collections.Dictionary data, int lifetimeInSeconds, int size = 0)
	{
		if (print_debug) GD.Print("Write to temporary file ", databaseName, " ", collectionName, " ", documentName);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		// Check and create TTL index if not exists
		await CreateTTLIndexIfNeeded(collection, "expiresAt");

		var document = new BsonDocument();
		document["_id"] = documentName;
		foreach (KeyValuePair<Variant, Variant> entry in data)
		{
			string key = GD.VarToStr(entry.Key);
			document[key] = new BsonBinaryData(GD.VarToBytes(entry.Value));
		}

		if (size == 0) size = GD.VarToBytes(data).Length;
		document["StorageSize"] = size;

		// Calculate the expiration date based on the lifetime in seconds
		DateTime expiration = DateTime.UtcNow.AddSeconds(lifetimeInSeconds);
		document["expiresAt"] = expiration;

		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentName);
		var options = new ReplaceOptions { IsUpsert = true };
		await collection.ReplaceOneAsync(filter, document, options);
	}

	public async Task<long> GetDocumentStorageSizeAsync(string collectionName, string documentName)
	{
		if (print_debug) GD.Print("Starting retrieval of StorageSize for document: ", databaseName, " ", collectionName, " ", documentName);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		try
		{
			var filter = Builders<BsonDocument>.Filter.Eq("_id", documentName);
			var projection = Builders<BsonDocument>.Projection.Include("StorageSize").Exclude("_id");
			var document = await collection.Find(filter).Project<BsonDocument>(projection).FirstOrDefaultAsync();

			if (document != null)
			{
				long size = document.Contains("StorageSize") ? document["StorageSize"].ToInt64() : 0;
				if (print_debug) GD.Print("Document Size: ", size, " ", databaseName, " ", collectionName, " ", documentName);
				return size;
			}
			else
			{
				if (print_debug) GD.Print("Document not found: ", databaseName, " ", collectionName, " ", documentName);
			}
		}
		catch (Exception ex)
		{
			if (print_debug) GD.Print("Exception retrieving StorageSize: ", ex.ToString());
		}

		return 0;
	}


	public async Task CreateIndex(string collectionName, HashSet<string> fieldsToIndex)
	{
		if (print_debug) GD.Print("Creating index for ", databaseName, " ", collectionName);

		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		var indexKeys = new BsonDocument();
		foreach (string field in fieldsToIndex)
		{
			indexKeys.Add(field, 1);  // Creates an ascending index for each specified field
		}

		try
		{
			string indexName = await collection.Indexes.CreateOneAsync(new CreateIndexModel<BsonDocument>(indexKeys));
			if (print_debug) GD.Print("Index created: ", indexName);
		}
		catch (Exception ex)
		{
			if (print_debug) GD.Print("Exception occurred while creating index: ", ex.Message);
		}
	}


	private async Task CreateTTLIndexIfNeeded(IMongoCollection<BsonDocument> collection, string fieldName)
	{
		try
		{
			var indexOptions = new CreateIndexOptions { ExpireAfter = TimeSpan.FromSeconds(0) };
			var indexKeys = Builders<BsonDocument>.IndexKeys.Ascending(fieldName);
			await collection.Indexes.CreateOneAsync(new CreateIndexModel<BsonDocument>(indexKeys, indexOptions));
			if (print_debug) GD.Print("TTL index ensured on field: ", fieldName);
		}
		catch (MongoCommandException ex)
		{
			if (print_debug) GD.Print("TTL index already exists or another error occurred: ", ex.Message);
		}
	}

	public async Task MakeDocumentPersistent(string collectionName, string documentName)
	{
		if (print_debug) GD.Print("Making document persistent ", databaseName, " ", collectionName, " ", documentName);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		var filter = Builders<BsonDocument>.Filter.Eq("_id", documentName);

		var update = Builders<BsonDocument>.Update.Unset("expiresAt");

		try
		{
			var result = await collection.UpdateOneAsync(filter, update);
			if (result.ModifiedCount == 0)
			{
				if (print_debug) GD.Print("No document found or 'expiresAt' field was not set.");
			}
			else
			{
				if (print_debug) GD.Print("Document is now persistent; 'expiresAt' field removed.");
			}
		}
		catch (Exception ex)
		{
			if (print_debug) GD.Print("Error making document persistent: ", ex.Message);
		}
	}

	public async Task<Godot.Collections.Array> BrowseCollection(string user, string path, bool externally_visible, string publicKey)
	{
		string[] pathSegments = path.Split('/');

		Godot.Collections.Dictionary activeSaveData;

		byte[] bytes = await RetrieveByteDocument("UserData", user, publicKey);

		Godot.Collections.Array browseResults = new Godot.Collections.Array();

		if (bytes == null)
		{
			activeSaveData = new Godot.Collections.Dictionary();
		}
		else
		{
			bytes = decompressor.Unwrap(bytes).ToArray();
			activeSaveData = (Godot.Collections.Dictionary)GD.BytesToVar(bytes);
		}

		// Start with the root of the active save data
		Godot.Collections.Dictionary currentData = activeSaveData;
		for (int i = 0; i < pathSegments.Length; i++)
		{
			string pathSegment = pathSegments[i];

			if (currentData.ContainsKey(pathSegment))
			{
				if (externally_visible)
				{
					if (currentData.ContainsKey("_externally_visible") && !(bool)currentData["_externally_visible"]) return null;
				}
				currentData = (Godot.Collections.Dictionary)currentData[pathSegment];
			}
			else
			{
				return null;
			}
		}

		if (externally_visible)
		{
			if (currentData.ContainsKey("_externally_visible") && !(bool)currentData["_externally_visible"]) return null;
		}

		if (print_debug) GD.Print("Browse ", currentData);

		string prefix = "root/";

		foreach (KeyValuePair<Variant, Variant> keyValuePair in currentData)
		{
			string key = (string)keyValuePair.Key;

			if (key == "_document_data" || key == "_externally_visible") continue;

			Godot.Collections.Dictionary subData = (Godot.Collections.Dictionary)currentData[key];

			if (externally_visible && subData.ContainsKey("_externally_visible") && !(bool)subData["_externally_visible"]) continue;

			bool isDocument = subData.ContainsKey("_document_data");

			browseResults.Add(new Godot.Collections.Dictionary() {
				{"Name", key},
				{"Path", path.StartsWith("root/") ? path.Substring("root/".Length) + "/" + key : path + "/" + key},
				{"Type", isDocument ? "Document" : "Collection"},
				{"ExternallyVisible", currentData.ContainsKey("_externally_visible") ? currentData["_externally_visible"] : false}
			});
		}

		return browseResults;
	}

	public async Task<Godot.Collections.Dictionary> RetrieveDocumentsAsync(string collectionName, int amount, int page, bool includeSize = false, bool includeID = false, HashSet<string> rawParameters = null, string sort = "_id", bool ascending = true)
	{
		if (print_debug) GD.Print("Retrieve documents from ", databaseName, " ", collectionName, " ", amount, " ", includeSize, " ", includeID, " ", rawParameters, " ", sort, " ", ascending);
		if (amount > 100) amount = 100;

		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		// First, find out how many documents are in the collection
		var totalDocuments = await collection.CountDocumentsAsync(Builders<BsonDocument>.Filter.Empty);

		// Calculate the number of documents to skip based on the page number and amount
		int skip = (page - 1) * amount;

		// Retrieve the documents with pagination
		List<BsonDocument> bsonDocuments;

		if (ascending)
		{
			bsonDocuments = await collection.Find(Builders<BsonDocument>.Filter.Empty)
			.Sort(Builders<BsonDocument>.Sort.Ascending(sort))
			.Skip(skip)
			.Limit(amount)
			.ToListAsync();
		}
		else
		{
			bsonDocuments = await collection.Find(Builders<BsonDocument>.Filter.Empty)
			.Sort(Builders<BsonDocument>.Sort.Descending(sort))
			.Skip(skip)
			.Limit(amount)
			.ToListAsync();
		}

		var documentsList = new Godot.Collections.Array();

		List<Task> tasks = new List<Task>();

		foreach (var bsonDocument in bsonDocuments)
		{
			var dictionary = new Godot.Collections.Dictionary();
			foreach (var element in bsonDocument)
			{
				if (includeSize)
				{
					if (element.Name == "StorageSize")
					{
						int size = (int)element.Value;
						dictionary["StorageSize"] = size;
						continue;
					}
				}
				else
				{
					if (element.Name == "StorageSize")
					{
						int size = (int)element.Value;
						continue;
					}
				}
				if (includeID)
				{
					if (element.Name == "_id")
					{
						dictionary["Database_id"] = (string)element.Value;
						continue;
					}
				}
				else
				{
					if (element.Name == "_id")
					{
						continue;
					}
				}
				if (element.Name == "expiresAt") continue;

				if (rawParameters != null && rawParameters.Contains(element.Name))
				{
					if (element.Value.BsonType == BsonType.String)
					{
						dictionary[element.Name] = (string)element.Value;
					}
					else
					{
						dictionary[element.Name] = (int)element.Value;
					}

				}
				else
				{
					dictionary[GD.StrToVar(element.Name)] = GD.BytesToVar((byte[])element.Value);
				}
			}

			documentsList.Add(dictionary);
		}

		// Calculate the final page
		int finalPage = (int)Math.Ceiling((double)totalDocuments / amount);
		if (finalPage == 0) finalPage = 1;

		await Task.WhenAll(tasks);

		// Prepare the return dictionary
		var resultDictionary = new Godot.Collections.Dictionary();
		resultDictionary["Documents"] = documentsList;
		resultDictionary["FinalPage"] = finalPage;

		if (print_debug) GD.Print("Returning documents ", documentsList);

		return resultDictionary;
	}

	public async Task<Godot.Collections.Dictionary> RetrieveDocumentsByIdSubstringAsync(string collectionName, string idContains, int amount, int page, bool includeSize = false, bool includeID = false, HashSet<string> rawParameters = null, string sort = "_id", bool ascending = true)
	{
		if (print_debug) GD.Print("Retrieve documents from ", databaseName, " ", collectionName, " with ID containing ", idContains);

		if (amount > 100) amount = 100;

		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		var filter = string.IsNullOrEmpty(idContains) ?
			Builders<BsonDocument>.Filter.Empty :
			Builders<BsonDocument>.Filter.Regex("_id", new BsonRegularExpression(idContains, "i"));

		var totalDocuments = await collection.CountDocumentsAsync(filter);
		int skip = (page - 1) * amount;

		List<BsonDocument> bsonDocuments;
		var sortDefinition = ascending ?
			Builders<BsonDocument>.Sort.Ascending(sort) :
			Builders<BsonDocument>.Sort.Descending(sort);

		bsonDocuments = await collection.Find(filter)
			.Sort(sortDefinition)
			.Skip(skip)
			.Limit(amount)
			.ToListAsync();

		var documentsList = new Godot.Collections.Array();
		List<Task> tasks = new List<Task>();

		foreach (var bsonDocument in bsonDocuments)
		{
			var dictionary = new Godot.Collections.Dictionary();
			foreach (var element in bsonDocument)
			{
				if (includeSize && element.Name == "StorageSize")
				{
					dictionary["StorageSize"] = (int)element.Value;
					continue;
				}
				if (!includeSize && element.Name == "StorageSize") continue;

				if (includeID && element.Name == "_id")
				{
					dictionary["Database_id"] = (string)element.Value;
					continue;
				}
				if (!includeID && element.Name == "_id") continue;

				if (element.Name == "expiresAt") continue;

				if (rawParameters != null && rawParameters.Contains(element.Name))
				{
					dictionary[element.Name] = element.Value.BsonType == BsonType.String ?
						(string)element.Value : (int)element.Value;
				}
				else
				{
					dictionary[GD.StrToVar(element.Name)] = GD.BytesToVar((byte[])element.Value);
				}
			}
			documentsList.Add(dictionary);
		}

		int finalPage = (int)Math.Ceiling((double)totalDocuments / amount);
		if (finalPage == 0) finalPage = 1;

		await Task.WhenAll(tasks);

		var resultDictionary = new Godot.Collections.Dictionary();
		resultDictionary["Documents"] = documentsList;
		resultDictionary["FinalPage"] = finalPage;

		if (print_debug) GD.Print("Returning documents ", documentsList);

		return resultDictionary;
	}


	public async Task<Godot.Collections.Array> RetrieveAllDocumentIdsAsync(string collectionName)
	{
		if (print_debug) GD.Print("Retrieve all document _ids from ", databaseName, " ", collectionName);
		var database = client.GetDatabase(databaseName);
		var collection = database.GetCollection<BsonDocument>(collectionName);

		// Retrieve all documents only fetching the _id field
		var projection = Builders<BsonDocument>.Projection.Include("_id");
		var bsonDocuments = await collection.Find(new BsonDocument()).Project(projection).ToListAsync();

		var documentIds = new Godot.Collections.Array();

		foreach (var bsonDocument in bsonDocuments)
		{
			// Directly add the _id value to the array
			if (bsonDocument.Contains("_id"))
			{
				documentIds.Add(bsonDocument["_id"].ToString());
			}
		}

		return documentIds;
	}

	private static readonly ConcurrentDictionary<string, SemaphoreSlim> LockDictionary = new ConcurrentDictionary<string, SemaphoreSlim>();
	private static readonly ConcurrentDictionary<string, DateTime> LockExpiryDictionary = new ConcurrentDictionary<string, DateTime>();
	private static readonly TimeSpan LockTimeout = TimeSpan.FromSeconds(5);

	public async Task LockDocument(string collection, string document)
	{
		string key = $"{databaseName}:{collection}:{document}";
		if (print_debug) GD.Print("Lock attempt on ", databaseName, " ", collection, " ", document);
		SemaphoreSlim semaphore = LockDictionary.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
		bool lockAcquired = false;

		while (true)
		{
			await semaphore.WaitAsync();
			lockAcquired = true;

			try
			{
				if (LockExpiryDictionary.TryGetValue(key, out DateTime expiryTime))
				{
					if (DateTime.UtcNow >= expiryTime)
					{
						if (print_debug) GD.Print("Taking lock for ", databaseName, " ", collection, " ", document);
						// Lock expired, take over
						LockExpiryDictionary[key] = DateTime.UtcNow.Add(LockTimeout);
						return;
					}
					else
					{
						// Lock still active, release and wait
						// double waitTimeSeconds = (expiryTime - DateTime.UtcNow).TotalSeconds;
						// if (print_debug) GD.Print("Waiting for unlock ", databaseName, " ", collection, " ", document, " for ", waitTimeSeconds, " seconds");
						semaphore.Release();
						lockAcquired = false; // Mark lock as released
					}
				}
				else
				{
					// No existing lock, create new
					if (print_debug) GD.Print("New lock for ", databaseName, " ", collection, " ", document);
					LockExpiryDictionary[key] = DateTime.UtcNow.Add(LockTimeout);
					return;
				}
			}
			finally
			{
				if (lockAcquired)
				{
					semaphore.Release();
				}
			}

			await Task.Delay(100); // Wait before retrying
		}
	}

	public void UnlockDocument(string collection, string document)
	{
		string key = $"{databaseName}:{collection}:{document}";

		if (LockDictionary.TryGetValue(key, out SemaphoreSlim semaphore))
		{
			if (print_debug) GD.Print("Unlock ", databaseName, " ", collection, " ", document);
			LockExpiryDictionary.TryRemove(key, out _);

			try
			{
				semaphore.Release();
			}
			catch (SemaphoreFullException)
			{
				if (print_debug) GD.Print("Semaphore already released for ", databaseName, " ", collection, " ", document);
			}
		}
	}
}

namespace ENUMS
{

	enum CONNECTION_STATUS
	{
		LOBBY_SWITCH = -1,
		DISABLED,
		FINDING_LB,
		PINGING_SERVERS,
		CONNECTING,
		CONNECTED,
		CONNECTION_SECURED,
		LOCAL_CONNECTION
	}

	enum PACKET_CHANNEL
	{
		SETUP,
		SERVER,
		RELIABLE,
		UNRELIABLE,
		INTERNAL,
	}

	enum PACKET_VALUE
	{
		PADDING,
		CLIENT_REQUESTS,
		SERVER_REQUESTS,
		INTERNAL_REQUESTS,
	}

	enum REQUEST_TYPE
	{
		VALIDATE_KEY,
		SECURE_CONNECTION,
		MESSAGE,
		SET_VARIABLE,
		CALL_FUNCTION,
		SET_VARIABLE_CACHED,
		CALL_FUNCTION_CACHED,
		CACHE_NODE_PATH,
		ERASE_NODE_PATH_CACHE,
		CACHE_NAME,
		ERASE_NAME_CACHE,
		SET_MC_OWNER,
		CREATE_LOBBY,
		JOIN_LOBBY,
		LEAVE_LOBBY,
		OPEN_LOBBY,
		CLOSE_LOBBY,
		SET_LOBBY_TAG,
		ERASE_LOBBY_TAG,
		SET_LOBBY_DATA,
		ERASE_LOBBY_DATA,
		SET_LOBBY_VISIBILITY,
		SET_LOBBY_PLAYER_LIMIT,
		SET_LOBBY_PASSWORD,
		GET_PUBLIC_LOBBIES,
		SET_PLAYER_USERNAME,
		SET_PLAYER_DATA,
		ERASE_PLAYER_DATA,
		SET_CONNECT_TIME,
		SET_SETTING,
		SET_CLIENT_ID,
		KICK_PLAYER,
		CHANGE_PASSWORD,
		GET_PUBLIC_LOBBY
	}

	enum MESSAGE_TYPE
	{
		CRITICAL_ERROR,
		CLIENT_ID_RECEIVED,
		CLIENT_KEY_RECEIVED,
		INVALID_PUBLIC_KEY,
		SET_NODE_PATH_CACHE,
		ERASE_NODE_PATH_CACHE,
		SET_NAME_CACHE,
		ERASE_NAME_CACHE,
		SET_MC_OWNER,
		HOST_CHANGED,
		LOBBY_CREATED,
		LOBBY_CREATION_FAILED,
		LOBBY_JOINED,
		SWITCH_SERVER,
		LOBBY_JOIN_FAILED,
		LOBBIES_RECEIVED,
		LOBBY_DATA_RECEIVED,
		LOBBY_DATA_CHANGED,
		LOBBY_TAGS_CHANGED,
		PLAYER_DATA_RECEIVED,
		PLAYER_DATA_CHANGED,
		CLIENT_JOINED,
		CLIENT_LEFT,
		SET_CONNECT_TIME,
		SET_SENDER_ID,
		SET_DATA_USAGE,
		KICKED,
		LOBBY_RECEIVED
	}

	enum SETTING
	{
		API_VERSION,
		USE_SENDER_ID,
	}

	enum DATA
	{
		REQUEST_TYPE,
		NAME,
		VALUE,
		TARGET_CLIENT = 3,
	}

	enum LOBBY_DATA
	{
		NAME = 1,
		PASSWORD = 2,
		PARAMETERS = 1,
		VISIBILITY = 1,
		VALUE = 2,
	}

	enum FUNCTION_DATA
	{
		NODE_PATH = 1,
		NAME = 2,
		PARAMETERS = 4
	}

	enum VAR_DATA
	{
		NODE_PATH = 1,
		NAME = 2,
		VALUE = 4
	}

	enum MESSAGE_DATA
	{
		TYPE = 1,
		VALUE = 2,
		ERROR = 3,
		VALUE2 = 3,
	}

	enum CRITICAL_ERROR
	{
		LOBBY_DATA_FULL,
		LOBBY_TAGS_FULL,
		PLAYER_DATA_FULL,
		REQUEST_TOO_LARGE,
	}

	enum INTERNAL_MESSAGE
	{
		LOBBY_UPDATED,
		LOBBY_DELETED,
		REQUEST_LOBBIES,
		INCREASE_DATA_USAGE,
	}

	enum CONNECTION_FAILED
	{
		INVALID_PUBLIC_KEY,
		TIMEOUT,
		LOCAL_PORT_ERROR,
	}

	enum LOBBY_CREATION_ERROR
	{
		LOBBY_ALREADY_EXISTS,
		NAME_TOO_SHORT,
		NAME_TOO_LONG,
		PASSWORD_TOO_LONG,
		TAGS_TOO_LARGE,
		DATA_TOO_LARGE,
		ON_COOLDOWN,
		LOCAL_PORT_ERROR,
	}

	enum LOBBY_JOIN_ERROR
	{
		LOBBY_DOES_NOT_EXIST,
		LOBBY_IS_CLOSED,
		LOBBY_IS_FULL,
		INCORRECT_PASSWORD,
		DUPLICATE_USERNAME,
	}

	enum NODE_REPLICATION_SETTINGS
	{
		INSTANTIATOR,
		SYNC_STARTING_CHANGES,
		EXCLUDED_PROPERTIES,
		SCENE,
		TARGET,
		ORIGINAL_PROPERTIES,
	}

	enum NODE_REPLICATION_DATA
	{
		ID,
		CHANGED_PROPERTIES,
	}

	enum ACCOUNT_CREATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		STORAGE_FULL,
		INVALID_EMAIL,
		INVALID_USERNAME,
		EMAIL_ALREADY_EXISTS,
		USERNAME_ALREADY_EXISTS,
		USERNAME_TOO_SHORT,
		USERNAME_TOO_LONG,
		PASSWORD_TOO_SHORT,
		PASSWORD_TOO_LONG,
	}

	enum ACCOUNT_DELETION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_PASSWORD_INCORRECT,
	}

	enum RESEND_VERIFICATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		VERIFICATION_DISABLED,
		ON_COOLDOWN,
		ALREADY_VERIFIED,
		EMAIL_OR_PASSWORD_INCORRECT,
		BANNED,
	}

	enum ACCOUNT_VERIFICATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		INCORRECT_CODE,
		CODE_EXPIRED,
		ALREADY_VERIFIED,
		BANNED,
	}

	enum IS_VERIFIED_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		USER_DOESNT_EXIST,
	}

	enum LOGIN_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_PASSWORD_INCORRECT,
		NOT_VERIFIED,
		EXPIRED_SESSION,
		BANNED,
	}

	enum LOGOUT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	enum CHANGE_PASSWORD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		ON_COOLDOWN,
		EMAIL_OR_PASSWORD_INCORRECT,
		NOT_VERIFIED,
		BANNED,
	}

	enum CHANGE_USERNAME_RESPONSE_CODE
	{

		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		ON_COOLDOWN,
		USERNAME_ALREADY_EXISTS,
		USERNAME_TOO_SHORT,
		USERNAME_TOO_LONG,
		INVALID_USERNAME
	}

	enum RESET_PASSWORD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_CODE_INCORRECT,
		CODE_EXPIRED,
	}

	enum REQUEST_PASSWORD_RESET_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		ON_COOLDOWN,
		EMAIL_DOESNT_EXIST,
		BANNED,
	}

	enum SET_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
	}

	enum GET_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	enum BROWSE_PLAYER_COLLECTION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	enum SET_EXTERNAL_VISIBLE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}


	enum HAS_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	enum DELETE_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	enum REPORT_USER_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		REPORT_TOO_LONG,
		TOO_MANY_REPORTS,
		USER_DOESNT_EXIST,
	}

	enum SUBMIT_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		LEADERBOARD_DOESNT_EXIST
	}

	enum DELETE_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST
	}

	enum GET_LEADERBOARDS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN
	}

	enum HAS_LEADERBOARD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN
	}

	enum BROWSE_LEADERBOARD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST
	}

	enum GET_LEADERBOARD_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST,
		USER_DOESNT_EXIST
	}

	enum ADD_FRIEND_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		USER_DOESNT_EXIST,
		FRIEND_ALREADY_ADDED,
		FRIENDS_LIST_FULL,
	}

	enum ACCEPT_FRIEND_REQUEST_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		FRIEND_NOT_FOUND,
	}

	enum GET_FRIENDS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	enum GET_FRIEND_STATUS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		USER_DOESNT_EXIST,
	}

	enum FRIEND_STATUS
	{
		NONE,
		PENDING,
		FRIEND
	}

	enum LINK_STEAM_ACCOUNT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		ALREADY_LINKED,
		STEAM_ERROR,
	}

	enum UNLINK_STEAM_ACCOUNT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STEAM_ERROR,
	}

	enum STEAM_LOGIN_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		STEAM_ERROR,
		NOT_LINKED,
		NOT_VERIFIED,
		BANNED,
	}

	// API SUPPORT LIST
	// 0 - NOTHING
	// 1 - SENDER ID SUPPORT

}